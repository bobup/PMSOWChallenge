#!/usr/bin/perl -w

# OWChallenge.pl -

# Copyright (c) 2023 Bob Upshaw.  This software is covered under the Open Source MIT License 

####################
# PERL modules and initialization to help compiling
####################
use File::Basename;
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
my %cumulations;	# $cumulations{ID} - set to ID
					# $cumulations{ID-YEAR} - count of OW swims for swimmer with USMS swimmer id of ID during the
					#	year YEAR.
					# $cumulations{ID-0} - count of OW swimms for swimmer with USMS swimmer id of ID over 
					#	all the years processed so far.
					# $cumulations{ID-distance-YEAR} - sum of total miles swum for swimmer with 
					#	USMS swimmer id of ID during the year YEAR.
					# $cumulations{ID-distance-0} - sum of total miles swum for swimmer with 
					#	USMS swimmer id of ID over all the years processed so far.
					# $cumulations{ID-name} - first M last of swimmer with USMS swimmer id of ID
my %totalNumSwimmers;	# this hash contains the total number of swimmers seen in specific years, where:
		# $totalNumSwimmers{"xxxx"} contains the total number of swimmers in the year xxxx, and
		# $totalNumSwimmers{"all"} contains the total number of unique swimmers seen in all years processed.
my $INVALID_SWIMMERS_NAME;



# forward declarations:
sub GetSwimmersName( $$ );
sub InitializeSwimmer( $$$$$ );
sub InitializeWorkingYear( $$$ );
sub InitializeTotalNumberSwimmers( $$$ );
sub UpdateCategoryCount( $$$$ );
sub InitializeCategories( $$$ );
sub GetPathName($$$);
sub PopulateTemplateDirsArray($);
sub GenerateHTMLResults($$);




BEGIN {
	# get the date/time we're starting:
	$dateTimeFormat = '%a %b %d %Y %Z %I:%M:%S %p';
	$currentDateTime = strftime $dateTimeFormat, localtime();
	$dateFormat = '%Y-%m-%d';		# year-mm-dd
	$currentDate = strftime $dateFormat, localtime();
	$yearFormat = '%Y';
	$yearBeingProcessed = strftime $yearFormat, localtime();
	
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

####################
# Usage string
####################

my $UsageString = <<bup
Usage:  
	$appProgName [Syear[-Eyear]]
	[-dDebugValue]
	[-tPROPERTYFILE]
	[-sSOURCEDATADIR]
	[-gGENERATEDFILESDIR]
	[-h]
where all arguments are optional:
	year-year - if present can be in one of these forms:
			Syear
			Syear-Eyear
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
range of years from the "StartYear" (defined in the properties.txt file) and the passed year.
Use the SwimmerEventHistory table to collect all swims for each swimmer during those years, and then
use the RSIND table for those years to map USMSSwimmerIds to swimmer names. 

????

Update the table 'Cumulative'
to contain the sums calculated for this year per swimmer, and for all years covered by Cumulative per swimmer.
bup
;

####################
# pragmas
####################
use DBI;
use strict;
use sigtrap;
use warnings;


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
			if( 
				($Syear > $Eyear) ||
				($Syear < 2008) ||
				($Eyear > $yearBeingProcessed)
				) {
				print "${appProgName}:: FATAL ERROR:  Invalid value for start year ($Syear) or " .
					"end year ($Eyear): '$value'\n";
				$numErrors++;
			} else {
				$startYear = $Syear;
				$endYear = $Eyear;
			}
			
print "startYear='$startYear', endYear='$endYear'\n";
		}
	}
} # end of while - done getting command line args


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

# write some initial logging info to the log file
PMSLogging::PrintLog( "", "", "Processing of $appProgName Begun: " . PMSStruct::GetMacrosRef()->{"currentDateTime"} . " ", 1 );
PMSLogging::PrintLog( "", "", "The range of years being processed: '$startYear' - '$endYear'", 1 );
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

my $categoriesRef = PMSMacros::GetCategoryArrayRef();
my $numCategories = InitializeCategories( $categoriesRef, $startYear, $endYear );

if( $PMSConstants::debug > 0 ) {
	my $categoriesRef = PMSMacros::GetCategoryArrayRef();
	print "Debugging: Categories:\n";
	foreach my $i (1..$numCategories) {
		print "Name: " . $categoriesRef->[$i]{"name"} . ", ";
		print "minCount: " . $categoriesRef->[$i]{"minCount"} . ", ";
		print "maxCount: " . $categoriesRef->[$i]{"maxCount"} . "\n";
	}
}

InitializeTotalNumberSwimmers( \%totalNumSwimmers, $startYear, $endYear );

