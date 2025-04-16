#!/usr/bin/perl -w

# OWChallenge.pl -

# Copyright (c) 2023 Bob Upshaw.  This software is covered under the Open Source MIT License 

####################
# pragmas
####################
use DBI;
use strict;
use sigtrap;
use warnings;
use HTTP::Tiny;

####################
# PERL modules and initialization to help compiling
####################
use File::Basename;
###use File::Path qw( make_path );
use POSIX qw(strftime);
use Cwd 'abs_path';
my $appProgName;
my $appDirName;     # directory containing the application we're running
my $appRootDir;		# directory containing the appDirName directory
my $sourceData;		# full path of directory containing the "source data" which we process to create the generated files
my $dateTimeFormat;
my $currentDateTime;	# the date/time we start this application
my $yearFormat;
my ($dateFormat, $currentDate);		# just the year-mm-dd
my $startYear;		# the earliest year for which we start accumulating OW swims
my $endYear;		# the latest year for which we accumulate OW swims
# $yearBeingProcessed is important:  it is the DEFAULT final year from which OW swims are being accumulated.
#	It's the year this app is running. It is computed below.
my $yearBeingProcessed;
my %cumulations;	# $cumulations{ID} - set to ID, which is the USMS Swimmer ID of the swimmer.
					# $cumulations{ID-YEAR} - count of OW swims for swimmer with USMS swimmer id of ID during the
					#	year YEAR.
					# $cumulations{ID-YEAR-SUITCAT} - count of OW swims for swimmer with USMS swimmer id of ID during the
					#	year YEAR when swimming with suit in category SUITCAT (1 or 2).
					# $cumulations{ID-0} - count of OW swimms for swimmer with USMS swimmer id of ID over 
					#	all the years processed so far.
					# $cumulations{ID-distance-YEAR} - sum of total miles swum for swimmer with 
					#	USMS swimmer id of ID during the year YEAR.
					# $cumulations{ID-team-YEAR} - the team for this swimmer for this year
					# $cumulations{ID-distance-0} - sum of total miles swum for swimmer with 
					#	USMS swimmer id of ID over all the years processed so far.
					# $cumulations{ID-name} - first M last of swimmer with USMS swimmer id of ID
					# $cumulations{ID-gender} - their gender, one of M or F
					# $cumulations{ID-YOB} - their year of birth, e.g. 1992
my %totalNumSwimmers;	# this hash contains the total number of swimmers seen in specific years, where:
		# $totalNumSwimmers{"xxxx"} contains the total number of swimmers in the year xxxx, and
		# $totalNumSwimmers{"all"} contains the total number of unique swimmers seen in all years processed.
my $INVALID_SWIMMERS_NAME;

my $accessLogHandle;




# forward declarations:
sub GetSwimmersName( $$ );
sub InitializeSwimmer( $$$$$ );
sub InitializeWorkingYear( $$$ );
sub InitializeTotalNumberSwimmers( $$$ );
sub UpdateCategoryCount( $$$$ );
sub InitializeCategories( $$$ );
sub GetPathName($$$);
sub PopulateTemplateDirsArray($);
sub GenerateHTMLResults($$$);




BEGIN {
	# get the date/time we're starting:
	$dateTimeFormat = '%a %b %d %Y %Z %I:%M:%S %p';
	$currentDateTime = strftime $dateTimeFormat, localtime();
	$dateFormat = '%Y-%m-%d';		# year-mm-dd
	$currentDate = strftime $dateFormat, localtime();
	$yearFormat = '%Y';
	$yearBeingProcessed = strftime $yearFormat, localtime();			# the current year
	
#	print "currentDateTime=$currentDateTime, localtime=" . scalar localtime . "\n";
	
	# Get the name of the program we're running:
	$appProgName = basename( $0 );
	die( "Can't determine the name of the program being run - did you use/require 'File::Basename' and its prerequisites?")
		if( (!defined $appProgName) || ($appProgName eq "") );
	
	# The program we're running is (by default) in a directory parallel to the directory that will contain
	# the generated results, but this can be changed by specifying a value for the GeneratedFiles in the property file.
	# The directory containing this program is called the "appDirName".
	# The appDirName is important because it's what we use to find everything else we need.  In particular, we
	# need to find and process the 'properties.txt' file (also contained in the appDirName), and from that
	# file we determine various operating parameters, which can override defaults set below, and also
	# set required values that are NOT set below.
	#
	$appDirName = dirname( $0 );     # directory containing the application we're running, e.g.
										# e.g. /Users/bobup/Development/PacificMasters/PMSOWPoints/Code/
										# or ./Code/
	die( "${appProgName}:: Can't determine our running directory - did you use 'File::Basename' and its prerequisites?")
		if( (!defined $appDirName) || ($appDirName eq "") );
	# convert our application directory into a full path:
	$appDirName = abs_path( $appDirName );		# now we're sure it begins with a '/'

	# The 'appRootDir' is the parent directory of the appDirName:
	$appRootDir = dirname($appDirName);		# e.g. /Users/bobup/Development/PacificMasters/PMSOWPoints/
	die( "${appProgName}:: The parent directory of '$appDirName' is not a directory! (A permission problem?)" )
		if( !-d $appRootDir );
	
	# initialize our source data directory name:
	$sourceData = "$appRootDir/SourceData";	
	
	# these should get defined in the properties file but these are defaults:
	$startYear = 2021;
	$endYear = $yearBeingProcessed;		# default - can change below (and in property file)

	$INVALID_SWIMMERS_NAME = "(unknown name)";

}

# access log...
###make_path( "../Access/OWChallenge/", {mode => '0750'} );
###open( $accessLogHandle, ">>", "../Access/OWChallenge/access.txt" );
###print $accessLogHandle "Accessed on: $currentDateTime\n";

####################
# Usage string
####################

my $UsageString = <<bup
Usage:  
	$appProgName [[Syear][-Eyear]]
	[-dDebugValue]
	[-tPROPERTYFILE]
	[-sSOURCEDATADIR]
	[-gGENERATEDFILESDIR]
	[-h]
where all arguments are optional:
	year-year - if present can be in one of these forms:
			Syear
			Syear-Eyear
			-Eyear
		where Syear is the "start year", and Eyear is the "end year".  We will process all years
		between Syear and Eyear, inclusive. If Syear is not supplied then 2021 is used.  If Eyear is not
		supplied then the current year is used.  Syear cannot be less than 2008. 
		Eyear cannot be greater than the current year. See $startYear and $endYear in the code below.
	-dDebugValue - a value 0 or greater.  The larger the value, the more debug stuff printed to the log
	-tPROPERTYFILE - the FULL PATH NAME of the property.txt file.  The default is appDirName/properties.txt, where
		'appDirName' is the directory holding this script, and
		'properties.txt' is the name of the properties files for this script.
	-sSOURCEDATADIR is the full path name of the SourceData directory
	-gGENERATEDFILES is the full path name of the GeneratedFiles directory
	-h - display help text then quit

Compute the total number of open water swims performed by each PMS swimmer during the
range of years from the "StartYear" through "EndYear". The default StartYear is 2021, but this can be overridden 
by the property file, and both are overridden by an argument passed to this app, if any. The default endYear
is the current year, but this can be overridden by the property file, and both are overridden by an argument 
passed to this app.
Uses the SwimmerEventHistory table to collect all swims for each swimmer during those years, and then
uses the RSIND table for those years to map USMSSwimmerIds to swimmer names. 
bup
;



####################
# included modules
####################

use lib "$appDirName/../../PMSPerlModules";
use PMSConstants;
require PMSUtil;
use PMS_ImportPMSData;     # code to manage PMS data containing every PMS swimmer, their club, and their reg#
require PMSLogging;
require PMSStruct;
require PMS_MySqlSupport;
require PMSMacros;
require PMSTemplate;
#require History_MySqlSupport;
use lib "$appDirName/../../PMSOWPoints/Code/OWPerlModules";
require OW_MySqlSupport;
use Data::Dumper;

####################
# hard-coded program options.  Change them if you want the program to behave differently
####################
							


####################
# internal subroutines
####################

