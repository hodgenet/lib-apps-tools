#!/usr/bin/perl

use strict;
use warnings;
use open qw(:utf8);
use LWP::Simple;
use CGI::Simple;
use XML::Writer;							#	use Parser to read the XML file,
use XML::SimpleObject;							#	Simple Object to handle the actual records
use Date::Simple ('date','today');                                      #       Date::Simple is useful for making filenames
#use Unicode::Normalize;
use Encode;                                                             #       to mess with utf8/unicode things

#  To install this script, install the above Perl module on your workstation or server.  Script expects write access a directory ./tmp relative to it's location
#  Customize the Institution defaults under Main Execution at the bottom of the script.  The author runs this on a secure workstation and makes no warranty
#  as to the peformance or security of the code.  Script is provided as is.

######## makeTime       #######

sub makeTime {

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$fileTime);

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(${$_[0]});

$fileTime = ($year+1900).'-'.($mon+1).'-'.$mday."  $hour:$min";

return ($fileTime);

}

##############################                                  Make a current timestamp                                ##############################

sub getDateTimeStamp {                                                                          # shouldn't need parameters passed, only returned
                                                                                                        # use this variously
my ($dateTimeStamp,$dateStamp008,$sec,$min,$hour,$mday,$mon,$year);

($sec,$min,$hour,$mday,$mon,$year) = localtime();                                       # make the current timestamp for 005
$year += 1900; $mon += 1;                                                                       # catering to offsets.
$dateTimeStamp = sprintf("%4d%02d%02d%02d%02d%02d",$year,$mon,$mday,$hour,$min,$sec);
$dateStamp008 = sprintf("%2d%02d%02d",$year,$mon,$mday);

return ($dateTimeStamp);
}


######## parseURL       ########

sub parseURL {

my $Patron_Source_System = ${$_[0]};
my @Patron_Address_Defaults = @{$_[1]};

my ($recOp,$Patron_Given_Name,$Patron_Middle_Name,$Patron_Family_Name,$Patron_Barcode,$Patron_Borrower_Category,$Patron_Email_Address,$Patron_Email_Address_Type,$Patron_User_ID_At_Source,$Patron_Expiration_Date);

my ($primaryStreetAddressLine1, $primaryStreetAddressLine2, $primaryCountry, $primaryStateOrProvince, $primaryCityOrLocality, $primaryPostalCode);

my $q = CGI::Simple->new;

if ( defined $q->param("Patron_Given_Name") ) { $Patron_Given_Name = $q->param("Patron_Given_Name"); } else { $Patron_Given_Name = 'test11'; }
if ( defined $q->param("Patron_Middle_Name") ) { $Patron_Middle_Name = $q->param("Patron_Middle_Name"); } else { $Patron_Middle_Name = ''; }
if ( defined $q->param("Patron_Family_Name") ) { $Patron_Family_Name = $q->param("Patron_Family_Name"); } else { $Patron_Family_Name = ''; }
if ( defined $q->param("Patron_Barcode") ) { $Patron_Barcode = $q->param("Patron_Barcode"); } else { $Patron_Barcode = 'test11'; }
if ( defined $q->param("Patron_Borrower_Category") ) { $Patron_Borrower_Category = $q->param("Patron_Borrower_Category"); } else { $Patron_Borrower_Category = ''; }
if ( defined $q->param("Patron_Email_Address") ) { $Patron_Email_Address = $q->param("Patron_Email_Address"); } else { $Patron_Email_Address = 'test11'; }
if ( defined $q->param("Patron_User_ID_At_Source") ) { $Patron_User_ID_At_Source = $q->param("Patron_User_ID_At_Source"); } else { $Patron_User_ID_At_Source = 'test11'; }
if ( defined $q->param("Patron_Source_System") ) { $Patron_Source_System = $q->param("Patron_Source_System"); } else { $Patron_Source_System = $Patron_Source_System; }
if ( defined $q->param("Patron_Expiration_Date") ) { $Patron_Expiration_Date = $q->param("Patron_Expiration_Date"); } else { $Patron_Expiration_Date = ''; }

if ( defined $q->param("primaryStreetAddressLine1") ) { $primaryStreetAddressLine1 = $q->param("primaryStreetAddressLine1"); } else { $primaryStreetAddressLine1 = "$Patron_Address_Defaults[0]"; }
if ( defined $q->param("primaryStreetAddressLine2") ) { $primaryStreetAddressLine2 = $q->param("primaryStreetAddressLine2"); } else { $primaryStreetAddressLine2 = "$Patron_Address_Defaults[1]"; }
if ( defined $q->param("primaryCountry") ) { $primaryCountry = $q->param("primaryCountry"); } else { $primaryCountry = "$Patron_Address_Defaults[2]"; }
if ( defined $q->param("primaryStateOrProvince") ) { $primaryStateOrProvince = $q->param("primaryStateOrProvince"); } else { $primaryStateOrProvince = "$Patron_Address_Defaults[3]"; }
if ( defined $q->param("primaryCityOrLocality") ) { $primaryCityOrLocality = $q->param("primaryCityOrLocality"); } else { $primaryCityOrLocality = "$Patron_Address_Defaults[4]"; }
if ( defined $q->param("primaryPostalCode") ) { $primaryPostalCode = $q->param("primaryPostalCode"); } else { $primaryPostalCode = "$Patron_Address_Defaults[5]" }

if ( defined $q->param("recOp") ) { $recOp = $q->param("recOp"); } else { $recOp = '0'; }

@Patron_Address_Defaults = ($primaryStreetAddressLine1,$primaryStreetAddressLine2,$primaryCountry,$primaryStateOrProvince,$primaryCityOrLocality,$primaryPostalCode);

return ($recOp,$Patron_Given_Name,$Patron_Middle_Name,$Patron_Family_Name,$Patron_Barcode,$Patron_Borrower_Category,$Patron_Email_Address,$Patron_Email_Address_Type,$Patron_User_ID_At_Source,$Patron_Source_System,$Patron_Expiration_Date,\@Patron_Address_Defaults);
}


