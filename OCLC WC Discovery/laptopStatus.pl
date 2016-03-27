#!/usr/bin/perl

use strict;

use LWP::Simple;
use HTTP::Cookies;
#( autosave => 1, file => "$ENV{'HOME'}/lwp_cookies.dat" );

use Digest::SHA qw(hmac_sha256_base64);
require LWP::UserAgent;
use LWP::Protocol::https;

#use XML::XPath;
use XML::Parser;                                                        #       use Parser to read the XML file,
use XML::SimpleObject;                                                  #       Simple Object to handle the actual records

use CGI qw(:param);
use Date::Simple ('date','today');                                      #       Date::Simple is useful for making filenames
use Data::Dumper::Simple;



######## makeTime       #######

sub makeTime {

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$fileTime,$displayTime);
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
# $fileTime = ($year+1900).($mon+1).$mday.$hour.$min.$sec;
if (length $min == 1) {$min = '0'.$min;}
$mon = $mon + 1;
if (length $mon == 1) {$mon = '0'.$mon;}
if (length $mday == 1) {$mday = '0'.$mday;}

$displayTime = ($year+1900).'-'.$mon.'-'.$mday.' '.$hour.':'.$min;

return ($displayTime);

}

######################### compute the Signature for Authentication #########################

sub makeOCLCHMACSignature {

my $httpMethod = ${$_[0]}; my $secret = ${$_[1]};  my $key = ${$_[2]}; my @queryParams = @{$_[3]};

## values unlikely to change
my $oclcurl = 'www.oclc.org';
my $port = '443';
my $path = '/wskey';
## values calculated at request time
my $nonce = int(rand(1000000));			##Set nonce for authentication string
my $timestamp = time;				##Set current time for authentication string

my $search = '';
while ($#queryParams >= 0) {			## Create the Availability search string.  Must be reverse of actual url parameters
	my $lastParam = pop @queryParams;
	if ($#queryParams != -1) { $search = $search.$lastParam."\n"; } else { $search = $search.$lastParam; }
}

my $string = $key."\n".$timestamp."\n".$nonce."\n"."\n".$httpMethod."\n".$oclcurl."\n".$port."\n".$path."\n".$search."\n";		## Create the request header
my $encodedString = hmac_sha256_base64($string, $secret);			##Hash the authentication string in SHA-256
while (length($encodedString) % 4) {
                $encodedString .= '=';
}

return ($encodedString,$timestamp,$nonce);
}


######################### make the Authentication header #########################

sub makeAuthHeader {

my $httpMethod = ${$_[0]}; my $secret = ${$_[1]}; my $key = ${$_[2]}; 
my $principalID = ${$_[3]}; my $principalIDNS = ${$_[4]}; my @queryParams = @{$_[5]}; 

my ($encodedString,$timestamp,$nonce) = &makeOCLCHMACSignature(\$httpMethod,\$secret,\$key,\@queryParams);

my $authHeader = 'http://www.worldcat.org/wskey/v2/hmac/v1 clientId="'.$key.'", timestamp="'.$timestamp.'", nonce="'.$nonce.'", signature="'.$encodedString.'", principalID="'.$principalID.'", principalIDNS="'.$principalIDNS.'"';

return ($authHeader);

}


######## getParams      ########
sub getParams {                                                         ## get permanent values from the param file
my ($key, $secret,$principalID,$paramFile,@parmArray);
$paramFile = ${$_[0]};
open PARMFILE, $paramFile;
binmode PARMFILE, ":utf8";
while (<PARMFILE>) {
        chomp $_;
        push @parmArray,$_;
}
close (PARMFILE);
($key,$secret,$principalID) = (@parmArray);
return ($key,$secret,$principalID);
}



########  getItemInfo ########

sub getItemInfo {

## stuff coming in from HMAC test
## value mostly unique to this site, but that dont' change much 
my $parmfile = '/home/wordpress/.params/APIParms.txt';
my ($key,$secret,$principalID) = &getParams(\$parmfile);

my $registryID = '87830';					## production
my $principalIDNS = 'urn:oclc:wms:da';

## values unique to this application
my $oclcnum = '933598360';					##Read in each OCLC number as variable $oclcnum (production)
my $httpMethod = 'GET';
my $apiURL = 'https://worldcat.org/circ/availability/sru/service?';
my @queryParams = ('x-registryId='.$registryID,'query=no%3A'.$oclcnum);
my $authHeader = &makeAuthHeader(\$httpMethod,\$secret,\$key,\$principalID,\$principalIDNS,\@queryParams);;

############## Set the request ###################

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
$ua->protocols_allowed( ['http', 'https'] );

my $requestQuery = '';
while ($#queryParams >= 0) {			## Create the Availability search string. In forward order this time 
	my $firstParam = shift @queryParams;
	if ($#queryParams != -1) { $requestQuery = $requestQuery.$firstParam.'&'; } else { $requestQuery = $requestQuery.$firstParam; }
}
my $requestURL = $apiURL.$requestQuery;

my $response = $ua->get($requestURL, 'Authorization'=>$authHeader,'host' => "worldcat.org", 'user-agent' => "Chrome 41.0.2228.0");		## Availability Request

my $holdingsRecord = $response->content;
	
return ($holdingsRecord);

}

########  Parse Record   #######

sub parseRecord {

my ($holdings,%laptops);
my $holdingsRecord = ${$_[0]};
my $parser = new XML::Parser(ErrorContext => 10,                       #       Create the parser, parse records as a tree
                           Style => "Tree");
my $xso = XML::SimpleObject->new($parser->parse("$holdingsRecord"));   #       Create the object for the parsed records and read

if ( $xso->child('searchRetrieveResponse')->child('records')->child('record')->child('recordData')->child('opacRecord')->child('holdings') ) {
	$holdings = $xso->child('searchRetrieveResponse')->child('records')->child('record')->child('recordData')->child('opacRecord')->child('holdings');
	foreach my $holding ($holdings->child('holding')) {
		my $laptopNumber = $holding->child('copyNumber')->value;
		my $status = $holding->child('circulations')->child('circulation')->child('availableNow')->attribute('value');
		if ($status == 1) {
                	$laptops{"$laptopNumber"} = '00:00';
		} else {
			my $reasonUnavailable = $holding->child('circulations')->child('circulation')->child('reasonUnavailable')->value;
			my $availabilityDate = $holding->child('circulations')->child('circulation')->child('availabilityDate')->value;
	                $laptops{"$laptopNumber"} = &getDueTime(\$availabilityDate);
		}

	}
}

return (%laptops);
}

######## get Due Time  ##############

sub getDueTime {

my ($dueString,$dday,$dmon,$dyear,$dhour,$dmin,$dsec,$dueTime);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst); ##system time in 24 hour clock###
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

$dueString = ${$_[0]};
($dyear,$dmon,$dday,$dhour,$dmin,$dsec) = $dueString =~ /^(\d\d\d\d)-(\d\d)-(\d\d)T([\d]{1,2}):([\d]{1,2})/;

$year = $year + 1900;
$mon++;
if (length $dmin == 1) { $dmin = $dmin + 1; $dmin = $dmin.'0'; }        ## adds  1 to be sure there's a value
if (length $dmon == 1) { $dmon = '0'.$dmon; }
if (length $dday == 1) { $dday = '0'.$dday; }
if (length $mon == 1) { $mon = '0'.$mon; }
if (length $mday == 1) { $mday = '0'.$mday; }

if ($dmin == '60') { $dmin = '00'; $dhour++; }

#if ("$hour:$min" < '09:51') {}					## this was III webpac export stuff, which was am/pm
#elsif (("$hour:$min" > '09:50') && ("$hour:$min" < '18:51') && ($dhour < 10)) {$dhour = $dhour + 12;}
#elsif (("$hour:$min" > '18:50') && ($dhour > 5)) {$dhour = $dhour + 12;}

if ( $dmon.$dday eq $mon.$mday )  {
        $dueTime = "$dhour:$dmin";
} else {
        $dueTime = 'Unavailable';
}

return ($dueTime);
}


###########  sort Laptops ##############

sub sortLaptops {

my %laptops = %{$_[0]};
my (@sorted);

@sorted = sort {  $laptops{$a} cmp $laptops{$b} || $a <=> $b }  keys %laptops;       
return @sorted;

}


######## make Laptop HTML ############


sub makeLaptopHTML {

my (%laptops,$i,$j,$k,$laptopHTML,$numberPerRow,$dueTime);

# my ($key,$a,$b,@sorted);

%laptops = %{$_[0]};
$laptopHTML = '<tr>';
$numberPerRow = 7;
$j = 0;
$k = 0;

my @sortedLaptops = &sortLaptops(\%laptops);
#warn Dumper(@sortedLaptops);

foreach my $laptop (@sortedLaptops) {
	if ($laptops{"$laptop"}) {
		if ($laptops{"$laptop"} =~ /^00:00/) {
			$laptopHTML = $laptopHTML.'<td><img src="/wp-content/uploads/icons/laptop-status-open.png"></br>laptop no.'.$laptop.'<br/>available</td>';
			$j++;
			$k++;
			if ($j % $numberPerRow == 0) {$laptopHTML .= '</tr>'."\n".'<tr>';}
		} elsif ($laptops{"$laptop"} =~ /^Unavailable/) {
                        $laptopHTML = $laptopHTML.'<td><img src="/wp-content/uploads/icons/laptop-status-used.png"></br>laptop no.'.$laptop.'<br/>'.$laptops{"$laptop"}.'</td>';
			$j++;
			if ($j % $numberPerRow == 0) {$laptopHTML .= '</tr>'."\n".'<tr>';}

		} else {
                        $laptopHTML = $laptopHTML.'<td><img src="/wp-content/uploads/icons/laptop-status-used.png"></br>laptop no.'.$laptop.'<br/>due at '.$laptops{"$laptop"}.'</td>';
			$j++;
			if ($j % $numberPerRow == 0) {$laptopHTML .= '</tr>'."\n".'<tr>';}
		}

	}
} # end foreach

$laptopHTML .= '<td colspan="'.($numberPerRow - ($j % $numberPerRow)).'"></tr>';

return ($laptopHTML,$j,$k);

}

######## printHTML      ########

sub printHTML {                                                 #       pass in middle bit

my ($laptopHTML,$displayTime,$numberLaptops,$numberAvailable,$numberCheckedOut);

$laptopHTML = ${$_[0]};
$displayTime = ${$_[1]};
$numberLaptops = ${$_[2]};
$numberAvailable = ${$_[3]};
$numberCheckedOut = $numberLaptops - $numberAvailable;

print <<END_of_Start;
Content-type: text/html

<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
<link href="http://library.aus.edu/Styles/LibMain.css" rel="stylesheet" type="text/css" />
<link href="http://library.aus.edu/Styles/screen.css" rel="stylesheet" media="screen" type="text/css" />
<link href="http://library.aus.edu/Styles/print.css" rel="stylesheet" media="print" type="text/css" />

<title>Laptops Available at $displayTime</title>

</head>
<body>

<h2>Laptops Status at $displayTime</h2>

<ul>
<li>Laptops can be checked out at the  Circulation Desk on the Ground Floor of the Library</li>
</ul>

<h3><strong>$numberAvailable available, $numberCheckedOut checked out.</strong></h3>

<table>$laptopHTML</table>

</body>
</html>
END_of_Start

}


####### Main Execution ############

my ($holdingsRecord,$recordFile,%laptops,$laptopHTML,$displayTime,$numberLaptops,$numberAvailable);

$holdingsRecord = &getItemInfo();			# get the full display export from the WebPAC as a string
#warn Dumper ($holdingsRecord);
%laptops = &parseRecord(\$holdingsRecord);		# parse it and put the item info in a hash
#warn Dumper(%laptops);

($laptopHTML,$numberLaptops,$numberAvailable) = &makeLaptopHTML(\%laptops);	# use the hash to make the html table contents
$displayTime = &makeTime();			# get the current time
&printHTML(\$laptopHTML,\$displayTime,\$numberLaptops,\$numberAvailable);		# output the html

