#!/usr/bin/perl 

use strict;
use lib '/path/to/OCLC Auth Mods/';
use OCLCAuth qw(:All);
use OCLCCred;
use LWP::UserAgent;
use LWP::Simple;
use CGI::Simple;
use XML::Parser;                                                        #       use Parser to read the XML file,
use XML::SimpleObject;                                                  #       Simple Object to handle the actual records

## This script is builds  a delimited file suitable for loading into libguides as a resource file.  It does this by using the License Manager 
## Beta API and doing a full list of of all licenses, parsing them to get the descriptions and the associated collections id, then retrieving 
## each collection record, and writing records for it to the delimited file.  We plan to use the Libguide A-Z pages to replace the XML based pages


######## makeTime       #######

sub makeTime {

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$fileTime);

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(${$_[0]});

$fileTime = ($year+1900).'-'.($mon+1).'-'.$mday."  $hour:$min";

return ($fileTime);

}


######## parseURL       ########

sub parseURL {

my $harvest;

my $q = CGI::Simple->new;

if ( defined $q->param("harvest") ) { $harvest = $q->param("harvest"); } else { $harvest = '0'; }

return ($harvest);

}


############   get/make the value for totalResults from the current result ############

sub parseLicenses {

	my $apiRecord = ${$_[0]}; 
	my $totalResults = 0; my $theseItemsPerPage;
	my $parser = new XML::Parser(ErrorContext => 1,                       #       Create the parser, parse records as a tree
                           Style => "Tree");
	my $xso = XML::SimpleObject->new($parser->parse("$apiRecord"));      #       Create the object for the parsed records and read

	$totalResults = $xso->child('feed')->child('os:totalResults')->value; 

foreach my $entry ( $xso->child('feed')->child('entry') )  {

	my $licID = $entry->child('content')->child('license')->child('id')->value;
	my $licName = $entry->child('content')->child('license')->child('name')->value;

	my $licDescription = '';
	if ( defined $entry->child('content')->child('license')->child('description') ) { 
		$licDescription = $entry->child('content')->child('license')->child('description')->value;
	}

	foreach my $collection ( $entry->child('content')->child('license')->child('collections')->child('collection') ) {
		my ($thisCollectionName, $thisCollectionProvider);
		my $thisCollectionID = $collection->child('id')->value;
		if ( defined $collection->child('name') ) { $thisCollectionName = $collection->child('name')->value; } else { $thisCollectionName = 'No Name'; }
		if ( defined $collection->child('provider') ) { $thisCollectionProvider = $collection->child('provider')->value; }

		## TODO Store these in a data structure for collections
		my $thisXMLCollectionRecord = getCollectionRecord(\$thisCollectionID,\$thisCollectionName);	## call getCollectionRecord
		my $thisCollectionUrl = ''; my $summary = ''; my $content_id = ''; my $owner_institution = ''; my $source_institution = ''; 
		my $staff_notes = ''; my $public_notes = ''; my $provider_name = ''; my $localstem = '';
		($thisCollectionUrl,$summary,$content_id,$public_notes,$staff_notes,$owner_institution,$source_institution,$provider_name,$localstem) = parseCollectionRecord(\$thisXMLCollectionRecord);

		my $libGDesc = '';
		if ( $summary ne '' ) { $libGDesc = $summary; } else { $libGDesc = $licDescription; }
		if ( $localstem eq 'false' ) { $localstem = 0; } else { $localstem = 1; }
		print LIBG "$provider_name\t$thisCollectionName\t$thisCollectionUrl\t$localstem\t$libGDesc\t$content_id\n";
	}
}

return ($totalResults);
}


############   ############

## Information required : Name, Description, url, collections, subjects, full text indicator,  ?

sub parseCollectionRecord {

my $collectionXMLRecord = ${$_[0]}; my %collectionRecord = ();

my $parser = new XML::Parser(ErrorContext => 1,                       #       Create the parser, parse records as a tree
                           Style => "Tree");
my $xso = XML::SimpleObject->new($parser->parse("$collectionXMLRecord"));      #       Create the object for the parsed records and read

my $collectionUrl = '';
foreach my $link ( $xso->child('entry')->child('link') )  {
	my %attributes = $link->attributes;
	if ($attributes{'rel'} eq 'via' ) { $collectionUrl = $attributes{'href'};
	}

}

my $summary = ''; 
if ( defined $xso->child('entry')->child('summary') ) {
	$summary = $xso->child('entry')->child('summary')->value;
}

my $staff_notes = ''; my $content_id = '';
if ( defined $xso->child('entry')->child('kb:collection_staff_notes') ) {
	$staff_notes = $xso->child('entry')->child('kb:collection_staff_notes')->value;
	if ( $staff_notes =~ /content_id:([\d]{6,10})/ ) {
		$content_id = $1;
		$staff_notes =~ s/content_id:$1//;
	}
}

my $public_notes = '';
if ( defined $xso->child('entry')->child('kb:collection_user_notes') ) {
	$public_notes = $xso->child('entry')->child('kb:collection_user_notes')->value;
}

my $owner_institution = '';
if ( defined $xso->child('entry')->child('kb:owner_institution') ) {
	$owner_institution = $xso->child('entry')->child('kb:owner_institution')->value;
}

my $source_institution = '';
if ( defined $xso->child('entry')->child('kb:source_institution') ) {
	$source_institution = $xso->child('entry')->child('kb:source_institution')->value;
}

my $provider_name = '';
if ( defined $xso->child('entry')->child('kb:provider_name') ) {
	$provider_name = $xso->child('entry')->child('kb:provider_name')->value;
}

my $localstem = '';
if ( defined $xso->child('entry')->child('kb:localstem') ) {
	$localstem = $xso->child('entry')->child('kb:localstem')->value;
}

return ($collectionUrl,$summary,$content_id,$public_notes,$staff_notes,$owner_institution,$source_institution,$provider_name,$localstem);

}