####################
# global flags and variables
####################

PMSStruct::GetMacrosRef()->{"currentDateTime"} = $currentDateTime;
PMSStruct::GetMacrosRef()->{"currentDate"} = $currentDate;


# define the generation date, which we rarely have a reason to change from "now", but this and the
# currentDate can be overridden in the property file below:
PMSStruct::GetMacrosRef()->{"generateDate"} = PMSStruct::GetMacrosRef()->{"currentDateTime"};

# the $groupDoingTheProcessing is the orginazation whose results are being processed.
# Set the default here:
my $groupDoingTheProcessing = "PacMasters"; 

# more defaults...
my $propertiesDir = $appDirName;	# Directory holding the properties.txt file.
my $propertiesFileName = "properties.txt";

# We also use the AppDirName in the properties file (it can't change)
PMSStruct::GetMacrosRef()->{"AppDirName"} = $appDirName;	# directory containing the application we're running

my $generatedFiles;


############################################################################################################
# get to work - initialize the program
############################################################################################################
# get the arguments:
my $arg;
my $numErrors = 0;
my $helpRequested = 0;
while( defined( $arg = shift ) ) {
	my $flag = $arg;
	my $value = PMSUtil::trim($arg);
	if( $value =~ m/^-/ ) {
		# we have a flag in the form '-x...'
		$flag =~ s/(-.).*$/$1/;
		$value =~ s/^-.//;
		if( $flag !~ m/^-.$/ ) {
			print "${appProgName}:: FATAL ERROR:  Invalid flag: '$arg'\n";
			$numErrors++;
		}
		SWITCH: {
	        if( $flag =~ m/^-E$/ ) {
				# we have the case of 	$appProgName -Eyear ...
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-E')
				$endYear = $value;
				last SWITCH;
	        }
	        if( $flag =~ m/^-d$/ ) {$PMSConstants::debug=$value; last SWITCH; }
	        if( $flag =~ m/^-t$/ ) {
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-t')
				$propertiesDir = dirname($value);
				$propertiesFileName = basename($value);
				last SWITCH;
	        }
	        if( $flag =~ m/^-s$/ ) {
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-s')
				$sourceData = $value;
				last SWITCH;
	        }
	        if( $flag =~ m/^-g$/ ) {
	        	$value = $arg;			# maintain the case of chars
				$value =~ s/^-.//;		# get rid of flag ('-g')
				$generatedFiles = $value;
				PMSStruct::GetMacrosRef()->{"GeneratedFiles"} = $generatedFiles;
				last SWITCH;
	        }
			if( $flag =~ m/^-h$/ ) {
				print $UsageString;
				$helpRequested = 1;
				last SWITCH; 
			}
			print "${appProgName}:: FATAL ERROR:  Invalid flag: '$arg'\n";
			$numErrors++;
		}
	} else {
		# we don't have a flag - must be the year(s) to accumulate
		if( $value ne "" ) {
			$value =~ m/^(\d\d\d\d)(-(\d\d\d\d))?$/;
			my $Syear = $1;
			my $Eyear = $3;
			if( !defined $Syear ) {
				$Syear = $startYear;
			}
			if( !defined $Eyear ) {
				$Eyear = $endYear;
			}
			$startYear = $Syear;
			$endYear = $Eyear;
			
			#print "startYear='$startYear', endYear='$endYear'\n";
		}
	}
} # end of while - done getting command line args

if( 
	($startYear > $endYear) ||
	($startYear < 2008) ||
	($endYear > $yearBeingProcessed)
	) {
	print "${appProgName}:: FATAL ERROR:  Invalid value for start year ($startYear) or " .
		"end year ($endYear)\n";
	$numErrors++;
}


if( $helpRequested ) {
	exit(1);       # non-zero because we didn't do anything useful!
}
# if we got any errors we're going to give up:
if( $numErrors > 0 ) {
	print "${appProgName}:: ABORT!:  $numErrors errors found - giving up!\n";
	exit;
}


PMSStruct::GetMacrosRef()->{"YearBeingProcessed"} = $yearBeingProcessed;
PMSStruct::GetMacrosRef()->{"EndYear"} = $endYear;
PMSStruct::GetMacrosRef()->{"StartYear"} = $startYear;

$generatedFiles = PMSStruct::GetMacrosRef()->{"GeneratedFiles"};
if( !defined $generatedFiles ) {
	# DEFAULT:  Generated files based on passed 'appRootDir':
	$generatedFiles = "$appRootDir/GeneratedFiles";	# directory location where we'll put all files we generate 
}
# make sure our directory name ends with a '/':
if( $generatedFiles !~ m,/$, ) {
	$generatedFiles .= "/";
	PMSStruct::GetMacrosRef()->{"GeneratedFiles"} = $generatedFiles;
}

# The $yearGroup is the concatenation of 'yyyy' and 'group' where:
#	yyyy - is USUALLY the year whose results are being processed, e.g. 2016 (but not required to be a year)
#	group - is USUALLY the group who generated those results, e.g. PacMasters (but that's not required, either)
#			Other possible groups have been:
#				USA
#				USMS
#			when we've done similar processing for those organizations.
# This value is used when constructing the names of generated fiels, and is also slightly modified and used
# as titles in generated files.  Thus, if the yearGroup is some other text it's OK - as long as the file
# names and titles make sense.
my $yearGroup = $yearBeingProcessed  . $groupDoingTheProcessing;   		# e.g. 2016PacMasters

my $simpleLogFileName = $yearGroup . "OWChallengeResultsLog.txt";				# file name of the log file
my $generatedLogFileName = $generatedFiles . $simpleLogFileName;		# full path name of the log file we'll generate

# open the log file so we can log errors and debugging info:
if( my $tmp = PMSLogging::InitLogging( $generatedLogFileName )) { die $tmp; }

PMSLogging::PrintLog( "", "", "$appProgName started on $currentDateTime...", 1 );
PMSLogging::PrintLog( "", "", "  ...with the app root of '$appRootDir'...", 1 );

# keep the value of $sourceData as a macro for convenience, and also because we use it in the properties.txt file
# (We might also change it in the properties file)
PMSStruct::GetMacrosRef()->{"SourceData"} = $sourceData;
PMSLogging::PrintLog( "", "", "  ...and the SourceData directory of '$sourceData'...", 1 );

# Read the properties.txt file and set the necessary properties by setting name/values in 
# the %macros hash which is accessed by the reference returned by PMSStruct::GetMacrosRef().  For example,
# if the macro "numSwimsToConsider" is set in the properties file, then it's value is retrieved by 
#	my $numSwimsWeWillConsider = PMSStruct::GetMacrosRef()->{"numSwimsToConsider"};
# after the following call to GetProperties();
# Note that the full path name of the properties file is set above, either to its default value when
# $propertiesDir and $propertiesFileName are initialized above, or to a non-default value by an
# argument to this script.
PMSLogging::PrintLog( "", "", "  ...and reading properties from '$propertiesDir/$propertiesFileName'", 1 );

PMSMacros::GetProperties( $propertiesDir, $propertiesFileName, $yearBeingProcessed );

# some initial values could have changed in the above property file, so we're going to
# re-initialize those values:
$endYear = PMSStruct::GetMacrosRef()->{"EndYear"};
$startYear = PMSStruct::GetMacrosRef()->{"StartYear"};



		

# at this point we INSIST that $yearBeingProcessed is a reasonable year:
if( ($yearBeingProcessed !~ m/^\d\d\d\d$/) ||
	( ($yearBeingProcessed < 2008) || ($yearBeingProcessed > 2030) ) ) {
	die( "${appProgName}::  The year being processed ('$yearBeingProcessed') is invalid - ABORT!");
}
PMSLogging::PrintLog( "", "", "  ...theYearBeingProcessed set to: '$yearBeingProcessed'", 1 );

# just in case the SourceData changed get the new value:
$sourceData = PMSStruct::GetMacrosRef()->{"SourceData"};

