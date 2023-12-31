#!/bin/bash


# DevPushOWC.bash - this script is intended to be executed on the PMS Dev machine ONLY.  
#   It will push the Open Water Challenge results to the Dev OW points page, e.g.:
#			http://www.pacmdev.org/points/OWChallenge/
#	ONLY IF the "????PacMastersOWChallengeResults.html" file exists in the 
#   "Generated files" directory. ('????' is the current year.)
#
# PASSED:
#	Either nothing or some string. If some string then the current OWChallenge html file is NOT pushed
#		with it's name, but instead a name that ends with "....-test.html" (same with the log file).
#		If this argument is empty then test files (if any) are removed.
#
#	This script is assumed to be located in the OW Challenge PMSScripts directory.
#

STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
EMAIL_NOTICE=bobup@acm.org
SIMPLE_SCRIPT_NAME=`basename $0`
DESTINATION_DIR=/usr/home/pacdev/public_html/pacmdev.org/sites/default/files/comp/points/OWChallenge
CURRENT_YEAR=`date +%Y`


#
# LogMessage - generate a log message to various devices:  email, stdout, and a script 
#	log file.
#
# PASSED:
#	$1 - the subject of the log message.
#	$2 - the log message
#
LogMessage() {
	echo "$2"
	/usr/sbin/sendmail -f $EMAIL_NOTICE $EMAIL_NOTICE <<- BUpLM
		Subject: $1
		$2
		BUpLM
} # end of LogMessage()

##########################################################################################


# Get to work!
mytest=$1;

echo ""; echo '******************** Begin' "$0" $mytest

# compute the full path name of the directory holding this script.  We'll find the
# Generated files directory relative to this directory:
script_dir=$(dirname $0)
# Next compute the full path name of the directory into which the generated files are placed, 
# making sure it exists:
mkdir -p $script_dir/../../../GeneratedFiles
pushd $script_dir/../../../GeneratedFiles >/dev/null; 
GENERATED_DIR=`pwd -P`
# do we have the generated files that we want to push?
if [ -e "${CURRENT_YEAR}PacMastersOWChallengeResults.html" ] ; then
	# yes!  get to work:
	mkdir -p $DESTINATION_DIR
	if [ .$mytest != . ] ; then
		# special case push...
		cp -f "${CURRENT_YEAR}PacMastersOWChallengeResults.html" \
			"$DESTINATION_DIR/${CURRENT_YEAR}PacMastersOWChallengeResults-test.html"
		cp -f "${CURRENT_YEAR}PacMastersOWChallengeResultsLog.txt" \
			"$DESTINATION_DIR/${CURRENT_YEAR}PacMastersOWChallengeResultsLog-test.txt"
		LogMessage "OW Challenge TEST pushed to dev by $SIMPLE_SCRIPT_NAME on $USERHOST" "$(cat <<- BUp9 
			Destination File: $DESTINATION_DIR/${CURRENT_YEAR}PacMastersOWChallengeResults-test.html
			(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
			BUp9
			)"
	else
		rm -rf $DESTINATION_DIR/*
		cp -r *  $DESTINATION_DIR
		pushd $DESTINATION_DIR >/dev/null
		rm -f OWChallenge.html
		ln -s "${CURRENT_YEAR}PacMastersOWChallengeResults.html" OWChallenge.html
		LogMessage "OW Challenge pushed to dev by $SIMPLE_SCRIPT_NAME on $USERHOST" "$(cat <<- BUp9 
			Destination File: $DESTINATION_DIR/${CURRENT_YEAR}PacMastersOWChallengeResults.html
			(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
			BUp9
			)"
	fi
fi

popd >/dev/null
echo ""; echo '******************** End of ' "$0"

exit;