# Analyze each year individually:
foreach my $workingYear ( $startYear..$endYear ) {
	# initialize our counts for the working year:
	InitializeWorkingYear( $categoriesRef, $numCategories, $workingYear );
	# get a list of all events swum during the working year:
	
	my ($selectStr, $selectDistanceStr);
	if( $workingYear == $yearBeingProcessed ) {
		# special case: if we're processing OW swims for the current year we can't look in the history
		# tables, but instead we'll look in the current OW Points tables
		print "workingYear = '$workingYear' which is the same as yearBeingProcessed\n";
		$selectStr = "SELECT SUBSTRING(RegNum, 6, 5) AS USMSSwimmerId, Swim.EventId as eventid FROM " .
			"RegNums Join Swim WHERE Swim.SwimmerId = RegNums.SwimmerId " .
	  		"ORDER BY USMSSwimmerId";
		$selectDistanceStr = "SELECT Distance from Events where EventId = xxxx";
	} else {
		# use our OW history
		print "workingYear = '$workingYear'\n";
		$selectStr = "SELECT USMSSwimmerId, UniqueEventId as eventid FROM SwimmerEventHistory WHERE Date
			LIKE '$workingYear%' ORDER BY USMSSwimmerId";
		$selectDistanceStr = "SELECT Distance from EventHistory where UniqueEventID = xxxx";
	}
	my( $sth, $rv ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $selectStr );
	my $resultHash;
	# each event swum represents a single swim by a single swimmer in a specific year ($workingYear). 
	# Increment the number of swims for the working year for each specific swimmer:
	while( defined( $resultHash = $sth->fetchrow_hashref ) ) {
#print "resultHash is: ";
#print Dumper($resultHash);
		my $usmsSwimmerId = $resultHash->{'USMSSwimmerId'};
		my $eventid = $resultHash->{'eventid'};
		# the following InitializeSwimmer() does nothing if we've seen this swimmer before:
		my $isValidSwimmer = InitializeSwimmer( \%cumulations, $usmsSwimmerId, $startYear, $endYear, $workingYear );
		if( $isValidSwimmer ) {
			$cumulations{ $usmsSwimmerId . "-$workingYear"}++;
			$cumulations{ $usmsSwimmerId . "-0"}++;		# total swims for this swimmer for all years up to and including this working Year
			# get the distance of this Swim
			$selectDistanceStr =~ s/xxxx/$eventid/;
			my( $sth2, $rv2 ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $selectDistanceStr );
			if( defined( $resultHash = $sth2->fetchrow_hashref ) ) {
				my $distance = $resultHash->{'Distance'};
				$cumulations{ $usmsSwimmerId . "distance-$workingYear"} += $distance;
				$cumulations{ $usmsSwimmerId . "distance-0"} += $distance;
			}
		
		}
	}
	
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
	
	if( $PMSConstants::debug > 0 ) {
		print "Number of swimmers for '$workingYear': $totalNumSwimmers{$workingYear}\n";
		foreach my $i (1..$numCategories) {
			print "  Number of swimmers in the " . $categoriesRef->[$i]{"name"} . " category: " .
				$categoriesRef->[$i]{$workingYear . "-swimmers"} . "\n";
		}
	}
			
} # end of each working year...

# Now pass through our %cumulations hash table and get some numbers:

foreach my $id (keys %cumulations) {
	if( index( $id, "-" ) == -1 ) {
		# $id is the key to a hash for a unique swimmer
		$totalNumSwimmers{"all"}++;
	}
}

if( $PMSConstants::debug > 0 ) {
	print "Total number of swimmers: $totalNumSwimmers{'all'}\n";
}

# Generate the HTML output:
GenerateHTMLResults( $endYear, \%cumulations );


print "Done with $appProgName\n\n";
exit 0;



###########################################################################################################################
###########################################################################################################################
###########################################################################################################################
# Subroutines
###########################################################################################################################
###########################################################################################################################
###########################################################################################################################