# Next, initialize the database parameters:
#                               'unique db id',  host,       database,            user,      password
# initialize the "normal" database used when processing a set of OW result files:
PMS_MySqlSupport::SetSqlParameters( 'default',
	PMSStruct::GetMacrosRef()->{"dbHost"},
	PMSStruct::GetMacrosRef()->{"dbName"},
	PMSStruct::GetMacrosRef()->{"dbUser"},
	PMSStruct::GetMacrosRef()->{"dbPass"} );

# now that we've processed args to this script, and read its property file, we have ALMOST all the operating
# parameters we need.  Create others based on what we know:

# Define the title used inside generated pages:
#PMSStruct::GetMacrosRef()->{PageTitle} = $yearBeingProcessed . " " . $groupDoingTheProcessing;   # e.g. 2016 PacMasters


my $simpleGeneratedFileName = $yearGroup . "OWChallengeResults.html";			# file name of the HTML file with accumulated individual
																				# results we're generating
my $generatedFileName = $generatedFiles . $simpleGeneratedFileName;		# full path name of HTML file with accumulated individual 
PMSStruct::GetMacrosRef()->{"generatedFileName"} = $generatedFileName;
PMSStruct::GetMacrosRef()->{"simpleGeneratedFileName"} = $simpleGeneratedFileName;
PMSLogging::PrintLog( "", "", "  ...generatedFiles set to: '$generatedFiles'", 1 );
PMSLogging::PrintLog( "", "", "", 1 );
my $simplePreTroutGeneratedFileName = $yearGroup . "OWPreTroutOWChallengeResults.html";		# used for pre-trout swimmers.
my $preTroutGeneratedFileName = $generatedFiles . $simplePreTroutGeneratedFileName;			# full path name

# Everything looks good so far.  Now it's time to initialize our connection to the MySQL database
my $dbh = PMS_MySqlSupport::GetMySqlHandle();
if( !$dbh ) {
	PMSLogging::DumpError( "", 0, "FATAL ERROR #1:  Unable to get a database connection.  See the logs", 1 );
	die( "The above error was FATAL!\n" );
}


# swimmer data (not race results) directory
my $PMSSwimmerData = "$sourceData/PMSSwimmerData/";



if( 0 ) {
# we need to read some swimmer data
# get the full path name to the merged members data file (contains a list of all PMS members who have
# two or more swimmer ids.)
my $fileNamePattern = PMSStruct::GetMacrosRef()->{"MergedMemberFileNamePattern"};
my $mergedMemberDataFile = PMSUtil::GetFullFileNameFromPattern( $fileNamePattern, $PMSSwimmerData, "Merged Member" );
if( defined $mergedMemberDataFile ) {
	# we have a merged member file - is it newer than the last one?  should we use it?  We'll decide here:
	PMS_ImportPMSData::GetMergedMembers( $mergedMemberDataFile, $yearBeingProcessed );
}

}

