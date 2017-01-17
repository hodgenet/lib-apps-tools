#!/usr/bin/perl 
##-w

use strict;
use lib '/path/to/OCLC Auth Modules/';
use OCLCAuth qw(:All);
use OCLCCred;
use LWP::UserAgent;
use Data::Dumper;
use XML::Parser;                                                        #       use Parser to read the XML file,
use XML::SimpleObject;                                                  #       Simple Object to handle the actual records

## This script is builds two files: 1) an xml dublin core file containing records of your WC Knowledgebase Collections, and 2) a delimited
## file suitable for loading into libguides as a resource file.  It does this by using the License Manager Beta API and doing a full list of 
## of all licenses, parsing them to get the descriptions and the associated collections id, then retrieving each collection record, and 
## writing records for it to the delimited and xml files.  We use the XML file with an XSL sheet to build website database pages,
## though we're looking at just using the Libguide A-Z pages


########################		 subroutine to normalize a title		################################

sub normalizeTitle {

	my $ntitle = $_[0];
	$ntitle =~ s/[\s\.:\/]$//g;		#	Remove trailing punctuation
	$ntitle =~ s/[\s]$//g;
	$ntitle =~ s/^The //;			#	Remove initial article
	$ntitle =~ s/^An //;			#	Remove initial article
	$ntitle =~ s/^A //;			#	Remove initial article
	$ntitle = ucfirst($ntitle);

return $ntitle;
}


########################		 subroutine to normalize a websubject		################################

sub normalizeWebSubject {

	my $nwsubject = $_[0];
	$nwsubject =~ s/&/&amp;/g;		#	entitize any ampersands
	$nwsubject =~ s/\"//g;			#	entitize any quotes
	$nwsubject =~ s/\.$//g;			#	Remove trailing period

return $nwsubject;
}


########################		 subroutine to normalize a description		################################

sub normalizeDescription {

	my $ndescription = $_[0];
#	$ndescription =~ s/&/&amp;/g;		#	entitize any ampersands
#	$ndescription =~ s/>/&gt;/g;		#	convert any arrow brackets
#	$ndescription =~ s/</&lt;/g;		#	convert any arrow brackets
	$ndescription =~ s/&quot /&quot;/g;
	$ndescription =~ s/\{u00AE\}/&#169;/g;		#	convert any arrow brackets
	$ndescription =~ s/\{u2122\}/&#8482;/g;		#	convert any arrow brackets
	$ndescription =~ s/\{u2019\}/\'/g;		#	convert any arrow brackets
	$ndescription =~ s/\{u2014\}/&#8212;/g;		#	convert any arrow brackets
	$ndescription =~ s/\{u201C\}/&#x34;/g;		#	convert any arrow brackets
	$ndescription =~ s/\{u201D\}/&#34;/g;		#	convert any arrow brackets
	$ndescription =~ s/\{u00E6\}/&#230;/g;		#	convert any arrow brackets

	$ndescription = ucfirst($ndescription);

return $ndescription;
}


########################		 subroutine to normalize an identifier		################################

sub normalizeIdentifier {

	my $nidentifier = $_[0];
	$nidentifier =~ s/&/&amp;/g;		#	entitize any ampersands
	$nidentifier =~ s/^\s//g;
	$nidentifier =~ s/\s$//g;

return $nidentifier;
}


############   get/make the value for totalResults from the current result ############