########################		 subroutine to write the file in XML Format          ################################

sub writePatronXMLRec {

my $xmlOutputFile = ${$_[0]};
my %bannerRecord = %{$_[1]};
my @Patron_Address_Defaults = @{$_[2]};
my $institutionId = ${$_[3]};
my $branchId = ${$_[4]};

my $output = new IO::File(">"."$xmlOutputFile");

my $writer = new XML::Writer(OUTPUT => $output,				#	Create the writer, declare the namespaces
      	                        NAMESPACES => 0,
				UNSAFE => 1				# not thrilled with this - problem with identifier data that should be in template maybe
);

$writer->xmlDecl("UTF-8","yes");				#	set up the top of file stuff - encoding, top level container
$writer->startTag("oclcPersonas","xmlns" => "http://worldcat.org/xmlschemas/IDMPersonas-1.1", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance", "xsi:schemaLocation" => "http://worldcat.org/xmlschemas/IDMPersonas-1.1 http://worldcat.org/xmlschemas/IDMPersonas/1.1/IDMPersonas-1.1.xsd");
print $output "\n";


my $p_barcode = $bannerRecord{'Patron_Barcode'};
my $given_Name = Encode::encode_utf8($bannerRecord{'Patron_Given_Name'});
my $idAtSource = $bannerRecord{'Patron_User_ID_At_Source'};


if ($p_barcode ne '' && $given_Name ne '' && $idAtSource ne '') {

	$writer->startTag("persona","institutionId" => "$institutionId");
	print $output "\n";

my $emailAddress = $bannerRecord{'Patron_Email_Address'};
my $sourceSystem = $bannerRecord{'Patron_Source_System'};

	$writer->startTag("correlationInfo");					#  Banner Unique ID
		$writer->startTag("sourceSystem");
			$writer->characters("$sourceSystem");			
		$writer->endTag("sourceSystem");
		$writer->startTag("idAtSource");
			$writer->characters($idAtSource);
		$writer->endTag("idAtSource");
	$writer->endTag("correlationInfo");
	print $output "\n";

my $middleName = Encode::encode_utf8($bannerRecord{'Patron_Middle_Name'});
my $family_Name = Encode::encode_utf8($bannerRecord{'Patron_Family_Name'});

	$writer->startTag("nameInfo");						# OCLC Names
		$writer->startTag("givenName");
			$writer->characters($given_Name);
		$writer->endTag("givenName");
		if ($middleName ne '') {
			$writer->startTag("middleName");
				$writer->characters($middleName);
			$writer->endTag("middleName");
		}
		$writer->startTag("familyName");
			$writer->characters($family_Name);
		$writer->endTag("familyName");
	$writer->endTag("nameInfo");
	print $output "\n";

my $borrowerCategory = $bannerRecord{'Patron_Borrower_Category'};
my $exp_date = $bannerRecord{'Patron_Expiration_Date'};
	
	$writer->startTag("wmsCircPatronInfo");					# Patron Info Section
		$writer->startTag("barcode");
			$writer->characters($p_barcode);
		$writer->endTag("barcode");
		$writer->startTag("borrowerCategory");
			$writer->characters($borrowerCategory);
		$writer->endTag("borrowerCategory");
		$writer->startTag("circExpirationDate");
			$writer->characters("$exp_date");
		$writer->endTag("circExpirationDate");
		$writer->startTag("homeBranch");
			$writer->characters("$branchId");
		$writer->endTag("homeBranch");
	$writer->endTag("wmsCircPatronInfo");
	print $output "\n";


if ($emailAddress ne '') {
	$writer->startTag("contactInfo");					#  contact info
		$writer->startTag("email");					#  email address
			$writer->startTag("emailAddress");
				$writer->characters($emailAddress);
			$writer->endTag("emailAddress");
			$writer->startTag("isPrimary");
				$writer->characters("true");
			$writer->endTag("isPrimary");
		$writer->endTag("email");
	$writer->endTag("contactInfo");
	print $output "\n";
}

my ($primaryStreetAddressLine1,$primaryStreetAddressLine2,$primaryCountry,$primaryStateOrProvince,$primaryCityOrLocality,$primaryPostalCode);

	$primaryStreetAddressLine1 = $Patron_Address_Defaults[0];
	$primaryStreetAddressLine2 = $Patron_Address_Defaults[1];
	$primaryCountry = $Patron_Address_Defaults[2];
	$primaryStateOrProvince = $Patron_Address_Defaults[3];
	$primaryCityOrLocality = $Patron_Address_Defaults[4];
	$primaryPostalCode = $Patron_Address_Defaults[5];

$writer->startTag("contactInfo");					#  contact info
		$writer->startTag("physicalLocation");				#  postal address
			$writer->startTag("postalAddress");
				$writer->startTag("streetAddressLine1");
					$writer->characters($primaryStreetAddressLine1);
				$writer->endTag("streetAddressLine1");
				$writer->startTag("streetAddressLine2");
					$writer->characters($primaryStreetAddressLine2);
				$writer->endTag("streetAddressLine2");
				$writer->startTag("cityOrLocality");
					$writer->characters($primaryCityOrLocality);
				$writer->endTag("cityOrLocality");
				$writer->startTag("stateOrProvince");
					$writer->characters($primaryStateOrProvince);
				$writer->endTag("stateOrProvince");
				$writer->startTag("postalCode");
					$writer->characters($primaryPostalCode);
				$writer->endTag("postalCode");
				$writer->startTag("country");
					$writer->characters($primaryCountry);
				$writer->endTag("country");
			$writer->endTag("postalAddress");
			$writer->startTag("isPrimary");
				$writer->characters("true");
			$writer->endTag("isPrimary");
		$writer->endTag("physicalLocation");
$writer->endTag("contactInfo");

print $output "\n";

	$writer->endTag("persona");								#	Add the closing record tag
	print $output "\n";

} # end check for 3 needed elements

## write the bottom of the XML file

$writer->endTag("oclcPersonas");				#	close the beginning tag for the file
print $output "\n";
$writer->end();							#	Do the writer output to the file
$output->close();						#	close the output file

my $opMessage = '<p><b>'.$xmlOutputFile.' written</b></p>';

return ($opMessage)

} ## end subroutine


###########################   Print the html for a form  ##########################

sub printEntryHTML {

# get file sizes and dates

my ($dirList,$selectFile,$fileDirectory,$opMessage,$Patron_Source_System,@Patron_Types,@Patron_Address_Defaults);

$opMessage = ${$_[0]};
$fileDirectory = ${$_[1]};
$selectFile = ${$_[2]};
$Patron_Source_System = ${$_[3]};
@Patron_Types = @{$_[4]};
@Patron_Address_Defaults = @{$_[5]};

## Address Fields : primaryStreetAddressLine1, primaryStreetAddressLine2, primaryCountry, primaryStateOrProvince, primaryCityOrLocality, primaryPostalCode
my ($primaryStreetAddressLine1, $primaryStreetAddressLine2, $primaryCountry, $primaryStateOrProvince, $primaryCityOrLocality, $primaryPostalCode ) = (@Patron_Address_Defaults);

my $directory = $fileDirectory;					## Make a listing of the files for download	
   opendir (DIR, $directory) or die $!;
while (my $file = readdir(DIR)) {
        my @fileStuff = stat $directory.$file;
        my $fileTime = &makeTime(\$fileStuff[9]);
        if ( $file =~ /\.xml/ ) {
                $dirList .= '<a href="./tmp/'.$file.'">'.$file.'</a>&nbsp;&nbsp;'."$fileStuff[7]".'&nbsp;&nbsp'."$fileTime".'<br/>';
       }
}

my $pTypeList = '';						## Make the Borrower type selection html
foreach my $pType(@Patron_Types) {
	$pTypeList .='<option>'.$pType.'</option>';
}

print <<END_of_Start;
Content-type: text/html

<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>

<title>Make a Patron Record to load</title>

</head>
<body>

<p><strong><span class="BigRedTitle">Make a Patron File to Load</span></strong></p>

$opMessage

<form action="fixOnePatron_new.pl" method="POST" enctype="multipart/form-data">

<strong>Patron Fields</strong><br/>
<p>Fill in the patron information available.  Use this form principally to fix an IDatSource / Login for a patron.</p>

<table>
<tr><td colwidth="1"><strong>Given Name :</strong> </td><td><input type="text" size="30" name="Patron_Given_Name"/></td>
<td><strong>Middle Name :</strong> </td><td><input type="text" size="30" name="Patron_Middle_Name"/></td>
<td><strong>Family Name :</strong> </td><td><input type="text" size="30" name="Patron_Family_Name"/></td></tr>

<tr><td colwidth="1"><strong>Barcode :</strong> </td><td><input type="text" size="30" name="Patron_Barcode"/></td>
<td colwidth="2"><strong>Email Address :</strong> </td><td><input type="text" size="30" name="Patron_Email_Address"/></td></tr>

<tr><td colwidth="1"><strong>Type :</strong> </td><td><select name="Patron_Borrower_Category"/>
$pTypeList
</select></td>
<td colwidth="2"><strong>Expiration date (yyyy-mm-ddT23:59:59) :</strong> </td><td><input type="text" size="30" name="Patron_Expiration_Date"/></td></tr>

<tr><td colwidth="1"><strong>Login (g00000001) :</strong> </td><td><input type="text" size="30" name="Patron_User_ID_At_Source"/></td>
<td colwidth="2"><strong>Source System :</strong> </td><td><input type="text" size="30" name="Patron_Source_System" value = "$Patron_Source_System"/></td></tr>
<tr><td colwidth="3">&nbsp;</td><tr/>
<tr><td><strong>Street Address 1:</strong> </td><td><input type="text" size="30" name="primaryStreetAddressLine1" value="$primaryStreetAddressLine1" /></td>
<td colwidth="2"><strong>Street Address 1:</strong> </td><td><input type="text" size="30" name="primaryStreetAddressLine2" value="$primaryStreetAddressLine2" /></td></tr>

<tr><td><strong>City :</strong> </td><td><input type="text" size="20" name="primaryCityOrLocality" value ="$primaryCityOrLocality" /></td>
<td colwidth="2"><strong>Province :</strong> </td><td><input type="text" size="20" name="primaryStateOrProvince" value="$primaryStateOrProvince" /></td></tr>

<tr><td><strong>Postcode :</strong> </td><td><input type="text" size="10" name="primaryPostalCode" value="$primaryPostalCode" /></td>
<td colwidth="2"><strong>Country :</strong> </td><td><input type="text" size="30" name="primaryCountry" value="$primaryCountry" /></td></tr>
</table>
<br/>
<input type="hidden" name="recOp" value="1"/>

<input type="submit" name="submit" value="Submit"/>

	
</form>

<strong>XML Files</strong><br/>
<p>These are the existing XML Files. Right click a processed file to download it and upload it to OCLC </p>
<p>$dirList</p>

</body>
</html>
END_of_Start

} # end top sub


############################   Main Execution    ###########################

my ( $recOp,$selectFile,$fileDirectory,$opMessage,%bannerRecord );
my ($Patron_Given_Name,$Patron_Middle_Name,$Patron_Family_Name,$Patron_Barcode,$Patron_Borrower_Category,$Patron_Email_Address,$Patron_Email_Address_Type,$Patron_User_ID_At_Source,$Patron_Expiration_Date);

my $dateTimeStamp = &getDateTimeStamp();
 
## Institution defaults.  Our Library doesn't load individual patron addresses and only has one institution and one branch.
## OCLC registry ID and and branch number.  List of Borrower types from WMS
my $Patron_Source_System = 'https://idp.some.edu/idp/shibboleth';
my $Patron_Institution = '11111';
my $Patron_Home_Branch = '222222';
my @Patron_Types = ('Alumni', 'External', 'Faculty', 'Family', 'Graduate', 'ILL', 'Library', 'Staff', 'Student', 'Visiting');

## Address Fields : primaryStreetAddressLine1, primaryStreetAddressLine2, primaryCountry, primaryStateOrProvince, primaryCityOrLocality, primaryPostalCode
## set these to '' if you store individual physical address information : AUS only loads default information that WMS requires to be filled out to load 
## example my @Patron_Address_Defaults = ('My University Library','1111 Some Street','USA','FL','Sarasota','34238',);
my @Patron_Address_Defaults = ('Default','Default','Default','Default','Default','Default',);
my $Patron_Address_Defaults_ref = \@Patron_Address_Defaults;
my $Patron_Address_Params_ref;

## this can be any directory that the script can access and write to
$fileDirectory = './tmp/';
## change this if you want a different filename
$selectFile = 'OnePatronFile_'.$dateTimeStamp.'.xml';
$opMessage = '';
$recOp = 0;

($recOp,$Patron_Given_Name,$Patron_Middle_Name,$Patron_Family_Name,$Patron_Barcode,$Patron_Borrower_Category,$Patron_Email_Address,$Patron_Email_Address_Type,$Patron_User_ID_At_Source,$Patron_Source_System,$Patron_Expiration_Date,$Patron_Address_Params_ref) = &parseURL(\$Patron_Source_System,\@Patron_Address_Defaults);

$bannerRecord{'Patron_Given_Name'} = $Patron_Given_Name;
$bannerRecord{'Patron_Middle_Name'} = $Patron_Middle_Name;
$bannerRecord{'Patron_Family_Name'} = $Patron_Family_Name;
$bannerRecord{'Patron_Barcode'} = $Patron_Barcode;
$bannerRecord{'Patron_Borrower_Category'} = $Patron_Borrower_Category;
$bannerRecord{'Patron_Email_Address'} = $Patron_Email_Address;
$bannerRecord{'Patron_User_ID_At_Source'}= $Patron_User_ID_At_Source;
$bannerRecord{'Patron_Source_System'} = $Patron_Source_System;
$bannerRecord{'Patron_Expiration_Date'} = $Patron_Expiration_Date;

if ( $recOp != 1 ) {
        &printEntryHTML(\$opMessage,\$fileDirectory,\$selectFile,\$Patron_Source_System,\@Patron_Types,\@Patron_Address_Defaults);
} elsif ( $recOp == 1 ) {								## take the form output and write an XML file
	my $xmlOutputFile = $fileDirectory.$selectFile;
	@Patron_Address_Defaults = @{$Patron_Address_Params_ref};
	$opMessage = &writePatronXMLRec(\$xmlOutputFile,\%bannerRecord,\@Patron_Address_Defaults,\$Patron_Institution,\$Patron_Home_Branch);
        &printEntryHTML(\$opMessage,\$fileDirectory,\$selectFile,\$Patron_Source_System,\@Patron_Types,\@Patron_Address_Defaults);
} else {
        &printEntryHTML(\$opMessage,\$fileDirectory,\$selectFile,\$Patron_Source_System,\@Patron_Types,\@Patron_Address_Defaults);
}