# before we start we're going to figure out the current OW Points year.
my $currentOWPointsYear = "";
my $query = "SELECT * FROM Events LIMIT 1";
my ( $sth, $rv ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
if( defined( my $resultHash = $sth->fetchrow_hashref ) ) {
	my $date = $resultHash->{'Date'};
	$date =~ s/-.*$//;
	$currentOWPointsYear = $date;
} else {
	PMSLogging::DumpError( "", 0, "FATAL ERROR #2:  Unable to fetch a database row.  See the logs", 1 );
	die( "The above error was FATAL!\n" );
}





# write some initial logging info to the log file
PMSLogging::PrintLog( "", "", "Processing of $appProgName Begun: " . PMSStruct::GetMacrosRef()->{"currentDateTime"} . " ", 1 );
PMSLogging::PrintLog( "", "", "The range of years being processed: '$startYear' - '$endYear'", 1 );
PMSLogging::PrintLog( "", "", "The current OW Points year is '$currentOWPointsYear'", 1 );
PMSLogging::PrintLogNoNL( 0, 0, "debug set to: $PMSConstants::debug ", 1 );
	if( $PMSConstants::debug == 0 ) {PMSLogging::PrintLog("", "", "(Debugging turned off)", 1)} 
	else {PMSLogging::PrintLog("", "", "(Debugging turned on)", 1)}

# debugging....
if( $PMSConstants::debug > 0 ) {
	PMSLogging::DumpMacros( "%macros after GetProperties():");
}



###########################################################################################################################
###########################################################################################################################
###########################################################################################################################
# get to work
###########################################################################################################################
###########################################################################################################################
###########################################################################################################################
# For debugging we're going to print out the id's of each swimmer who have a minimum or more number of
# OW swims accumulated up to each year we're analyzing. This minimum is given by $minDebugPoints defined
# below.  The lower the minumum the more swimmers that are reported. Set the minimum very high to turn
# off debugging.
my $minDebugPoints = 9999;
my $debugSwimmerId = "xxxxx";

my $categoriesRef = PMSMacros::GetCategoryArrayRef();
my $numCategories = InitializeCategories( $categoriesRef, $startYear, $endYear );

if( $PMSConstants::debug > 0 ) {
	print "Debugging: Categories:\n";
	foreach my $i (0..$numCategories) {
		print "Name: " . $categoriesRef->[$i]{"name"} . ", ";
		print "minCount: " . $categoriesRef->[$i]{"minCount"} . ", ";
		print "maxCount: " . $categoriesRef->[$i]{"maxCount"} . "\n";
	}
}

InitializeTotalNumberSwimmers( \%totalNumSwimmers, $startYear, $endYear );

# Analyze each year individually:
foreach my $workingYear ( $startYear..$endYear ) {
	my( $sth, $rv );
	my $resultHash;
	my ($selectStr, $selectDistanceStr);
	# make sure we're ready to process this year:
	my $RsindTableExists = PMS_MySqlSupport::DoesTableExist( "RSIDN_$workingYear" );
	if( $RsindTableExists == 1 ) {
		# yes! this year has processed at least one OW event. 
		# initialize our counts for the working year:
		InitializeWorkingYear( $categoriesRef, $numCategories, $workingYear );

		# get a list of all events swum during the working year. How we do that depends on whether or not
		# the workingYear is the current OWPoints year or a historical year:
		if( $workingYear == $currentOWPointsYear ) {
			# if we're processing OW swims for the current OWPoints year we can't look in the history
			# tables, but instead we'll look in the current OW Points tables
			PMSLogging::PrintLog( "", "", "workingYear = '$workingYear' which is the current OW Points year", 1 );
			$selectStr = "SELECT RegNum, Swim.EventId as eventid, Events.Category FROM " .
				"RegNums Join Swim Join Events WHERE Swim.SwimmerId = RegNums.SwimmerId " .
				"AND Events.EventId = Swim.EventId " .
				"AND RegNum LIKE '38%' " .
				"ORDER BY RegNum";
			# NOTE: Above "AND RegNum LIKE '38%'" filters out non-PMS
			$selectDistanceStr = "SELECT Distance from Events where EventId = xxxx";
		} else {
			# use our OW history
			PMSLogging::PrintLog( "", "", "workingYear = '$workingYear'", 1 );
			$selectStr = "SELECT USMSSwimmerId, UniqueEventId as eventid, Category FROM SwimmerEventHistory WHERE Date
				LIKE '$workingYear%' ORDER BY USMSSwimmerId";
			# NOTE: Above query will only find PMS swimmers because that's all we put into the history table.
			$selectDistanceStr = "SELECT Distance from EventHistory where UniqueEventID = xxxx";
		}

		#print "usmsSwimmerId: '$usmsSwimmerId', 1st query; '$selectStr'\n";
		( $sth, $rv ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $selectStr );
		# each event swum represents a single swim by a single swimmer in a specific year ($workingYear). 
		# Increment the number of swims for the working year for each specific swimmer:
		my $selectDistanceStrCopy = $selectDistanceStr;
		while( defined( $resultHash = $sth->fetchrow_hashref ) ) {
			# process the next swimmer in this working year
			$selectDistanceStr = $selectDistanceStrCopy;
			my $regNum = $resultHash->{'RegNum'};
			my $usmsSwimmerId;
			if( defined $regNum ) {
				# the $workingYear == current OWPoints year...
				# 10nov2024: Sometimes the OW results don't have a real regnum for a swimmer.  E.g. OEVT, or the
				# results just don't give a regnum (empty field).  In these cases we just ignore the swimmer.
				if( $regNum =~ m/^\d/ ) {
					# we got a regnum - construct the usmsSwimmerId
					($usmsSwimmerId) = $regNum =~ m/....-(.*)$/;
					if( $usmsSwimmerId eq $debugSwimmerId ) {
						print "workingYear == current OW Points year:  usmsSwimmerId: '$usmsSwimmerId', regNum='$regNum'\n";
					}
				} else {
					# we're going to ignore this swimmer
					$regNum = undef;
				}
			} else {
				# we didn't get a regnum - must have used the OW history which only gives us the usmsSwimmerId. 
				# construct our own "regnum".
				$usmsSwimmerId = $resultHash->{'USMSSwimmerId'};
				if( defined $usmsSwimmerId ) {
					$regNum = "xxxx-" . $usmsSwimmerId;
					if( $usmsSwimmerId eq $debugSwimmerId ) {
						print "workingYear NE current OW Points year:  usmsSwimmerId: '$usmsSwimmerId', regNum='$regNum'\n";
					}
				} # else leave the $regNum undefined and ignore this swimmer...
			}
		
			if( defined $regNum ) {
				# we've got a swimmer to process
				my $eventid = $resultHash->{'eventid'};
				my $suitCat = $resultHash->{'Category'};
				if( $usmsSwimmerId eq $debugSwimmerId ) {
					print "usmsSwimmerId: '$usmsSwimmerId', eventid='$eventid', suitCat='$suitCat'. 1st query; '$selectStr'\n";
				}
				# the following InitializeSwimmer() does nothing if we've seen this swimmer before:
				my $isValidSwimmer = InitializeSwimmer( \%cumulations, $usmsSwimmerId, $startYear, $endYear, $workingYear );
				if( $isValidSwimmer ) {
					$cumulations{ $usmsSwimmerId . "-$workingYear"}++;
					$cumulations{ $usmsSwimmerId . "-0"}++;		# total swims for this swimmer for all years up to and including this working Year
					# get the distance of this Swim
					$selectDistanceStr =~ s/xxxx/$eventid/;
					if( $usmsSwimmerId eq $debugSwimmerId ) {
						print "usmsSwimmerId: '$usmsSwimmerId', distance query; '$selectDistanceStr'\n";
					}
					my( $sth2, $rv2 ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $selectDistanceStr );
					my $resultHash2;
					if( defined( $resultHash2 = $sth2->fetchrow_hashref ) ) {
						my $distance = $resultHash2->{'Distance'};
						if( $usmsSwimmerId eq $debugSwimmerId ) {
							print "year: $workingYear, eventid: $eventid, distance=$distance, cat=$suitCat\n";
							print "BEFORE: cumulations{$usmsSwimmerId-$workingYear-$suitCat} = " . 
								$cumulations{ $usmsSwimmerId . "-$workingYear-$suitCat"}  . "\n";
						}
						$cumulations{ $usmsSwimmerId . "-$workingYear-$suitCat"}++;
						if( $usmsSwimmerId eq $debugSwimmerId ) {
							print "AFTER: cumulations{$usmsSwimmerId-$workingYear-$suitCat} = " . 
								$cumulations{ $usmsSwimmerId . "-$workingYear-$suitCat"}  . "\n";
						}
						$cumulations{ $usmsSwimmerId . "-distance-$workingYear"} += $distance;
						$cumulations{ $usmsSwimmerId . "-distance-0"} += $distance;
						if( $usmsSwimmerId eq $debugSwimmerId ) {
							print "year: $workingYear, eventid: $eventid, distance=$distance, total so far=" . 
								$cumulations{ $usmsSwimmerId . "-distance-$workingYear"} . "\n";
						}
						# get the team this swimmer swam for (if we don't have it already):
						my $swimmersTeamForThisYear = $cumulations{ $usmsSwimmerId . "-team-$workingYear"};
						if( $swimmersTeamForThisYear eq "?" ) {
							# get the team this swimmer swam for during this year:
							my $selectTeam = "SELECT RegisteredTeamInitialsStr as Team from RSIDN_$workingYear " .
								"WHERE USMSSwimmerId='$usmsSwimmerId'";
							my( $sth3, $rv3 ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $selectTeam );
							if( defined( my $resultHash3 = $sth3->fetchrow_hashref ) ) {
								# remember this swimmer's team
								$cumulations{ $usmsSwimmerId . "-team-$workingYear"} = $resultHash3->{'Team'};
								if( $usmsSwimmerId eq $debugSwimmerId ) {
									print "year: $workingYear, query='$selectTeam', team=$resultHash3->{'Team'}\n";
								} 
							} else {
								# we couldn't find the team this swimmer swam for!
								PMSLogging::DumpWarning( "", 0, "${appProgName}: Unable to find Team for " .
									"USMSId '$usmsSwimmerId in RSIND. Query='$selectTeam'", 1 );
								$cumulations{ $usmsSwimmerId . "-team-$workingYear"} = "(unknown)";
							}
						} # end of get the team...
					}
				} # end of if( $isValidSwimmer ...
			} # end of processing a swimmer
		} # end of processing all swimmers for this working year


		foreach my $id (keys %cumulations) {
			if( index( $id, "-" ) == -1 ) {
				# $id is the key to a hash for a unique swimmer
				if( $cumulations{"$id-0"} > 0 ) {
					if( $cumulations{ $id . "-$workingYear"} > 0 ) {
						$totalNumSwimmers{$workingYear}++;	# add this swimmer to the count of swimmers who swam OW this year
					}
					UpdateCategoryCount( $categoriesRef, $numCategories, $workingYear, $cumulations{"$id-0"} );
					if( $PMSConstants::debug > 0 ) {
						# debugging only: print the swimmer id's of all swimmers with at least $minDebugPoints points
						if( $cumulations{"$id-0"} >= $minDebugPoints ) {
							my $years = "for the years $startYear through $workingYear";
							if( $workingYear == $startYear ) {
								$years = "for the year $startYear";
							}
							print $cumulations{$id . "-name"} . " ($id) has " . $cumulations{"$id-0"} . " OW swims $years.\n";
						}
					} # end debugging
				} # end of if( $cumulations{"$id-0"} > 0...
			}
		}
	
		print "  Number of swimmers for '$workingYear': $totalNumSwimmers{$workingYear}\n";

		if( $PMSConstants::debug > 0 ) {
			foreach my $i (0..$numCategories) {
				print "    Number of swimmers in the " . $categoriesRef->[$i]{"name"} . " category: " .
					$categoriesRef->[$i]{$workingYear . "-swimmers"} . "\n";
			}
		}
			
	} # end of Rsind table exists...
	else {
		# this working year doesn't have an RSIND file (yet?). We're going to skip it and all following years.
		PMSLogging::DumpWarning( "", 0, "${appProgName}: No RSIND file for the year '$workingYear'. Skipping this " .
			"year and any following.", 1 );
		$endYear = $workingYear - 1;
		PMSStruct::GetMacrosRef()->{"EndYear"} = $endYear;
		last;
	}
} # end of each working year...



# Now pass through our %cumulations hash table and get some numbers:

my $numChangedTeams = 0;
my $numChangedTeamsTroutOrBetter = 0;
foreach my $id (keys %cumulations) {
	if( index( $id, "-" ) == -1 ) {
		# $id is the key to a hash for a unique swimmer
		$totalNumSwimmers{"all"}++;
		if( 1 ) {
			# did we have any swimmers who changed teams during the time covered by this run of OWChallenge?
			my $team = undef;
			foreach my $workingYear ( $startYear..$endYear ) {
				if( $cumulations{$id . "-team-$workingYear"} ne "?" ) {
					if( defined $team ) {
						if( $cumulations{$id . "-team-$workingYear"} ne $team ) {
							# we found a swimmer who changed teams...
							# how many swims for this swimmer?
							my $numSwims = $cumulations{$id . "-0"};
							# how many swims required to get listed on our page?
							my $numMinSwims = $categoriesRef->[1]{"minCount"};
							if( $PMSConstants::debug >= 10 ) {
								if( $PMSConstants::debug >= 5 ) {
									print "Found a swimmer who changed teams in $workingYear from $team to " .
										$cumulations{$id . "-team-$workingYear"} . ": " .
										$cumulations{$id . "-name"} . "($numSwims swims)\n";
								}
								if( $PMSConstants::debug < 5 ) {
									if( $numSwims >= $numMinSwims ) {
										print "Found a swimmer who changed teams in $workingYear from $team to " .
											$cumulations{$id . "-team-$workingYear"} . ": " .
											$cumulations{$id . "-name"} . "($numSwims swims)\n";
									}
								}
							}
							$numChangedTeams++;
							if( $numSwims >= $numMinSwims ) {
								$numChangedTeamsTroutOrBetter++;
							}
							# we're done with this swimmer...
							last;
						} # else this swimmer's team didn't change
					} else {
						# this is the first time we found a team for this swimmer
						$team = $cumulations{$id . "-team-$workingYear"};
					}
				} # else this swimmer didn't swim this year
			} # end of foreach my $workingYear....
		}
	} # end of if( index( $id...
}

#if( $PMSConstants::debug > 0 ) {
	print "Total number of swimmers: $totalNumSwimmers{'all'}\n";
	print "Total number of swimmers who changed teams at least once from $startYear through $endYear: $numChangedTeams\n";
	print "Number of swimmers Trout or better who changed teams: $numChangedTeamsTroutOrBetter\n";
#}

# Generate the HTML output:
GenerateHTMLResults( $startYear, $endYear, \%cumulations );


print "Done with $appProgName\n\n";
exit 0;



###########################################################################################################################
###########################################################################################################################
###########################################################################################################################
# Subroutines
###########################################################################################################################
###########################################################################################################################
###########################################################################################################################

#		my ($swimmersName, $gender, $yearOfBirth) = GetSwimmersName( $usmsSwimmerId, $yearBeingProcessed );
sub GetSwimmersName( $$ ) {
	my ($USMSId, $yearBeingProcessed) = @_;
	my $name = $INVALID_SWIMMERS_NAME;
	my ($gender, $yearOfBirth) = ("?", "?");
	
	my $query = "SELECT FirstName, MiddleInitial, LastName, Gender, DateOfBirth FROM RSIDN_" . 
		$yearBeingProcessed . " WHERE USMSSwimmerId = '$USMSId'";
	
	my( $sth, $rv ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	my $resultHash = $sth->fetchrow_hashref;
	if( defined $resultHash ) {
		my $middleInitial = $resultHash->{'MiddleInitial'};
		if( $middleInitial ne "" ) {
			$middleInitial = "$middleInitial ";
		}
		$name = $resultHash->{'FirstName'} . " $middleInitial" . $resultHash->{'LastName'};
		$gender = $resultHash->{"Gender"};
		$yearOfBirth = $resultHash->{"DateOfBirth"};
		$yearOfBirth =~ s/-.*$//;
	} else {
		# this swimmer was not a PMS swimmer - we'll return $INVALID_SWIMMERS_NAME and ignore them.
		if( $PMSConstants::debug > 10 ) {
			print "ERROR in GetSwimmersName(): USMSId '$USMSId' not found in RSIND. Query='$query'\n";
		}
	}
	
	return ($name, $gender, $yearOfBirth);
} # end of GetSwimmersName()



# 		InitializeSwimmer( \%cumulations, $usmsSwimmerId, $startYear, $endYear );
# InitializeSwimmer - initialize the cumulative numbers for the passed swimmer if this is the
#		first time we've seen this swimmer. Otherwise, do nothing.
#
# RETURN:
#	$result = 0 if this was an invalid swimmer, non-zero otherwise.
sub InitializeSwimmer( $$$$$ ) {
	my ($cumulationsRef, $usmsSwimmerId, $startYear, $endYear, $yearBeingProcessed ) = @_;
	my $result = 1;		# assume the best
	
	if( !defined( $cumulationsRef->{$usmsSwimmerId} ) ) {
		# we haven't see this swimmer before - set all counts to 0 and initialize other fields for this swimmer
		my ($swimmersName, $gender, $yearOfBirth) = GetSwimmersName( $usmsSwimmerId, $yearBeingProcessed );
		if( $swimmersName eq $INVALID_SWIMMERS_NAME ) {
			# we're going to ignore this swimmer because we can't find them in our RSIND file.
			$result = 0;
		} else {
			$cumulationsRef->{$usmsSwimmerId} = $usmsSwimmerId;
			foreach my $workingYear ( $startYear..$endYear ) {
				$cumulationsRef->{"$usmsSwimmerId-$workingYear"} = 0;
				$cumulationsRef->{"$usmsSwimmerId-$workingYear-1"} = 0;
				$cumulationsRef->{"$usmsSwimmerId-$workingYear-2"} = 0;
				$cumulationsRef->{"$usmsSwimmerId-distance-$workingYear"} = 0;
				$cumulationsRef->{"$usmsSwimmerId-team-$workingYear"} = "?";
			}
			$cumulationsRef->{"$usmsSwimmerId-0"} = 0;
			$cumulationsRef->{"$usmsSwimmerId-distance-0"} = 0;
			$cumulationsRef->{ $usmsSwimmerId . "-name"} = $swimmersName;
			$cumulationsRef->{ $usmsSwimmerId . "-gender"} = $gender;
			$cumulationsRef->{ $usmsSwimmerId . "-YOB"} = $yearOfBirth;
		}
	}
	return $result;
} # end of InitializeSwimmer()



#		InitializeWorkingYear( $categoriesRef, $numCategories, $workingYear );
sub InitializeWorkingYear( $$$ ) {
	my ($categoriesRef, $numCategories, $workingYear) = @_;
	foreach my $i (0..$numCategories) {
		$categoriesRef->[$i]{"$workingYear-swimmers"} = 0;
	}
} # end of InitializeWorkingYear()



#  InitializeTotalNumberSwimmers( \%totalNumSwimmers, $startYear, $endYear );
sub InitializeTotalNumberSwimmers( $$$ ) {
	my ($totalNumSwimmersRef, $startYear, $endYear) = @_;
	foreach my $workingYear ( $startYear..$endYear ) {
		$totalNumSwimmersRef->{$workingYear} = 0;
	}
	$totalNumSwimmersRef->{"all"} = 0;
} # end of InitializeTotalNumberSwimmers()


# my $numCategories = InitializeCategories( $categoriesRef, $startYear, $endYear );

sub InitializeCategories( $$$ ) {
	my ($categoriesRef, $startYear, $endYear) = @_;
	my $numCategories = scalar( @{$categoriesRef} );		# start at 0!

	# here we're creating another (fake) category to help with further processing
	$categoriesRef->[$numCategories]{"name"} = "fake";
	$categoriesRef->[$numCategories]{"minCount"} = 99999999;
	$categoriesRef->[$numCategories]{"maxCount"} = 99999999;

	foreach my $i (0..$numCategories-1) {
		foreach my $workingYear ( $startYear..$endYear ) {
			$categoriesRef->[$i]{$workingYear . "-swimmers"} = 0;
		}
		$categoriesRef->[$i]{"maxCount"} = $categoriesRef->[$i+1]{"minCount"} - 1;
	}
	
	return $numCategories;
} # end of InitializeCategories()




#				UpdateCategoryCount( $categoriesRef, $numCategories, $workingYear, $cumulations{"$id-$workingYear"} );
#
# UpdateCategoryCount - Used to compute the number of swimmers in each category for each year.
# 
# PASSED:
#	$categoriesRef - reference to the @categories array (see PMSMacros)
#	$numCategories - number of different categories.
#	$workingYear - the year we're working on
#	$swimmersCount - the number of total OW swims by the unique swimmer we're working on considering
#		all swims from the startYear up to the $workingYear.
#
# SIDE EFFECTS:
#	$categories[categoryIndex]{"$workingYear-swimmers"} is updated to include the OW swims by the passed
#		swimmer up through the passed year.
#
sub UpdateCategoryCount( $$$$ ) {
	my( $categoriesRef, $numCategories, $workingYear, $swimmersCount ) = @_;
	if( $swimmersCount >= $categoriesRef->[1]{"minCount"} ) {
		# this swimmer has enough OW swims to belong to one of the REAL categories...
		foreach my $i (1..$numCategories) {
			if( ($swimmersCount >= $categoriesRef->[$i]{"minCount"}) &&
				($swimmersCount <= $categoriesRef->[$i]{"maxCount"}) ) {
					$categoriesRef->[$i]{$workingYear . "-swimmers"}++;
					last;
			}
		}
	} else {
		# else this swimmer doesn't have enough OW swims to affect a REAL category - count them as a pre-trout
		$categoriesRef->[0]{$workingYear . "-swimmers"}++;
	}
} # end of UpdateCategoryCount()



# GenerateHTMLResults - main driver for the generation of the HTML page showing the 
#	calculated Open Water Challenge data.  All data comes from populated structures above.
#
# PASSED:
#	$startYear - 
#	$endYear -
#	$cumulationsRef -
#	
#	Plus, we use data from populated structures above
#
# RETURNED:
#	n/a
#
# SIDE EFFECTS:
#	Various files are written
#
sub GenerateHTMLResults( $$$ ) {
	my ($startYear, $endYear, $cumulationsRef) = @_;

	# Here we will open the file into which we write our HTML results:
	my $generatedFileHandle;
	open( $generatedFileHandle, "> $generatedFileName" ) || 
		die( "${appProgName}::  Can't open/create $generatedFileName: $!" );
	# we're also going to generate the pre-trout swimmers into a different file and use ajax to show them if requested.
	my $generatedPreTroutFileHandle;
	open( $generatedPreTroutFileHandle, "> $preTroutGeneratedFileName" ) || 
		die( "${appProgName}::  Can't open/create $preTroutGeneratedFileName: $!" );


	# locate all our template files:
	my $templateRootRoot = "$appDirName/Templates/";        # directory location of master template files.
	# compute the names of the directories that we'll search for our template files
	my @templateDirs;
	@templateDirs = PopulateTemplateDirsArray( PMSStruct::GetMacrosRef()->{"templateSearchPath"} );

	# Get full path names to all of our template files so we're ready to open and process them:
	my $templateOpenWaterHead_PathName = GetPathName( $templateRootRoot, \@templateDirs, "OpenWaterHead.html" );
	my $templateOpenWaterTail_PathName = GetPathName( $templateRootRoot, \@templateDirs, "OpenWaterTail.html" );
	my $templateCategoryDefinitionStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "CategoryDefinitionStart.html" );
	my $templateCategoryDefinitionEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "CategoryDefinitionEnd.html" );
	my $templateCategoryDefinition_PathName = GetPathName( $templateRootRoot, \@templateDirs, "CategoryDefinition.html" );

	my $templateRecognitionSectionStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSectionStart.html" );
	my $templateRecognitionSectionEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSectionEnd.html" );
	my $templateRecognitionStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionStart.html" );
	my $templatePreTroutPlaceholder_PathName = GetPathName( $templateRootRoot, \@templateDirs, "PreTroutPlaceholder.html" );
	my $templateRecognitionEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionEnd.html" );
	my $templateRecognitionSwimmersListStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmersListStart.html" );
	my $templateRecognitionSwimmersListEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmersListEnd.html" );
	my $templateRecognitionSwimmerStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmerStart.html" );
	my $templateRecognitionSwimmerDetail_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmerDetail.html" );
	my $templateRecognitionSwimmerEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmerEnd.html" );

	####################
	# Begin processing our templates, generating our accumulated result file in the process
	####################
	if( $PMSConstants::debug >= 0 ) {
		print "GenerateHTMLResults(): starting...";
	}
	# start the HTML file:
	PMSTemplate::ProcessHTMLTemplate( $templateOpenWaterHead_PathName, $generatedFileHandle );
	
	# display a definition of all the categories (shark, whale, etc...)
	PMSTemplate::ProcessHTMLTemplate( $templateCategoryDefinitionStart_PathName, $generatedFileHandle );
	my $categoriesRef = PMSMacros::GetCategoryArrayRef();
	my $numCategories = scalar( @{$categoriesRef} ) - 2;		# start at 1, not 0! And ignore the fake highest one
	for( my $i = $numCategories; $i >= 0; $i-- ) {
		my $minSwimsForThisCategory = $categoriesRef->[$i]{"minCount"};
		my $maxSwimsForThisCategory = $categoriesRef->[$i]{"maxCount"};
		my $patch = $categoriesRef->[$i]{"patch"};
		my $maxString;
		# we're starting with the highest valued category and going down to least valued. is
		# this one the highest valued one?
		if( $i == $numCategories ) {
			$maxString = "+ swims";
		} else {
			$maxString = " - $maxSwimsForThisCategory swims";
		}
		PMSStruct::GetMacrosRef()->{"CategoryName"} = $categoriesRef->[$i]{"name"};
		PMSStruct::GetMacrosRef()->{"RangeOfSwimsInCategory"} = $minSwimsForThisCategory . $maxString;
		PMSStruct::GetMacrosRef()->{"ThePatch"} = $patch;
		if( $i == 1 ) {
			# this is the Trout row - put a hot spot at the end of the line
			PMSStruct::GetMacrosRef()->{"HotSpot"} = 
				'<a style="color:white" onclick="TogglePreTrout(event);return false" href="#">x</a>';
		} else {
			PMSStruct::GetMacrosRef()->{"HotSpot"} = '';
		}
		
		# handle pre-trout
		if( $i == 0 ) {
			# this is the pre-Trout row - hide the row for now
			PMSStruct::GetMacrosRef()->{"trStyle"} = 'CategoryRowPreTrout" style="display:none"';
		} else {
			# normal row - show it
			PMSStruct::GetMacrosRef()->{"trStyle"} = '"';
		}
		PMSTemplate::ProcessHTMLTemplate( $templateCategoryDefinition_PathName, $generatedFileHandle );
	} # end of for( my $i =....
	PMSTemplate::ProcessHTMLTemplate( $templateCategoryDefinitionEnd_PathName, $generatedFileHandle );
	
	# display the recognition section...
	PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSectionStart_PathName, $generatedFileHandle );
	for( my $i = $numCategories; $i >= 0; $i-- ) {
		# Generate the title line for this recognition:
		my $numSwimmers = $categoriesRef->[$i]{$endYear . "-swimmers"};
		my $numSwimmersString = "No swimmers (yet)";
		if( $numSwimmers > 0 ) {
			my $swimmers = "swimmers";
			if( $numSwimmers == 1 ) {
				$swimmers = "swimmer";
			}
			$numSwimmersString = "Total of $numSwimmers $swimmers:";
		}

		# We actually generate TWO recognition sections: one for all categories that we show by default, and
		# another for the pre-trout swimmers. For this reason we will write the two recognition sections to two
		# different files. More on this below.
		my $outputFileHandle = $generatedFileHandle;	# default recognition section
		
		### if $i == 0 this means we're starting the "made up" category "pre-trout". We don't normally show
		# that category but we're going to make it possible for the user to request seeing it. In this case we
		# "finish" generating the recognition section and begin generating a DIFFERENT recognition section just
		# for the pre-trouts. We'll generate that section to a different file, using Ajax to display that 
		# file if requested by the user.
		if( $i == 0 ) {
			# this is the pre-Trout row - finish the already generated recognition section:
			# all done displaying the recognition of ALL swimmers of ALL categories	EXCEPT pre-trout
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSectionEnd_PathName, $outputFileHandle );
			# Now, begin a different recognition section just for the pre-trouts
			$outputFileHandle = $generatedPreTroutFileHandle;
			# this is where the pre-trout swimmers will go. We'll create a place-holder for them later and then 
			# fill it in via ajax when requested by the user.
			
			# begin the pre-trout recognition section
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSectionStart_PathName, $outputFileHandle );
			PMSStruct::GetMacrosRef()->{"trStyle"} = 'CategoryRowPreTrout"';
			# this is a special case: show the number of swimmers with N swims, for N = max swims for this
			# category (e.g. 4 if Trout min is 5) down to 1 swims.  Useful for ordering patches.
			my @preTroutSwims = CountPreTroutSwims( $cumulationsRef );
			my $min = $categoriesRef->[0]{"minCount"};
			my $max = $categoriesRef->[0]{"maxCount"};
			$numSwimmersString .= " (";
			for( my $i = $max; $i >= $min; $i-- ) {
				my $swims = "swims";
				$swims = "swim" if( $i == 1);
				$numSwimmersString .= "$i $swims: $preTroutSwims[$i]";
				if( $i == $min ) {
					$numSwimmersString .= ")";
				} else {
					$numSwimmersString .= ", ";
				}
			}
		} else {
			# normal row - show it
			PMSStruct::GetMacrosRef()->{"trStyle"} = '"';
		}
		PMSStruct::GetMacrosRef()->{"CategoryName"} = $categoriesRef->[$i]{"name"};
		PMSStruct::GetMacrosRef()->{"NumSwimmersInCategory"} = $numSwimmersString;
		PMSTemplate::ProcessHTMLTemplate( $templateRecognitionStart_PathName, $outputFileHandle );
		if( $numSwimmers > 0 ) {
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmersListStart_PathName, $outputFileHandle );
			# we've got some swimmers in this category - display details on each swimmer
			BeginEnumerationOfCategory( $categoriesRef, $i );
			my $USMSId;
			my $count = 0;
			while( ($USMSId = GetNextMemberOfCategory()) ne "" ) {
				$count++;
				# got another swimmer to recognize...
				PMSStruct::GetMacrosRef()->{"SwimmerName"} = $cumulationsRef->{ $USMSId . "-name"};
				PMSStruct::GetMacrosRef()->{"SwimmerCount"} = $cumulationsRef->{ $USMSId . "-0"};
#				PMSStruct::GetMacrosRef()->{"SwimmerId"} = $USMSId;		# debugging
				PMSStruct::GetMacrosRef()->{"SwimmerId"} = "";			# not Debugging
				# color rows differently when odd or even:
				if( $count % 2 ) {
					PMSStruct::GetMacrosRef()->{"SingleSwimmerRowClass"} = "SingleSwimmerRowOdd";
				} else {
					PMSStruct::GetMacrosRef()->{"SingleSwimmerRowClass"} = "SingleSwimmerRowEven";
				}
				PMSStruct::GetMacrosRef()->{"TotalDistance"} = $cumulationsRef->{ $USMSId . "-distance-0"};
				PMSStruct::GetMacrosRef()->{"ChallengerID"} = PMSStruct::GetMacrosRef()->{"CategoryName"} . 
					"_$count"; 
			
				my $lastYear = GetSwimmersLastYear( $USMSId );
				PMSStruct::GetMacrosRef()->{"LatestTeam"} = $cumulationsRef->{ $USMSId . "-team-$lastYear"};
				# handle pre-trout
				if( $i == 0 ) {
					# this is the pre-Trout row - 
					PMSStruct::GetMacrosRef()->{"trStyle"} = 'CategoryRowPreTrout" style="display:table-row"';
				} else {
					# normal row - show it
					PMSStruct::GetMacrosRef()->{"trStyle"} = '"';
				}
				PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmerStart_PathName, $outputFileHandle );
				
				# supply OW details for this swimmer:
				foreach my $workingYear ( $startYear..$endYear ) {
					my $numOWSwims = $cumulationsRef->{ $USMSId . "-" . $workingYear };
					if( $numOWSwims > 0 ) {
						# the following will construct a link to this swimmer's OW Points page in one of the 
						# following two forms:
						#   https://data.pacificmasters.org/points/OWPoints/Historical/xxxx/GeneratedFiles/xxxxPacMastersAccumulatedResults.html
						# or
						#	https://data.pacificmasters.org/points/OWPoints/xxxxPacMastersAccumulatedResults.html
						# where 'xxxx' is the workingYear.
						# or
						#	some other URL that isn't right but doesn't generate a 404. This is the worst case.
						my $URL = LinkToOWPointsForThisYear( $workingYear );
						
						# we'll break down their swims based on category of suit:
						my ($numSwimCat1, $numSwimCat2) = (
							$cumulationsRef->{ "$USMSId-$workingYear-1" },
							$cumulationsRef->{ "$USMSId-$workingYear-2" } );
						if( $numSwimCat1 > 0 ) {
							my $url1 = $URL . "?open=" . PMSUtil::GenerateUniqueID2( $cumulationsRef->{ "$USMSId-gender" },
								$cumulationsRef->{ "$USMSId-YOB" }, "1", $USMSId );
							PMSStruct::GetMacrosRef()->{"SwimCat1"}	= "<a href='$url1' target='_blank'>" .
								"Cat 1 swims: $numSwimCat1</a> &nbsp;&nbsp;";
						} else {
							PMSStruct::GetMacrosRef()->{"SwimCat1"}	= "";
						}
						if( $numSwimCat2 > 0 ) {
							my $url2 = $URL . "?open=" . PMSUtil::GenerateUniqueID2( $cumulationsRef->{ "$USMSId-gender" },
								$cumulationsRef->{ "$USMSId-YOB" }, "2", $USMSId );
							PMSStruct::GetMacrosRef()->{"SwimCat2"}	= "<a href='$url2' target='_blank'>" .
								"Cat 2 swims: $numSwimCat2</a>";
						} else {
							PMSStruct::GetMacrosRef()->{"SwimCat2"}	= "";
						}
					
						PMSStruct::GetMacrosRef()->{"year"}	= $workingYear;
						PMSStruct::GetMacrosRef()->{"OWSwims"}	= $numOWSwims;
						PMSStruct::GetMacrosRef()->{"OWMiles"}	= $cumulationsRef->{ $USMSId . "-distance-$workingYear"};
						PMSStruct::GetMacrosRef()->{"ThisYearsTeam"} = $cumulationsRef->{ $USMSId . "-team-$workingYear"};						
						PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmerDetail_PathName, $outputFileHandle );
					}
				}
				# done with details for this swimmer
				PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmerEnd_PathName, $outputFileHandle );
			}
			# done displaying details for each swimmer in this category
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmersListEnd_PathName, $outputFileHandle );
		}
		# all done displaying swimmers in this category - finish up this category so we can start the next one
		PMSTemplate::ProcessHTMLTemplate( $templateRecognitionEnd_PathName, $outputFileHandle );

		if( $i == 0 ) {
			# all done displaying the recognition of ALL swimmers of the pre-trout categorye	
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSectionEnd_PathName, $outputFileHandle );
		}
	} # end of for( my $i =...

	# we're done with both recognition files. Now, put a placeholder into the file holding all non-pre-trout 
	# recognition swimmers so ajax can add the pre-trout swimmers if requested by the user.
	PMSTemplate::ProcessHTMLTemplate( $templatePreTroutPlaceholder_PathName, $generatedFileHandle );

	# all done with the page
	PMSTemplate::ProcessHTMLTemplate( $templateOpenWaterTail_PathName, $generatedFileHandle );

	if( $PMSConstants::debug >= 0 ) {
		print "GenerateHTMLResults(): All done.\n";
	}

	close( $generatedFileHandle );
	close( $generatedPreTroutFileHandle );
} # end of GenerateHTMLResults()