# 				$cumulations{ $lastIDSeen . "-name"} = GetSwimmersName( $lastIDSeen, $yearBeingProcessed );
sub GetSwimmersName( $$ ) {
	my ($USMSId, $yearBeingProcessed) = @_;
	my $name = $INVALID_SWIMMERS_NAME;
	
	my $query = "SELECT FirstName, MiddleInitial, LastName FROM RSIDN_" . $yearBeingProcessed . " WHERE USMSSwimmerId = '$USMSId'";
	
	my( $sth, $rv ) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	my $resultHash = $sth->fetchrow_hashref;
	if( defined $resultHash ) {
		my $middleInitial = $resultHash->{'MiddleInitial'};
		if( $middleInitial ne "" ) {
			$middleInitial = "$middleInitial ";
		}
		$name = $resultHash->{'FirstName'} . " $middleInitial" . $resultHash->{'LastName'};
	} else {
		if( $PMSConstants::debug > 10 ) {
			print "ERROR in GetSwimmersName(): USMSId '$USMSId' not found in RSIND. Query='$query'\n";
		}
	}
	
	return $name;
}



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
		my $swimmersName = GetSwimmersName( $usmsSwimmerId, $yearBeingProcessed );
		if( $swimmersName eq $INVALID_SWIMMERS_NAME ) {
			# we're going to ignore this swimmer because we can't find them in our RSIND file.
			$result = 0;
		} else {
			$cumulationsRef->{$usmsSwimmerId} = $usmsSwimmerId;
			foreach my $workingYear ( $startYear..$endYear ) {
				$cumulationsRef->{"$usmsSwimmerId-$workingYear"} = 0;
			}
			$cumulationsRef->{"$usmsSwimmerId-0"} = 0;
			$cumulationsRef->{ $usmsSwimmerId . "-name"} = $swimmersName;
		}
	}
	return $result;
} # end of InitializeSwimmer()



