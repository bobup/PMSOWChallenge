#!/bin/bash

# BuildAndInstallIfNecessary.bash - if necessary we will build and install (into dev and 
# 	production) a new version of OWChallenge. It's only necessary if the OW points page is
# 	newer than the OWChallenge page.


CURRENT_YEAR=`date +%Y`
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
echo "OWPUSHDATE='$OWPUSHDATE', OWCPushDate='$OWCPushDate'"

# is the date of the last push of OW points more recent than the date of the last push of OWChallenge?
# convert the two dates into integers for easy comparison:
DATEOFLASTOWPUSH=`date -d "$OWPUSHDATE" +%s`
DATEOFLASTOWCPUSH=`date -d "$OWCPushDate" +%s`
echo "DATEOFLASTOWPUSH='$DATEOFLASTOWPUSH', DATEOFLASTOWCPUSH='$DATEOFLASTOWCPUSH'"
if [ $DATEOFLASTOWPUSH -gt $DATEOFLASTOWCPUSH ] ; then
	# YES! regenerate the OWChallenge page
	echo Regeneration of OWChallenge in progress...
	./OWCGenerate
	./PMSScripts/DevPushOWC.bash
	./PMSScripts/ProdPushOWC.bash
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