# 			my @preTroutSwims = CountPreTroutSwims($cumulationsRef);
sub CountPreTroutSwims($) {
	my $cumulationsRef = $_[0];
	my @preTroutSwims = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);		# probably too big but just in case...
	my $categoriesRef = PMSMacros::GetCategoryArrayRef();

	my $min = $categoriesRef->[0]{"minCount"};
	my $max = $categoriesRef->[0]{"maxCount"};
	foreach my $key( keys %$cumulationsRef ) {
		if( index( $key, '-' ) == -1 ) {
			# $key is the usms swimmer id of a swimmer - are they a pre-trout?
			my $numSwimsForThisSwimmer = $cumulationsRef->{"$key-0"};
			if( ($numSwimsForThisSwimmer >= $min) && ($numSwimsForThisSwimmer <= $max) ) {
				$preTroutSwims[$numSwimsForThisSwimmer]++;
			}
		}
	}
	return @preTroutSwims;
} # end of CountPreTroutSwims()








# PopulateTemplateDirsArray - populate the global @templateDirs[] with the directory names found in 
#	the passed string of directory names.
#
# PASSED:
#	$paths - a string of the form dir1,dir2,dir3,...,dirN
#
# RETURNED:
#	array...
#
# SIDE EFFECTS:
#	The global array @templateDirs is populated with:
#		$templateDirs[0] = dir1
#		$templateDirs[1] = dir2
#		$templateDirs[2] = dir3
#		...etc...
#		
sub PopulateTemplateDirsArray($) {
	my $paths = $_[0];
	
	if( ! defined( $paths ) ) {
		die( "${appProgName}::  !!! FATAL ERROR in PopulateTemplateDirsArray - no template search path specified.\n" );
	}

	my @templateDirs = split( /,/, $paths );
	return @templateDirs;
	
} # end of PopulateTemplateDirsArray


