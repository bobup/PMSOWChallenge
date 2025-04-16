#!/bin/bash

# BuildAndInstallIfNecessary.bash - if necessary we will build and install (into dev and 
# 	production) a new version of OWChallenge. It's only necessary if the OW points page is
# 	newer than the OWChallenge page.


CURRENT_YEAR=`date +%Y`
ORIGINAL_CURRENT_YEAR=$CURRENT_YEAR
STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
SIMPLE_SCRIPT_NAME=`basename $0`
EMAIL_NOTICE=bobup@acm.org
PRODDIRECTORY=/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points
# full path of the OW Points page on the production server:
OWPOINTSFILE=$PRODDIRECTORY/OWPoints/${CURRENT_YEAR}PacMastersAccumulatedResults.html
# full path of the OWChallenge page on the production server:
OWCFILE=$PRODDIRECTORY/OWChallenge/OWChallenge.html

# make our working directory the directory holding this script:
script_dir=$(dirname $0)
pushd $script_dir >/dev/null

#
# LogMessage - generate a log message to various devices:  email, stdout, and a script
#   log file.
#
# PASSED:
#   $1 - the subject of the log message.
#   $2 - the log message
#
LogMessage() {
    echo "$2"
	/usr/sbin/sendmail -f $EMAIL_NOTICE $EMAIL_NOTICE <<- BUpLM
		Subject: $1
		$2
		BUpLM
} # end of LogMessage()



# compare the date of the last push of OW points with the date of the OWChallenge page. First, get the two dates:
OWPUSHDATE=`ssh pacmasters@pacmasters.pairserver.com \
	"( date -r  $OWPOINTSFILE )"`
OWCPushDate=`ssh pacmasters@pacmasters.pairserver.com \
	"( date -r $OWCFILE )"`
echo "CURRENT_YEAR='$CURRENT_YEAR', OWPUSHDATE='$OWPUSHDATE', OWCPushDate='$OWCPushDate'"

# if we can't find results for OW then we're going to use the previous year as the CURRENT_DATE. We do this
# to handle the case where we're running on Jan 1 of the year following the last year of OW competitions.
# It's possible that's not the case, and we're just getting some error trying to find the latest OW
# results, but in that case we'll just ignore the current year. That's not 


#pretend that the last OW results were created on 
# Jan 1 of the current year. This will handle the case of the first run of a new year. In that case, it will
# appear that the OW results have changed, thus a new OWChallenge page will be generated with the new year
# in the title but with no other changes. The next time this script runs it will think that the OWChallenge page
# is "newer" than the OW points page thus nothing will be generated. Eventually a new OW points page will be
# generated causing a new OWChallenge page to be generated, as it should.
if [ ".$OWPUSHDATE" == . ] ; then
	CURRENT_YEAR=$(expr $CURRENT_YEAR - 1)
	# full path of the OW Points page on the production server:
	OWPOINTSFILE=$PRODDIRECTORY/OWPoints/${CURRENT_YEAR}PacMastersAccumulatedResults.html
	OWPUSHDATE=`ssh pacmasters@pacmasters.pairserver.com \
		"( date -r  $OWPOINTSFILE )"`
	echo "Above changed. Now:  CURRENT_YEAR='$CURRENT_YEAR', OWPUSHDATE='$OWPUSHDATE', OWCPushDate='$OWCPushDate'"
fi
if [ ".$OWPUSHDATE" == . ] ; then
	LogMessage "$SIMPLE_SCRIPT_NAME failed." \
		"$(cat <<- BUp8
		$SIMPLE_SCRIPT_NAME failed: unable to find latest OW results for $ORIGINAL_CURRENT_YEAR and $CURRENT_YEAR.
		ORIGINAL_CURRENT_YEAR='$ORIGINAL_CURRENT_YEAR'
		CURRENT_YEAR='$CURRENT_YEAR'
		Date of last OW push for $CURRENT_YEAR: NONE FOUND!
		Date of last OWChallenge generation: $OWCPushDate
		Abort!!
		BUp8
		)"
	exit 1;
else
	LogMessage "$SIMPLE_SCRIPT_NAME recovered from failure." \
		"$(cat <<- BUp8
		$SIMPLE_SCRIPT_NAME recovered: unable to find latest OW results for $ORIGINAL_CURRENT_YEAR but
		  found them for $CURRENT_YEAR.  That's the results we're using.
		ORIGINAL_CURRENT_YEAR='$ORIGINAL_CURRENT_YEAR'  (we are NOT using that year)
		CURRENT_YEAR='$CURRENT_YEAR'  (we ARE using that year)
		Date of last OW push for $CURRENT_YEAR: $OWPUSHDATE
		Date of last OWChallenge generation: $OWCPushDate
		Another email should follow...
		BUp8
		)"
fi

# is the date of the last push of OW points more recent than the date of the last push of OWChallenge?
# convert the two dates into integers for easy comparison:
DATEOFLASTOWPUSH=`date -d "$OWPUSHDATE" +%s`
DATEOFLASTOWCPUSH=`date -d "$OWCPushDate" +%s`
echo "DATEOFLASTOWPUSH='$DATEOFLASTOWPUSH', DATEOFLASTOWCPUSH='$DATEOFLASTOWCPUSH'"


#if [ $DATEOFLASTOWPUSH -gt $DATEOFLASTOWCPUSH ] ; then

if [ 1 ] ; then


	# YES! regenerate the OWChallenge page
	echo Regeneration of OWChallenge in progress...
	./OWCGenerate -E"$CURRENT_YEAR"
###	./PMSScripts/DevPushOWC.bash
###	./PMSScripts/ProdPushOWC.bash
	echo Regeneration done.
else
	echo No Regeneration of OWChallenge necessary.
	LogMessage "OW Challenge NOT regenerated." \
		"$(cat <<- BUp9
		Date of last OW push for $CURRENT_YEAR: $OWPUSHDATE
		Date of last OWChallenge generation: $OWCPushDate
		BUp9
		)"
fi