sub parseLicenses {

open (OUT, ">> ./licCollOut.txt") or die $!;
binmode OUT, ":utf8";

open (LIBG, ">> ./libguideFile.txt") or die $!;
binmode LIBG, ":utf8";

print LIBG "vendor\tname\turl\tenable_proxy\tdescription\tcontent_id\n";

	my $apiRecord = ${$_[0]}; 
	my $totalResults = 0; my $theseItemsPerPage;
	my $parser = new XML::Parser(ErrorContext => 1,                       #       Create the parser, parse records as a tree
                           Style => "Tree");
	my $xso = XML::SimpleObject->new($parser->parse("$apiRecord"));      #       Create the object for the parsed records and read

	$totalResults = $xso->child('feed')->child('os:totalResults')->value; 

foreach my $entry ( $xso->child('feed')->child('entry') )  {

	my $licID = $entry->child('content')->child('license')->child('id')->value;
	my $licName = $entry->child('content')->child('license')->child('name')->value;
print OUT "License Name: \t$licName\n";
	my $licDescription = '';
	if ( defined $entry->child('content')->child('license')->child('description') ) { 
		$licDescription = $entry->child('content')->child('license')->child('description')->value;
print OUT "$licDescription\n\n";
	}

	foreach my $collection ( $entry->child('content')->child('license')->child('collections')->child('collection') ) {
		my ($thisCollectionName, $thisCollectionProvider);
		my $thisCollectionID = $collection->child('id')->value;
		if ( defined $collection->child('name') ) { $thisCollectionName = $collection->child('name')->value; } else { $thisCollectionName = 'No Name'; }
		if ( defined $collection->child('provider') ) { $thisCollectionProvider = $collection->child('provider')->value; }

print OUT "\tCollection Name :\t$thisCollectionName\t";
print "\tCollection ID :\t$thisCollectionID\t";
print "\tCollection Name :\t$thisCollectionName\t";

		## TODO Store these in a data structure for collections
		my $thisXMLCollectionRecord = getCollectionRecord(\$thisCollectionID,\$thisCollectionName);	## call getCollectionRecord
		my $thisCollectionUrl = ''; my $summary = ''; my $content_id = ''; my $owner_institution = ''; my $source_institution = ''; 
		my $staff_notes = ''; my $public_notes = ''; my $provider_name = ''; my $localstem = '';
		($thisCollectionUrl,$summary,$content_id,$public_notes,$staff_notes,$owner_institution,$source_institution,$provider_name,$localstem) = parseCollectionRecord(\$thisXMLCollectionRecord);
print OUT "URL : $thisCollectionUrl\n";
print "Content ID in parseLicense: $content_id\n";
		my $libGDesc = '';
		if ( $summary ne '' ) { print OUT "\tCollection Summary: \t$summary\n\n"; $libGDesc = $summary; } else { print OUT "\n"; $libGDesc = $licDescription; }
		if ( $content_id ne '' ) { print OUT "\tContentID: \t$content_id\n"; } else { print OUT "\n"; }
		if ( $owner_institution ne '' ) { print OUT "\tOwner Inst: \t$owner_institution\t"; } else { print OUT "\t"; }
		if ( $source_institution ne '' ) { print OUT "\tSource Inst: \t$source_institution\n"; } else { print OUT "\n"; }
		if ( $staff_notes ne '' ) { print OUT "\tStaff Notes: \t$staff_notes\n"; } else { print OUT "\n"; }
		if ( $public_notes ne '' ) { print OUT "\tPublic Notes: \t$public_notes\n\n"; } else { print OUT "\n"; }
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

#warn Dumper ($xso);

my $collectionUrl = '';
foreach my $link ( $xso->child('entry')->child('link') )  {
	my %attributes = $link->attributes;
	if ($attributes{'rel'} eq 'via' ) { $collectionUrl = $attributes{'href'};
#	if ( $link->attribute eq "rel"  && $link->attribute('rel')->value eq "via") {
#		$collectionUrl = $link->attribute('href')->value;
	}

}
print " URL in parseCollection: $collectionUrl\n";
my $summary = ''; my $content_id = '';
if ( defined $xso->child('entry')->child('summary') ) {
	$summary = $xso->child('entry')->child('summary')->value;
	if ( $summary =~ /content_id:([\d]{6,10})/ ) {
		$content_id = $1;
		$summary =~ s/content_id:$1//;
	}
}
print "\n";
print "CollectionID in parseCollection : $content_id\n";
print "Summary in parseCollection : $summary\n";
print "\n";
my $staff_notes = '';
if ( defined $xso->child('entry')->child('kb:collection_staff_notes') ) {
	$staff_notes = $xso->child('entry')->child('kb:collection_staff_notes')->value;
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


#my $collectionTitle = $xso->child('entry')->child('title')->value;
#my $collectionID = $xso->child('entry')->child('kb:collection_uid')->value;

#$collectionRecord{$collectionID} = $collectionUrl;

#return (\%collectionRecord);
return ($collectionUrl,$summary,$content_id,$public_notes,$staff_notes,$owner_institution,$source_institution,$provider_name,$localstem);

}


######################### Get a Collection Record ######################################

sub getCollectionRecord {

my $collectionID = ${$_[0]}; my $collectionName = ${$_[1]}; 

my $parmfile = '/path/to/param/file.txt';				## module will need to accept parameters - key, secret, principalID, registryID, principalIDNS.  Need to be stored securely
##my ($key,$secret,$principalID,$principalIDNS,$registryID,$regionHost) = &getAPIParams(\$parmfile);
my %instParams = %{get_ip(\$parmfile)};
my $wskey = $instParams{'wskey'};
my $institutionID = $instParams{'contextInstitutionId'};

my $apiURL = 'https://worldcat.org/webservices/kb/rest/collections/'.$collectionID.','.$institutionID;		## for KB Manager API
#my $apiURL = 'https://worldcat.org/webservices/kb/rest/collections/seach?intitution_uid='.$institutionID.'&collection_uid='.$collectionID;		## for KB Manager API

my %queryParams = ('wskey'=>"$wskey");						## for APIs that use WSKEY query paramete
my $ua = LWP::UserAgent->new;
$ua->timeout(20);
$ua->protocols_allowed( ['http', 'https'] );

my $requestURL = make_hru(\$apiURL,\%queryParams);		## Call makeOCLCRequestURL function to make the URL correctly
my $response = $ua->get($requestURL);						## for  ??
my $apiRecord = $response->content;

if (defined $apiRecord) {
print "\n";
##	warn Dumper($apiRecord);
}

return ($apiRecord);

}


################################   Main execution #######################################


## Get the record data
my $parmfile = '/path/to/param/file.txt';				## module will need to accept parameters - wskey, secret, principalID, principalIDNS
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
##warn Dumper ($accessToken);							## Debugging
my $atAuthHeader = make_atah(\$accessToken);
##print "Access Token Header : $atAuthHeader\n";					## Debugging

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
##warn Dumper($response);							## debugging : uncomment if you want to see the request/response

	my $apiRecord = $response->content;
warn Dumper($apiRecord);							## debugging: dumps results to screen. Modify parseApiRecord to output entries to file
	
	($totalResults) = parseLicenses(\$apiRecord);
## print "Total results : $totalResults\n";
	$startIndex = $startIndex + $itemsPerPage;				## increment the start index for next batch
}