# GetPathName - search for the passed file (name) using the passed root directory and passed list of subdirectories.
#  Return the path to the file (including the file name) sutable for open().
#
# PASSED:
#	$rootDir - the full path name of a directory
#	$pathArray - an array of directory paths, e.g. created by PopulateTemplateDirsArray() above.
#	$fileName - the simple name of the file we're looking for.
#
# RETURNED:
#	$fullPath - either the full path name of the found file whose simple name is $fileName, or
#		a bogus path.  In the latter case an error is written to the log file and to the console.
#
sub GetPathName($$$) {
	my $rootDir = $_[0];
	my @pathArray = @{$_[1]};
	my $fileName = $_[2];
	
	foreach my $path (@pathArray) {
		my $fullPath = "$rootDir/$path/$fileName";
		if( -r $fullPath ) {
			return $fullPath;
		}
	}
	
	# couldn't find the file - assume this is an error (but not fatal)
	PMSLogging::DumpError( "", 0, "${appProgName}::GetPathName(): Unable to find a path to '$fileName' " .
		"(using root '$rootDir' - PROBABLY WILL CAUSE A FATAL ERROR LATER!", 1 );
	PMSLogging::DumpArray( \@pathArray, "Search path used in above error", 0 );
	return "(invalid path from GetPathName)";
	
} # end of GetPathName



