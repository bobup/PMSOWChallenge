#!/bin/bash

#
# UploadHistorical {d | p} [year]
#
# Upload historical data to either PRODUCTION or DEVELOPMENT.
#
# UploadHistorical - The first argument must be either d or p (DEVELOPMENT or PRODUCTION) and
#   that designates the destination of the upload.  If there is a second argument
#   it will use that argument as a year (e.g. 2015)
#   and upload the historical generated results for that year.
#   If there is no second argument then this script will upload the generated results for ALL years
#
# In all cases it assumes a very specific directory structure and
# requires all historical OW results be stored in specific places in that directory
# structure.  For a summary of that structure see the Historical generation script (at this
# time called "Historical2" but that could change.)  One detail that will be useful is knowing that
# the directory 'Code' is the grandparent directory of this script, and is
# considered the 'appDirName' of the Accumulated Results application (GenerateOWResults.pl)
# and the history maintenance application (MaintainOWSwimmerHistory.pl).
#
#

SIMPLE_SCRIPT_NAME=`basename $0`

if [ ."$1" = . ] || ( [ ."$1" != .p ] && [ ."$1" != .d ] ) ; then
    echo "Usage: $SIMPLE_SCRIPT_NAME {d | p} [year]  - ABORT!"
    exit 1
fi

TMPTARFILESIMPLENAME=UploadHist-$$.tar
TMPTARFILE=/tmp/$TMPTARFILESIMPLENAME
echo "TMPTARFILE is '$TMPTARFILE'"

# compute the full path name of our PMSOWPoints/Historical local repository (relative to the location of this script)
# and make it our current directory:
script_dir=$(dirname $0)
pushd $script_dir/../../PMSOWPoints/Historical >/dev/null; HISTORICALDIR=`pwd -P`

# debugging...
echo HISTORICALDIR=$HISTORICALDIR

echo ""
echo ""
echo ""
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo ""

# assume we are uploading to the DEVELOPMENT server
DESTINATION_SERVER=DEVELOPMENT
DESTINATION_ADDRESS=pacdev@pacdev.pairserver.com
DESTINATION_HISTORY_DIRECTORY=/usr/home/pacdev/public_html/pacmdev.org/sites/default/files/comp/points/OWPoints/Historical
if [ .$1 == .p ] ; then
	DESTINATION_SERVER=PRODUCTION
    DESTINATION_ADDRESS=pacmasters@pacmasters.pairserver.com
    DESTINATION_HISTORY_DIRECTORY=/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/OWPoints/Historical
fi

# assume we're uploading historical data for all past years:
LOWERYEAR=2008
CURRENTYEAR=`date "+%Y"`
UPPERYEAR=$(($CURRENTYEAR-1))
if [ ."$2" != . ]  ; then
    # nope!  just one year
	echo "***>>> Uploading historical data for $LOWERYEAR to $DESTINATION_SERVER - started at `date \"+%H:%M:%S\"`"
    LOWERYEAR=$2
    UPPERYEAR=$2
else
	echo "***>>> Uploading Historical data for ALL years ($LOWERYEAR -> $UPPERYEAR) to $DESTINATION_SERVER - "\
        "started at `date \"+%H:%M:%S\"`"
fi


# OK, now get to work:
for (( WORKINGYEAR=$LOWERYEAR ; $WORKINGYEAR <= $UPPERYEAR ; WORKINGYEAR=$(($WORKINGYEAR+1)) )) ; do
	echo ""
	echo "***>>> Tar historical data for $WORKINGYEAR"
    pushd ~/Automation/PMSOWPoints/Historical/ >/dev/null
    tar czf $TMPTARFILE $WORKINGYEAR/GeneratedFiles
	echo "***>>> Prep and populate historical data area on $DESTINATION_SERVER for $WORKINGYEAR"
    if [ .$1 == .p ] ; then
        # uploading to the remote (production) machine
        scp -p $TMPTARFILE pacmasters@pacmasters.pairserver.com:$DESTINATION_HISTORY_DIRECTORY
        ssh $DESTINATION_ADDRESS \
            "( cd $DESTINATION_HISTORY_DIRECTORY; \
            mkdir -p $WORKINGYEAR; \
            rm -rf $WORKINGYEAR*.html $WORKINGYEAR*.txt $WORKINGYEAR*.csv; \
            tar xf $TMPTARFILESIMPLENAME;
            rm -f $TMPTARFILESIMPLENAME )"
    else
        # uploading to the local (dev) machine
        cd $DESTINATION_HISTORY_DIRECTORY; mkdir -p $WORKINGYEAR
        rm -rf $WORKINGYEAR*.html $WORKINGYEAR*.txt $WORKINGYEAR*.csv  
        tar xf $TMPTARFILE
    fi
	echo "***>>> Done with $WORKINGYEAR"
	echo ""
done

echo "***>>> Done uploading Historical data ($LOWERYEAR -> $UPPERYEAR) - finished at `date \"+%H:%M:%S\"`"

rm -f $TMPTARFILE
exit