######################### Get a Collection Record ######################################

sub getCollectionRecord {

my $collectionID = ${$_[0]}; my $collectionName = ${$_[1]}; 

my $parmfile = '/path/to/param/file.txt';				## module will need to accept parameters - key, secret, principalID, registryID, principalIDNS.  Need to be stored securely

my %instParams = %{get_ip(\$parmfile)};
my $wskey = $instParams{'wskey'};
my $institutionID = $instParams{'contextInstitutionId'};

my $apiURL = 'https://worldcat.org/webservices/kb/rest/collections/'.$collectionID.','.$institutionID;		## for KB Manager API
#my $apiURL = 'https://worldcat.org/webservices/kb/rest/collections/search';  # for doing a search, need to modify routine to find the entry if you use this

my %queryParams = ('wskey'=>"$wskey");						## for APIs that use WSKEY query parameter
#my %queryParams = ('institution_uid'=>"$institutionID",'collection_uid'=>"$collectionID",'wskey'=>"$wskey");  # for doing a search, need to modify routine to find the entry if you use this

my $ua = LWP::UserAgent->new;
$ua->timeout(20);
$ua->protocols_allowed( ['http', 'https'] );

my $requestURL = make_hru(\$apiURL,\%queryParams);		## Call makeOCLCRequestURL function to make the URL correctly
my $response = $ua->get($requestURL);						## for  ??
my $apiRecord = $response->content;

return ($apiRecord);
}

######## printHTML      ########

sub printHTML {                                                 #       pass in middle bit

my ($dirList);

my $directory = './tmp/';					## Make a listing of the files for download	
   opendir (DIR, $directory) or die $!;

while (my $file = readdir(DIR)) {
        my @fileStuff = stat $directory.$file;
        my $fileTime = &makeTime(\$fileStuff[9]);
        if ( $file =~ /\.txt/ ) {
                $dirList .= '<a href="./tmp/'.$file.'">'.$file.'</a>&nbsp;&nbsp;'."$fileStuff[7]".'&nbsp;&nbsp'."$fileTime".'<br/>';
       }
}


print <<END_of_Start;
Content-type: text/html

<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
<link href="http://library.aus.edu/Styles/LibMain.css" rel="stylesheet" type="text/css" />
<link href="http://library.aus.edu/Styles/screen.css" rel="stylesheet" media="screen" type="text/css" />
<link href="http://library.aus.edu/Styles/print.css" rel="stylesheet" media="print" type="text/css" />

<title>Harvest Collections for Database Pages</title>

</head>
<body>

<h2>Harvest Collections for Database Pages</h2>

<form action="makeDb4LGonline.pl" method="POST" enctype="multipart/form-data">
<input type="hidden" name="harvest" value="1"/>
<input type="submit" name="submit" value="Submit"/>
</form>

<strong>Libguide-loadable Database File</strong><br/>
<p>This is the Libguides loadable file from the last harvest.  Click the button above to re-harvest and make a new file</p>
<p>$dirList</p>


</body>
</html>
END_of_Start

}


################################   get all of the License Records #######################################

sub getLicenses {

## Get the record data
my $parmfile = '/path/to/param/file.txt';
				## module will need to accept parameters - wskey, secret, principalID, principalIDNS
										## auth registryID, context registryID, datacenter
my %instParams = %{get_ip(\$parmfile)};

my $startIndex = 1;								## values for the query parameters
my $itemsPerPage = 15;
my $totalResults = 15;
my $runningResults = 0;
my $licenseStatusFilter = 'current';

my $apiURL = 'https://'.$instParams{'authenticatingInstitutionId'}.'.share.worldcat.org/license-manager/license/list';			## for License Manager API
my $APIService = 'WMS_LMAN';
my $accessToken = request_at_ccg(\$APIService,\%instParams);			## TODO add some code to keep track of expiration
my $atAuthHeader = make_atah(\$accessToken);

open (LIBG, "> ./tmp/libguideFile.txt") or die $!;
binmode LIBG, ":utf8";

print LIBG "vendor\tname\turl\tenable_proxy\tdescription\tcontent_id\n";

############## Set the request ###################

my $ua = LWP::UserAgent->new;
$ua->timeout(20);								## fiddle with this or check and increment if you get a timeout
$ua->protocols_allowed( ['http', 'https'] );

############## Loop through the licenses ###########

while ( $startIndex < $totalResults) {					## when total results falls below itemsPerPage, we have everything

	my %queryParams = ('itemsPerPage'=>$itemsPerPage,'startIndex'=>$startIndex,'q'=>"licenseStatus:$licenseStatusFilter");		## for License Manager API
	my $requestURL = make_hru(\$apiURL,\%queryParams);			## Call makeOCLCRequestURL function to make the URL correctly
print "Request URL in Main : $requestURL\n";					## Debugging

	my $response = $ua->get($requestURL, 'Authorization'=>$atAuthHeader);	## for APIs that send an authHeader.

	my $apiRecord = $response->content;
	
	($totalResults) = parseLicenses(\$apiRecord);

	$startIndex = $startIndex + $itemsPerPage;				## increment the start index for next batch
}

close LIBG;

}


################################   Main execution #######################################

my $harvest = parseURL();

if ( $harvest == 1 ) { 
	getLicenses();
	printHTML();
} else {
	printHTML();
}