###########################################################################################################################
###########################################################################################################################
###########################################################################################################################
# Enumerations
###########################################################################################################################
###########################################################################################################################
###########################################################################################################################

my @USMSIdArr = ();
my $USMSIdArrIndex = 0;
sub BeginEnumerationOfCategory( $$ ) {
	my ($categoriesRef, $catIndex ) = @_;
	my $minCount = $categoriesRef->[$catIndex]{"minCount"};
	my $maxCount = $categoriesRef->[$catIndex]{"maxCount"};
	my @tmpArr = ();
	@USMSIdArr = ();
	
	foreach my $USMSId (keys %cumulations) {
		if( index( $USMSId, "-" ) == -1 ) {
			# $USMSId is the key to a hash for a unique swimmer
			my $count = $cumulations{"$USMSId-0"};
			my $distance = $cumulations{"$USMSId-distance-0"};
			if( ($count >= $minCount) && ($count <= $maxCount) ) {
				# this swimmer is part of the passed category
				push( @tmpArr, $USMSId . ":::$count<<<$distance" );
				# NOTE: @tmpArr[x] will look like this:   "abcdef:::N<<<D" where
				#	abcdef is the USMSId, and
				#	N is the number of swims for that swimmer (1 or more digits), and
				#	D is the total distance of those swims (1 or more digits)
			}
		}
	}
	# sort the array by # of swims
	@USMSIdArr = sort { 
		GetCountFromString( $b ) <=> GetCountFromString( $a ) ||
		GetDistanceFromString( $b ) <=> GetDistanceFromString( $a )
	} @tmpArr;	
	$USMSIdArrIndex = 0;
} # end of BeginEnumerationOfCategory()