#		InitializeWorkingYear( $categoriesRef, $numCategories, $workingYear );
sub InitializeWorkingYear( $$$ ) {
	my ($categoriesRef, $numCategories, $workingYear) = @_;
	foreach my $i (1..$numCategories) {
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
	my $numCategories = scalar( @{$categoriesRef} ) - 1;		# start at 1, not 0!

	# here we're creating another (fake) category to help with further processing
	$categoriesRef->[$numCategories+1]{"name"} = "fake";
	$categoriesRef->[$numCategories+1]{"minCount"} = 99999999;
	$categoriesRef->[$numCategories+1]{"maxCount"} = 99999999;

	foreach my $i (1..$numCategories) {
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
		# this swimmer has enough OW swims to belong to one of the categories...
		foreach my $i (1..$numCategories) {
			if( ($swimmersCount >= $categoriesRef->[$i]{"minCount"}) &&
				($swimmersCount <= $categoriesRef->[$i]{"maxCount"}) ) {
					$categoriesRef->[$i]{$workingYear . "-swimmers"}++;
					last;
			}
		}
	} # else this swimmer doesn't have enough OW swims to affect any category
} # end of UpdateCategoryCount()



# GenerateHTMLResults - main driver for the generation of the HTML page showing the 
#	calculated Open Water Challenge data.  All data comes from populated structures above.
#
# PASSED:
#	$workingYear - 
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
sub GenerateHTMLResults( $$ ) {
	my ($workingYear, $cumulationsRef) = @_;

	# Here we will open the file into which we write our HTML results:
	my $generatedFileHandle;
	open( $generatedFileHandle, "> $generatedFileName" ) || die( "${appProgName}::  Can't open/create $generatedFileName: $!" );

	# locate all our template files:
	my $templateRootRoot = "$appDirName/Templates/";        # directory location of master template files.
	# compute the names of the directories that we'll search for our template files
	my @templateDirs;
	@templateDirs = PopulateTemplateDirsArray( PMSStruct::GetMacrosRef()->{"templateSearchPath"} );

	# Get full path names to all of our template files so we're ready to open and process them:
	my $templateOpenWaterHead_PathName = GetPathName( $templateRootRoot, \@templateDirs, "OpenWaterHead.html" );
	my $templateCategoryDefinitionStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "CategoryDefinitionStart.html" );
	my $templateCategoryDefinitionEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "CategoryDefinitionEnd.html" );
	my $templateCategoryDefinition_PathName = GetPathName( $templateRootRoot, \@templateDirs, "CategoryDefinition.html" );

	my $templateRecognitionSectionStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSectionStart.html" );
	my $templateRecognitionSectionEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSectionEnd.html" );
	my $templateRecognitionStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionStart.html" );
	my $templateRecognitionEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionEnd.html" );
	my $templateRecognitionSwimmersListStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmersListStart.html" );
	my $templateRecognitionSwimmersListEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmersListEnd.html" );
	my $templateRecognitionSwimmerStart_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmerStart.html" );
	my $templateRecognitionSwimmerEnd_PathName = GetPathName( $templateRootRoot, \@templateDirs, "RecognitionSwimmerEnd.html" );




	####################
	# Begin processing our templates, generating our accumulated result file in the process
	####################
	if( $PMSConstants::debug == 0 ) {
		print "GenerateHTMLResults(): starting...";
	}
	
	# start the HTML file:
	PMSTemplate::ProcessHTMLTemplate( $templateOpenWaterHead_PathName, $generatedFileHandle );
	
	# display a definition of all the categories (shark, whale, etc...)
	PMSTemplate::ProcessHTMLTemplate( $templateCategoryDefinitionStart_PathName, $generatedFileHandle );
	my $categoriesRef = PMSMacros::GetCategoryArrayRef();
	my $numCategories = scalar( @{$categoriesRef} ) - 2;		# start at 1, not 0! And ignore the fake highest one
	for( my $i = $numCategories; $i > 0; $i-- ) {
		my $minSwimsForThisCategory = $categoriesRef->[$i]{"minCount"};
		my $maxSwimsForThisCategory = $categoriesRef->[$i]{"maxCount"};
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
		PMSTemplate::ProcessHTMLTemplate( $templateCategoryDefinition_PathName, $generatedFileHandle );
	}
	PMSTemplate::ProcessHTMLTemplate( $templateCategoryDefinitionEnd_PathName, $generatedFileHandle );
	
	# display the recognition section...
	PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSectionStart_PathName, $generatedFileHandle );
	for( my $i = $numCategories; $i > 0; $i-- ) {
		my $numSwimmers = $categoriesRef->[$i]{$workingYear . "-swimmers"};
		my $numSwimmersString = "No swimmers (yet)";
		if( $numSwimmers > 0 ) {
			my $swimmers = "swimmers";
			if( $numSwimmers == 1 ) {
				$swimmers = "swimmer";
			}
			$numSwimmersString = "Total of $numSwimmers $swimmers:";
		}
		PMSStruct::GetMacrosRef()->{"CategoryName"} = $categoriesRef->[$i]{"name"};
		PMSStruct::GetMacrosRef()->{"NumSwimmersInCategory"} = $numSwimmersString;
		PMSTemplate::ProcessHTMLTemplate( $templateRecognitionStart_PathName, $generatedFileHandle );

		if( $numSwimmers > 0 ) {
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmersListStart_PathName, $generatedFileHandle );
			# we've got some swimmers in this category - display details on each swimmer
			BeginEnumerationOfCategory( $categoriesRef, $i );
			my $USMSId;
			my $count = 0;
			while( ($USMSId = GetNextMemberOfCategory()) ne "" ) {
				$count++;
				# got another swimmer to recognize...
				PMSStruct::GetMacrosRef()->{"SwimmerName"} = $cumulationsRef->{ $USMSId . "-name"};
				PMSStruct::GetMacrosRef()->{"SwimmerCount"} = $cumulationsRef->{ $USMSId . "-0"};
				# color rows differently when odd or even:
				if( $count % 2 ) {
					PMSStruct::GetMacrosRef()->{"SingleSwimmerRowClass"} = "SingleSwimmerRowOdd";
				} else {
					PMSStruct::GetMacrosRef()->{"SingleSwimmerRowClass"} = "SingleSwimmerRowEven";
				}
				PMSStruct::GetMacrosRef()->{"TotalDistance"} = $cumulationsRef->{ $USMSId . "distance-0"};
				
				PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmerStart_PathName, $generatedFileHandle );
				PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmerEnd_PathName, $generatedFileHandle );
			}
			# done displaying details for each swimmer in this category
			PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSwimmersListEnd_PathName, $generatedFileHandle );
		}
		# all done displaying swimmers in this category - finish up this category so we can start the next one
		PMSTemplate::ProcessHTMLTemplate( $templateRecognitionEnd_PathName, $generatedFileHandle );

	}
	# all done displaying the recognition of ALL swimmers of ALL categoryes	
	PMSTemplate::ProcessHTMLTemplate( $templateRecognitionSectionEnd_PathName, $generatedFileHandle );



	close( $generatedFileHandle );
} # end of GenerateHTMLResults()



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
		"(using root '$rootDir' - PROBABLY WILL CAUSE A FATAL ERROR LATER!". 1 );
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
			if( ($count >= $minCount) && ($count <= $maxCount) ) {
				# this swimmer is part of the passed category
				push( @tmpArr, $USMSId . ":::$count" );
				# NOTE: @tmpArr[x] will look like this:   "abcdef:::N" where
				#	abcdef is the USMSId, and
				#	N is the number of swims for that swimmer (1 or more digits)
			}
		}
	}
	# sort the array by # of swims
	@USMSIdArr = sort { GetCountFromString( $b ) <=> GetCountFromString( $a ) } @tmpArr;	
	$USMSIdArrIndex = 0;
} # end of BeginEnumerationOfCategory()


# PASSED:
#	$str - a string of the form "abcdef:::N" where
#					abcdef is the USMSId, and
#					N is the number of swims for that swimmer (1 or more digits)
#
sub GetCountFromString( $ ) {
	my $str = $_[0];
	$str =~ s/^.*::://;
	return $str;
} # end of GetCountFromString()



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

# end of OWChallenge.pl