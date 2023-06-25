#!/usr/bin/perl -w
# CU_MySqlSupport.pm - support routines and values used by the CU MySQL based code.

# Copyright (c) 2023 Bob Upshaw.  This software is covered under the Open Source MIT License 

package CU_MySqlSupport;

use strict;
use sigtrap;
use warnings;
use DBI;

#use lib '../../../PMSPerlModules';
use FindBin;
use File::Spec;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..', 'PMSPerlModules' );
require PMS_MySqlSupport;
#use PMSConstants;
#use PMSLogging;


#***************************************************************************************************
#********************** Open Water Challenge Points MySql Support Routines ***********************
#***************************************************************************************************
		
		
		



# InitializeCumulativeDB - get handle to our db; create tables if they are not there.
sub InitializeAccPtsDB() {
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $sth;
	my $rv;
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};
	if( $dbh ) {
	
	}
	return $dbh;
} # end of InitializeCumulativeDB()



1;  # end of module