# PASSED:
#	$str - a string of the form "abcdef:::N<<<D" where
#					abcdef is the USMSId, and
#					N is the number of swims for that swimmer (1 or more digits)
#					D is the distance of all those swims (1 or more digits)
#
sub GetCountFromString( $ ) {
	my $str = $_[0];
	$str =~ s/^.*::://;
	$str =~ s/<<<.*$//;
	return $str;
} # end of GetCountFromString()



# PASSED:
#	$str - a string of the form "abcdef:::N<<<D" where
#					abcdef is the USMSId, and
#					N is the number of swims for that swimmer (1 or more digits)
#					D is the distance of all those swims (1 or more digits)
#
sub GetDistanceFromString( $ ) {
	my $str = $_[0];
	$str =~ s/^.*<<<//;
	return $str;
} # end of GetDistanceFromString()


# return "" if no more to return, otherwise return swimmer USMS ID
sub GetNextMemberOfCategory() {
	my $maxIndex = scalar( @USMSIdArr ) - 1;		# 0 .. n-1
	my $result = "";
	
	if( $USMSIdArrIndex <= $maxIndex ) {
		$result = $USMSIdArr[$USMSIdArrIndex];
		# NOTE: $result will look like this:   "abcdef:::N" where
		#	abcdef is the USMSId, and
		#	N is the number of swims for that swimmer (1 or more digits)
		# So, get the USMSId only:
		$result =~ s/:::.*$//;
		$USMSIdArrIndex++;
	}
	
	return $result;
} # end of GetNextMemberOfCategory()


# 				my $lastYear = GetSwimmersLastYear( $USMSId );
sub GetSwimmersLastYear( $ ) {
	my $USMSId = $_[0];
	my $result = 0;
	
	for( my $workingYear = $endYear; $workingYear >= $startYear; $workingYear-- ) {
		if( $cumulations{"$USMSId-team-$workingYear"} ne "?" ) {
			$result = $workingYear;
			last;
		}
	}
	return $result;
} # end of GetSwimmersLastYear()



# This is a cache of OW Points links for various years
my @linksForWorkingYear = ();

# 						my $URL = LinkToOWPointsForThisYear( $workingYear );
sub LinkToOWPointsForThisYear( $ ) {
	my $workingYear = $_[0];
	my $result = "";
	my ($url, $url2);
	my $httpResponse;
	my $tinyHttp = HTTP::Tiny->new( );

	if( defined( $linksForWorkingYear[$workingYear] ) ) {
		# we already know the location of the OW points for this year.
		$result = $linksForWorkingYear[$workingYear];
	} else {
		# we don't know where the OW points are for this year, so we'll figure it out.
		$url = "https://data.pacificmasters.org/points/OWPoints/Historical/$workingYear/" .
			"GeneratedFiles/$workingYear" . "PacMastersAccumulatedResults.html";
		$httpResponse = $tinyHttp->get( $url );
		if( $httpResponse->{success} ) {
		  $result = $url;
		} else {
			$url2 = "https://data.pacificmasters.org/points/OWPoints/$workingYear" .
				"PacMastersAccumulatedResults.html";
			$httpResponse = $tinyHttp->get( $url2 );
			if( $httpResponse->{success} ) {
			  $result = $url2;
			} else {
				# ohoh....
				PMSLogging::DumpError( "", 0, "${appProgName}::LinkToOWPointsForThisYear(): Unable to find " .
					"the OW Points page for the year '$workingYear'.  Tried:\n" .
					"    $url\n    and\n    $url2", 1 );
				$result = "https://www.pacificmasters.org/";
			}
		}	
		# at this point we have the URL of the OW points page for this year. Save it so we don't have to figure it 
		# out again.
		$linksForWorkingYear[$workingYear] = $result;
		#print "Set link for '$workingYear' to '$result'\n";
	}
	return $result;
} # end of LinkToOWPointsForThisYear()




# end of OWChallenge.pl
