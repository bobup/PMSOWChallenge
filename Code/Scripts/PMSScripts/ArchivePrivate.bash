#!/bin/bash

# ArchivePrivate - construct an archive of all private data files that cannot otherwise
#	be stored in a public-visible source code system.
# This script is Open Water Points specific.
#
# It is assumed that this script is located in the Scripts/PMSScripts directory.
# To execute just run this script with no arguments. Your CWD can be anywhere, since
#	it will use the location of the script to find the root of the OW tree.
#

STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
SIMPLE_SCRIPT_NAME=`basename $0`
TARBALL_SIMPLE_NAME=PrivateOWData-`date +%d%b%Y`.tar
SCRIPT_DIR=$(dirname $0)
pushd $SCRIPT_DIR >/dev/null ; SCRIPT_DIR_FULL_NAME=`pwd -P` ; popd >/dev/null
ARCHIVE_DIR=$SCRIPT_DIR_FULL_NAME/../../../../Private/OWPrivateArchives
mkdir -p $ARCHIVE_DIR
pushd $ARCHIVE_DIR >/dev/null ; TARBALL_DIR=`pwd -P` ; popd >/dev/null
TARBALL_FULL_NAME=$TARBALL_DIR/$TARBALL_SIMPLE_NAME

pushd $SCRIPT_DIR_FULL_NAME/../../../  >/dev/null

tar cvf $TARBALL_FULL_NAME \
			Historical/HISTORICAL-properties_DB.txt \
			Historical/*/SourceData/PMSSwimmerData/*RSIND* \
			SourceData/*-properties_DB.txt \
			SourceData/PMSSwimmerData/*RSIND* \
			Historical/*/SourceData/PMSSwimmerData/MergedMembers*

echo "$SIMPLE_SCRIPT_NAME: Done constructing $TARBALL_FULL_NAME"

