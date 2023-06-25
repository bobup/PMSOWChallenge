#!/bin/bash

# PushOWC.bash - push Open Water Challenge files from dev to production
#	Push generated files from the dev OWChallenge page to production.
#
# This script assumes that this host can talk to production using its public key.  If that isn't
# true then the user of this script will have to supply the password to production 3 times!!!
#
# PASSED:
#   n/a

# debugging...
#set -x

CURRENT_YEAR=`date +%Y`
STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
SIMPLE_SCRIPT_NAME=`basename $0`
EMAIL_NOTICE=bobup@acm.org
TARBALL=OWC_`date +'%d%b%Y'`.zip
OWDIR=OWChallenge
OWDIRARCHIVE=${OWDIR}_`date +'%d%b%Y'`.zip
TARDIR=~/Automation/OWCPushes
# make sure out TARDIR exists:
mkdir -p $TARDIR
PRODDIRECTORY=/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/
PRODURL=https://data.pacificmasters.org/points/$OWDIR/${CURRENT_YEAR}PacMastersOWChallengeResults.html
USERHOST=$USER@`hostname`

# Get to work!

echo ""; echo '******************** Begin' "$0"



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

cd /usr/home/pacdev/public_html/pacmdev.org/sites/default/files/comp/points > /dev/null
tar czf $TARBALL $OWDIR
mv $TARBALL $TARDIR
cd $TARDIR >/dev/null
# push tarball to production
scp -p $TARBALL pacmasters@pacmasters.pairserver.com:$PRODDIRECTORY
# archive old Challenge files and untar the new one in its place
# Also clean out old tar files.
ssh pacmasters@pacmasters.pairserver.com \
	"( cd $PRODDIRECTORY; tar zcf Attic/$OWDIRARCHIVE $OWDIR; rm -f $OWDIR/*.html $OWDIR/*.txt ; tar xf $TARBALL; mv $TARBALL Attic; cd Attic; ls -tp | grep -v '/$' | grep $OWDIR | tail -n +21 | xargs -I {} rm -- {}; ls -tp | grep -v '/$' | grep OW_ | tail -n +21 | xargs -I {} rm -- {} )"

# clean up old tarballs keeping only the most recent 60
cd $TARDIR >/dev/null
ls -tp | grep -v '/$' | tail -n +61 | xargs -I {} rm -- {}

LogMessage "OW Challenge pushed to PRODUCTION by $SIMPLE_SCRIPT_NAME on $USERHOST" \
	"$(cat <<- BUp9
	Destination File: $PRODDIRECTORY$OWDIR/${CURRENT_YEAR}PacMastersOWChallengeResults.html
	Destination URL: $PRODURL
	(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
	BUp9
	)"

echo 'Done!'

