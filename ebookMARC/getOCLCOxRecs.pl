#!/usr/bin/env perl

##	This script opens the SerSol.mrc MARC file and the MARCPriority.xml files.  It reads the MARCPriority.xml
##	file to determine the next best source of records to enrich the SerSol.mrc records.  If the next source
##	is a downloaded MARC file, it reads through that file for a match on the next SerSol.mrc file.  If it's a
##	Z39.50 source it does a search by ISSN on that source and determines if the record matches.

use strict;
use XML::Parser;							#	use Parser to read the XML file, 
use XML::SimpleObject;							#	Simple Object to handle the parsed priority records
use MARC::Batch; 							#	MARC files and records, as well as field editing operations 
use MARC::Record;							#	are handled by the various MARC:: modules
use MARC::Field; 
use MARC::Charset;							#	for marc8 to utf8 conversions
use ZOOM;								#	for getting records from z servers
use Net::OAI::Harvester;						#	for getting records from OAI-PMH repositories
use Encode;								#	to mess with utf8/unicode things
use Unicode::Normalize;							#	normalize what MARC::Charset does
use Date::Simple ('date','today');					#	Date::Simple is useful for making filenames
use Data::Dumper::Simple;						#	Data::Dumbper is just here for debugging some of the objects
use Business::ISBN;
use LWP::Simple;
use LWP::Simple::Cookies ( autosave => 1,
                            file => "$ENV{'HOME'}/lwp_cookies.dat" );
use CGI qw(:param);


my $dcpref = "http://purl.org/dc/elements/1.1/";			#	Set the namespace URI's for the writer
my $dctermspref = "http://purl.org/dc/terms/";				#	probably don't need for this script
my $xsipref = "http://www.w3.org/2001/XMLSchema-instance";
my $auslibpref = "http://library.aus.edu/auslib/";

##############################					Make a current timestamp				##############################

sub getDateTimeStamp {										# shouldn't need parameters passed, only returned
													# use this variously
my ($dateTimeStamp,$dateStamp008,$sec,$min,$hour,$mday,$mon,$year);

($sec,$min,$hour,$mday,$mon,$year) = localtime();					# make the current timestamp for 005
$year += 1900; $mon += 1; 									# catering to offsets.
$dateTimeStamp = sprintf("%4d%02d%02d%02d%02d%02d",$year,$mon,$mday,$hour,$min,$sec);
$dateStamp008 = sprintf("%2d%02d%02d",$year,$mon,$mday);

return ($dateTimeStamp,$dateStamp008);
}

######## makeTime       #######

sub makeTime {

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$fileTime);

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(${$_[0]});

$fileTime = ($year+1900).'-'.($mon+1).'-'.$mday."  $hour:$min";

return ($fileTime);

}

######## parseURL       ########

sub parseURL {

my ($selectFile,$fileOp);

if ( param("selectFile") ) { $selectFile = param("selectFile"); } else { $selectFile = ''; }
if ( param("fileOp") ) { $fileOp = param("fileOp"); } else { $fileOp = 3; }

return ($fileOp,$selectFile);

}

##############################				Read, parse and sort the MARCPriority file		##############################

sub getPriorities {									# needs ($priorityFile)

my (@prilist,$parser,$xso,$priority,$ptitle,$ppriority,$ptype,$pidentifier,$pfilterTags);

$parser = new XML::Parser(ErrorContext => 2,					#	Create the parser, parse records as a tree
                           Style => "Tree",
                           Namespaces => 1);

$xso = XML::SimpleObject->new($parser->parsefile("$_[0]"));			#	Create the object for the parsed records and read 
										#	the records from the file in through the parser
foreach $priority ($xso->child('metadata')->child('record')) {			#	Iterate through the MARCPriority records

	$ptitle = $priority->child('title')->value;				#	Get the values
	$ppriority = $priority->child('title')->attribute('priority');
	$ptype = $priority->child('type')->value;
	$pidentifier = $priority->child('identifier')->value;
	$pfilterTags = $priority->child('extent')->value;

	$prilist[$ppriority] = [ ($ptitle,$ptype,$pidentifier,$pfilterTags) ];	#	put them in an array of arrays for sorting
	
} # end foreach through priorities

# warn Dumper(@prilist);							#	For looking at the records

return (@prilist);

} # end getPriorities

##############################				combine the two MARC Files into one				##############################

sub combineMARCFiles {

my ($matchedMARCFile,$unmatchedMARCFile,$unmatchedBatch,$unmatchedRecord,$dateTime,$for008Date,);

$matchedMARCFile = ${$_[0]};									#	where to write out the matched/enhanced records
$unmatchedMARCFile = ${$_[1]};								#	source file for brief MARC records

$unmatchedBatch = MARC::Batch->new('USMARC',"$unmatchedMARCFile"); 		#	Open the SerSol.mrc file for matching from
open (OUTPUT, ">> $matchedMARCFile") || die $!;						# 	Open new MARC file for matched/enriched records for append
binmode OUTPUT, ":utf8";

while ( $unmatchedRecord = $unmatchedBatch->next() ) {				# 	Read through match from/SerSol file, get each record 
	print OUTPUT $unmatchedRecord->as_usmarc();					# 	write as matchedRecord to OUTPUT
}

close (OUTPUT);

($dateTime,$for008Date) = &getDateTimeStamp();
rename $matchedMARCFile, './eBookMARC'.$dateTime.'.mrc';					#	rename matched file to timestamped version

}


##############################				rename the two MARC Files 				##############################

sub renameMARCFiles {

my ($matchedMARCFile,$unmatchedMARCFile,$marcDirectory,$dateTime,$for008Date,);

$matchedMARCFile = ${$_[0]};									#	where to write out the matched/enhanced records
$unmatchedMARCFile = ${$_[1]};								#	source file for brief MARC records
$marcDirectory = ${$_[2]};

($dateTime,$for008Date) = &getDateTimeStamp();
rename $matchedMARCFile, "$marcDirectory".'matched_Oxford_eBookMARC'.$dateTime.'.mrc';					#	rename matched file to timestamped version
rename $unmatchedMARCFile, "$marcDirectory".'unmatched_Oxford_eBookMARC'.$dateTime.'.mrc';					#	rename matched file to timestamped version

}



##############################				get Match Points from a source record				##############################

sub getMatchPoints {									# needs (@theseFields)

my ($thisField,@theseFields,@these020as,$this020a,@these856s);

@theseFields = @{$_[0]};

foreach $thisField(@theseFields) {							# 	Read through the fields				

#	if ($thisField->tag() == '001' )  {						# 	SpringerLink uses the print ISBN as an OO1	
#		$this020a = $thisField->data();
#		$this020a =~ s/-//g;
#		push @these020as, $this020a;
#	}

	if ($thisField->tag() == '020' and $thisField->subfield('a')) {			# 	If field is 020 and has subfield a, get the isbn value 
		$this020a = $thisField->subfield('a');
	        my $isbn10_unmatched = Business::ISBN->new($this020a);
	        $isbn10_unmatched = $isbn10_unmatched->as_isbn10;
	        $this020a = $isbn10_unmatched->as_string([]);
#	        print "Matched Source: ",$isbn10_unmatched->as_string([]),"\n";
		$this020a =~ s/-//g;
		push @these020as, $this020a;
	}
	if ($thisField->tag() == '856') {						# 	If field is 245, get the main title value 
		push @these856s, $thisField;		
	}

} # end foreach through unmatched fields


return (\@these856s,\@these020as);

}

##############################				get Match Points from Target a record				##############################

sub getMatchPointsT {									# needs (@theseFields)

### Addtional OCLC data to collect for each record : 
###		040 $b (=eng)								40
###		600, 610, 611, 630, 650, 651 field where 2nd indicator is a 0		30
###		050, 090 $a no hyphen 							20
###		245 $h has 'electronic' |  338 = online resource			15
###		856 $u has 'springer' | doi.org and $3 has Springerlink			10

my ($thisField,@theseFields);
my ($this040a,$this0x0a,$this245h,$this338a,$this856u,$this8563,$this6xxi2,@these6xxi2s, $unmatched20a, $matched20a, @these020as,$this001,$this505);

@theseFields = @{$_[0]}; $unmatched20a = ${$_[1]};

foreach $thisField(@theseFields) {							# 	Read through the fields			###	Modify to get all ISBN's	

        if ($thisField->tag() == '001' )  {                                             #       SpringerLink uses the print ISBN as an OO1      
                $this001 = $thisField->data();
                $this001 =~ s/-//g;
#		print "OCLC no : ",$this001,"\t";
        }

	if ($thisField->tag() == '040' and $thisField->subfield('b')) {			# 	If field is 040 and has subfield b, get the subfield b
		$this040a = $thisField->subfield('b');
	}
	if ($thisField->tag() == '600' || $thisField->tag() == '610' || $thisField->tag() == '611' || $thisField->tag() == '630' || $thisField->tag() == '650' || $thisField->tag() == '651') {	# 	If field is 6xx, get 2nd indicator value
		$this6xxi2 = $thisField->indicator('2');
		if ($this6xxi2 eq '0') {
			push @these6xxi2s, $this6xxi2;
		}
	}

	if ($thisField->tag() == '020') {						# 	If field is 245, get the main title value 
		my ($isbn10_matched,$isbn10_unmatched);
		if ($thisField->subfield('a')) {
			my $this20a = $thisField->subfield('a');

			if ( (Business::ISBN->new($this20a)) and (Business::ISBN->new($unmatched20a) ) ) {

				$isbn10_matched = Business::ISBN->new($this20a);
				$isbn10_matched = $isbn10_matched->as_isbn10;
			        $isbn10_matched = $isbn10_matched->as_string([]);
#				print "ISBN from matched record: ",$isbn10_matched,"\t";
				$isbn10_unmatched = Business::ISBN->new($unmatched20a);
				$isbn10_unmatched = $isbn10_unmatched->as_isbn10;
			        $isbn10_unmatched = $isbn10_unmatched->as_string([]);
#				print "ISBN from source matched record: ",$isbn10_unmatched,"\n";


			} else { 
#				$isbn10_matched = '1';
#				$isbn10_unmatched = '2222222222'; 
	
			}

			if ( $isbn10_matched eq $isbn10_unmatched ) {
				push @these020as,$isbn10_matched;
			}
		}
	}

	if ($thisField->tag() == '050' || $thisField->tag() == '090') {						# 	If field is 245, get the main title value 
		$this0x0a = $thisField->subfield('a');
	}
	if ($thisField->tag() == '245') {						# 	If field is 245, get the main title value 
		$this245h = $thisField->subfield('h');
	}
	if ($thisField->tag() == '338') {						# 	If field is 245, get the main title value 
		$this245h = $thisField->subfield('a');
	}
	$this505 = 0;
	if ($thisField->tag() == '505') {						# 	If field is 245, get the main title value
		$this505++;
	}
	if ($thisField->tag() == '856') {						# 	If field is 245, get the main title value 
		$this856u = $thisField->subfield('u');
		$this8563 = $thisField->subfield('3');
	}

} # end foreach through unmatched fields

# warn Dumper (@these020as);

#print "Size: ",$#these020as,"\n";

if ($#these020as >= 0) {
	$matched20a = $these020as[0];
} elsif ($#these020as < 0) {
	$matched20a = '';
}


#print "matched20a : ",$matched20a,"\n";

# print "$this040a\t$this0x0a\t$this245h\t$this338a\t$this856u\t$this8563\n";
# warn Dumper(@these6xxi2s);
#$this0x0a =~ s/-//g;

return ($matched20a,$this040a,$this0x0a,$this245h,$this338a,$this505,$this856u,$this8563,@these6xxi2s);

}


##############################			perform the Match Logic and return true or false		##############################


sub doMatch {											# needs to change to point assignments

my $thisMatch = 0;
my ($unmatched020a,$matched020a,$this040a,$this0x0a,$this245h,$this338a,$this505,$this856u,$this8563,@these6xxi2s) = (${$_[0]},${$_[1]},${$_[2]},${$_[3]},${$_[4]},${$_[5]},${$_[6]},${$_[7]},${$_[8]},@{$_[9]});

#print "this 0x0 : $this0x0a\n";
if ( $this0x0a !~ /-/ ) {$thisMatch += 20;}
#print "thisMatch : $thisMatch\n";

#print "this245h : $this245h\n";
#print "this338a : $this338a\n";
if ( ($this245h =~ /.*/) || ($this338a eq 'online resource') ) {$thisMatch += 15;}
#print "thisMatch : $thisMatch\n";

if ( $this505 > 0 ) { $thisMatch += ($this505*10); }

if ( ($this856u =~ /oxford/i) || ( ($this856u =~ /doi\.org/i) && ($this8563 =~ /oxford/i) ) ) {$thisMatch += 10;}
#print "thisMatch : $thisMatch\n";



my $subjectEachScore;
if ($#these6xxi2s > 0) { $subjectEachScore = 30 / $#these6xxi2s+1; } else { $subjectEachScore = 30; }
#print "thisMatch : $thisMatch\n";

foreach my $this6xxi2 ( @these6xxi2s) {
	if ($this6xxi2 eq '0') {
		$thisMatch += $subjectEachScore;
	}
}
#print "thisMatch : $thisMatch\n";

#my ($isbn10_matched,$isbn10_unmatched);
#if ($matched020a ) {
#	my $isbn10_matched = Business::ISBN->new($matched020a);
#	$isbn10_matched = $isbn10_matched->as_isbn10;
#	$isbn10_matched = $isbn10_matched->as_string([]);
#	print "Matched: ",$isbn10_matched,"\n";
#}
#if ($unmatched020a) {
#	$isbn10_unmatched = Business::ISBN->new($unmatched020a);
#	$isbn10_unmatched = $isbn10_unmatched->as_isbn10;
#	$isbn10_unmatched = $isbn10_unmatched->as_string([]);
#	print "Unmatched: ",$isbn10_unmatched,"\n";
#}
#print "both : ",$matched020a,"\t",$unmatched020a,"\n";
if ( $matched020a ne $unmatched020a ) {
	$thisMatch = 0;
}

if ( ($this040a =~ /eng/) or ($this040a eq "") ) { } else  { $thisMatch = 0;}
#print "thisMatch : $thisMatch\n";

return ($thisMatch);

}

##############################		recover from an error by rewriting $unmatchedMARCFile		##############################


sub recoverBatch {											# need $unmatchedBatch,,\$priorityList[$i],$unmatchedMARCFile
													# $unmatchedRecord
my ($recoverBatchFile,$unmatchedBatch,$unmatchedMARCFile,$unmatchedRecord);

$recoverBatchFile = './recoverBatch.mrc'; $unmatchedBatch = ${$_[0]}; $unmatchedMARCFile = ${$_[2]}; $unmatchedRecord = ${$_[3]};

open (RECOVOUT, "> $recoverBatchFile") || die $!;							# Open a temp file to store unprocessed records from $unmatchedBatch 
	binmode RECOVOUT, ":utf8";
	if ( $unmatchedRecord ) { print RECOVOUT $unmatchedRecord->as_usmarc(); } 			# don't forget last record read if it's there
	while ( $unmatchedRecord = $unmatchedBatch->next() ) {						# from point in $unmatchedMARC where left off, begin printing records to RECOVOUT
		print RECOVOUT $unmatchedRecord->as_usmarc(); 						#
	} # end while through rest of batch

unlink ("$unmatchedMARCFile"); 										# overwrite SerSol.mrc with SerSolTemp.mrc 
close (RECOVOUT);
rename("$recoverBatchFile","$unmatchedMARCFile") || die "Can't rename $recoverBatchFile to $unmatchedMARCFile : $!";	# (effectively deletes matched unmatchedRecord's from unmatchedBatch)

#print "Recovering.  Sleep for 90 seconds until things are better ... \n";
sleep 90;

#print "Recovered.  Calling Z39.50 matching routine ... \n";						# call the z matching routine on what's left of $unmatchedMARCFile

$unmatchedBatch = MARC::Batch->new('USMARC',"$unmatchedMARCFile"); 					# make a new batch to restart from new beginning of file
searchZTarget ( \$unmatchedBatch, \${$_[1]}, \$unmatchedMARCFile );					# needs $unmatchedBatch,,\$priorityList[$i],$unmatchedMARCFile

}


##############################			Convert a single record from MARC8 to UTF8			##############################

sub marc8toUtf8 {									#	mainly snitched from the good folks at KOHA/koders.com
											#	needs $matchAgainstRecord
my ($record2Convert,$leader,$field,$fieldName,$fieldValue,@subfieldsArray,
	 $indicator1Value,$indicator2Value,$subfield,$subfieldName,$subfieldValue,);

$record2Convert = ${$_[0]};									#	dereference the record

$leader = $record2Convert->leader();								#	change the leader position 9 to unicode
substr($leader,9,1) = 'a';
$record2Convert->leader($leader);

foreach my $field ($record2Convert->fields()) {							#	go through each fields

        if ($field->is_control_field()) {
		$fieldName = $field->tag();							#	this doesn't seem to do anything, presumably
		$fieldValue = $field->data();							#	control field characters are all < 255
	} else {
		my @subfieldsArray;								#	fields with subfields may have characters >255
		$fieldName = $field->tag();							#	get the tag and the indicator values
		$indicator1Value = $field->indicator(1);					#	again, these don't seem to do anything, presumably
		$indicator2Value = $field->indicator(2);					#	MARC tags and indicators characters are all < 255
  
		foreach my $subfield($field->subfields()) {					#	get individual subfield values and put in an array
			$subfieldName = $subfield->[0];
			$subfieldValue = $subfield->[1];
			$subfieldValue = MARC::Charset::marc8_to_utf8($subfieldValue);		#	convert the value to utf8
			$subfieldValue = Unicode::Normalize::NFC($subfieldValue);		#	then try fixing the fix.  added this bit
    	                push @subfieldsArray, [$subfieldName, $subfieldValue];			
               } # end foreach

		foreach my $subfieldRow(@subfieldsArray) {					#	delete the old subfields
			$subfieldName = $subfieldRow->[0];
			$field->delete_subfields($subfieldName);
		} # end foreach

		foreach my $subfieldRow(@subfieldsArray) {					#	add the converted subfields back to the field
			$field->add_subfields(@$subfieldRow);
		} # end foreach
	} # end else

} # end foreach

$record2Convert->encoding('UTF-8');								#	explicitly set new record encoding
return $record2Convert;										#	return converted records

} # end fMARC8ToUTF8

##############################				Normalize a single record				##############################

sub normalizeMatchedRecord {								# needs ($unmatchedRecord, $matchAgainstRecord, $priorityList[$i][3])

my $unmatchedRecord = ${$_[0]};
my $matchAgainstRecord = ${$_[1]};
my @matchAgainstFields = ${$_[1]}->fields();

my ($matchedRecord,@matchedWarnings,$dateTime,$for008Date,@tags2Get,$getTag,@getFields,
	@checkIndicatorFields,$checkIndicatorField,@keepTags,$keepTag,$foundTag);

$matchedRecord = MARC::Record->new();							# 	Make a new record
$matchedRecord->encoding( 'UTF-8' );							####	Set the encoding
@matchedWarnings = $matchedRecord->warnings();

# $matchedRecord->leader('     nam a22      a 4500');					# 	add generic serials leader
$matchedRecord->leader($unmatchedRecord->leader);

($dateTime,$for008Date) = &getDateTimeStamp();						#	get the current date/time stamps

@tags2Get = split /,/, ${$_[2]};							#  	Call list of tags to get from the target ($priorityList[$i][3])
foreach $getTag(@tags2Get) {
	if (length $getTag == 3) {							# 	check tag length for further processing options
		@getFields = $matchAgainstRecord->field($getTag);
		$matchedRecord->append_fields(@getFields);
	} elsif (length $getTag == 5) {								#	Need to elaborate/generalize this, only designed for XXX/0 at the moment
		@checkIndicatorFields = $matchAgainstRecord->field( substr($getTag,0,3) );
		foreach $checkIndicatorField(@checkIndicatorFields) {				# 	Read through the fields
			if ( $checkIndicatorField->indicator(2) == substr( $getTag,4,1 ) ) {	# 	check if indicator 2 matches
				$matchedRecord->append_fields($checkIndicatorField);		#	Append them to the matched record
			} # end if
		} # end foreach
	} # end elsif
} # end foreach

@keepTags = ('000','001','003','005','007','008','020','024','040','072','082','100','110','245','246','250','260','300','490','505','520','599','650','655','700','710','773','776','830','856','912','950','999');						# keep  006, 007, 008, 500, 590 from brief
foreach $keepTag(@keepTags) {								# if not in list of tags to get from target
	$foundTag = 0;
	foreach $getTag(@tags2Get) {
		if ("$getTag" eq "$keepTag") {
			$foundTag = 1;
		}
	}
	if ($foundTag == 0) {$matchedRecord->insert_fields_ordered($unmatchedRecord->field("$keepTag"));}
}

@getFields = $unmatchedRecord->field('902');						# keep the 902's from the brief record for troubleshooting, etc.
$matchedRecord->append_fields(@getFields);

# print $matchedRecord->as_formatted();							# debugging

return ($matchedRecord);

} # end normalizeRecord


##############################	Go through unmatchedBatch and search against a Z39.50 Target		##############################

sub searchZTarget {											#	Pass in (\$unmatchedBatch,\@priorityList[$i],\*OUTPUT,\*OUTTEMP)

my ($unmatchedRecord,

#	$matchAgainst020a,$matchAgainst245a, @matchAgainst020as,
#	$matchAgainstRecord,@matchAgainstFields,$matchAgainstField,$matchedRecord,$leader,


	);

my ($host, $port, $dbname, $zusername, $zpassword) = split /:/,${$_[1]}->[2];							# 	$priorityList[$i][2]

eval {													# wrap Z in eval to check for fatal errors like connection loss

my $zConnection = new ZOOM::Connection("$host", "$port", 
					databaseName => "$dbname",					#	Open the Z39.50 connection using ZOOM
					preferredRecordSyntax => 'usmarc',
		     			user => "$zusername",
		     			password => "$zpassword");

while ( $unmatchedRecord = ${$_[0]}->next() ) {								# 	Read through match from/SerSol file ($priorityList[$i][2]), get each record
	my ($unmatchedField);
	my @unmatchedFields = $unmatchedRecord->fields();							# 	get unmatched 020a, 245a, 902abcd's
	my ($unmatched856s_ref,$unmatched020as_ref) = getMatchPoints(\@unmatchedFields); 				#	 needs @unmatchedFields
	my @unmatched020as = @$unmatched020as_ref;
	my @unmatched856s = @$unmatched856s_ref;

	foreach my $unmatched020a(@unmatched020as) {

### add conversion to isbn10

		if ($unmatched020a =~ /^[\dxX]{10,13}/) {						# make sure valid issn, or result set can be very large and useless
			my $zResultSet = $zConnection->search_pqf("\@attr 1=7 \@attr 2=3 \@attr 3=3 \@attr 4=2 \@attr 5=104 \@attr 6=1 $unmatched020a");		# 	do the z search here

#			print "Result set size : ",$zResultSet->size(),"\n";
			if ( $zResultSet->size() > 0 ) {
				my (%matches, %matchedRecords,$j);
			for $j (0 .. $zResultSet->size()-1) {
				my $zRecord = $zResultSet->record($j); 							# 	Extract MARC record from the result set, and invoke MARC::Record 
				my $matchAgainstRecord = MARC::Record->new_from_usmarc($zRecord->raw()); 
# warn Dumper ($matchAgainstRecord);
				my @matchAgainstFields = $matchAgainstRecord->fields();					# 	get 020a
#				my ($matched20a,$matchAgainst040b,$matchAgainst0x0a,$matchAgainst245h,$matchAgainst338a,$matchAgainst856u,$matchAgainst8563,@matchAgainst6xxi2s);
				my ($matched20a,$matchAgainst040b,$matchAgainst0x0a,$matchAgainst245h,$matchAgainst338a,$this505,$matchAgainst856u,$matchAgainst8563,@matchAgainst6xxi2s) = getMatchPointsT(\@matchAgainstFields,\$unmatched020a); 		#	 needs @unmatchedFields
				if (doMatch(\$unmatched020a,\$matched20a,\$matchAgainst040b,\$matchAgainst0x0a,\$matchAgainst245h,\$matchAgainst338a,\$this505,\$matchAgainst856u,\$matchAgainst8563,\@matchAgainst6xxi2s)) {	# check if anything matches
					$matches{$j} = doMatch (\$unmatched020a,\$matched20a,\$matchAgainst040b,\$matchAgainst0x0a,\$matchAgainst245h,\$matchAgainst338a,\$this505,\$matchAgainst856u,\$matchAgainst8563,\@matchAgainst6xxi2s);
					$matchedRecords{$j} = $matchAgainstRecord;
				} # end if match is not 0 
					else {$matches{$j} = 0;
				} # 
			} # end for through z search results

#				warn Dumper(%matches);

				my $maxValueKey;
				my $maxValue = 0;
				while ((my $key, my $value) = each %matches) {
				  if ($value > $maxValue) {
				    $maxValue = $value;
				    $maxValueKey = $key;
  				  }  # end if value is > maxvalue
				} # end while my key and value

				if ($maxValue > 0) {	
					my @urls = $matchedRecords{$maxValueKey}->field('856');
				    	$matchedRecords{$maxValueKey}->delete_fields(@urls);
					$matchedRecords{$maxValueKey}->insert_fields_ordered(@unmatched856s);
					print OUTPUT $matchedRecords{$maxValueKey}->as_usmarc();					# 	write as matchedRecord to OUTPUT
				} else  {
#					print "Use the Springer Record\n";
					print OUTTEMP $unmatchedRecord->as_usmarc();					# 	write as matchedRecord to OUTPUT
				}

			} else {	# end if $zResultset->size > 0
				print OUTTEMP $unmatchedRecord->as_usmarc();			## if no result set, print the springer record to the temp file
			}

		} # end check of $unmatched020a is an isbn

	} # end foreach through unmatched 020as


} # end while through the $unmatchedMARC file

$zConnection->destroy();

}; # end eval

if ($@) {
#	print "Z39.50 Error ", $@->code(), ": ", $@->message(), "\n";						#	Found Error 10007: Timeout
#	print "Calling recovery routine ... \n";
	&recoverBatch ( \${$_[0]},\${$_[1]},\${$_[2]},\$unmatchedRecord  );					#	Pass (\$unmatchedBatch,\@priorityList[$i],\$unmatchMARCFile)
}

#print "Letting the CPU cool down, wait for 5 minutes.\n"; sleep 300;                                    # let my laptop CPU cool down between files

} # end searchZTarget


######## printProcessingHTML      ########

sub printProcessingHTML {

# get file sizes and dates

my $selectFile = ${$_[0]};

print <<END_of_Start;
Content-type: text/html

<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>

<link href="http://library.aus.edu/Styles/LibMain.css" rel="stylesheet" type="text/css" />
<link href="http://library.aus.edu/Styles/screen.css" rel="stylesheet" media="screen" type="text/css" />
<link href="http://library.aus.edu/Styles/print.css" rel="stylesheet" media="print" type="text/css" />

<title>AUS Library Get OCLC Recs for a Springer File</title>

</head>
<body>

<span class="Breadcrumbs"><a href="http://lib-apps.aus.edu/index.php">Lib-apps Home</a> &gt; Processing File</span>

<p><strong><span class="BigRedTitle">Processing File $selectFile</span> </strong></p>

<p>Wait for form to refresh</p>

</body>
</html>
END_of_Start



}


######## printHTML      ########

sub printHTML {

# get file sizes and dates

my ($dirList,$selectFile,$marcDirectory,$opMessage);

$selectFile = ${$_[0]};
$marcDirectory = ${$_[1]};
$opMessage = ${$_[2]};

my $directory = "$marcDirectory";
    opendir (DIR, $directory) or die $!;
while (my $file = readdir(DIR)) {
        my @fileStuff = stat $directory.$file;
        my $fileTime = &makeTime(\$fileStuff[9]);
        if ( $file =~ /\.mrc/ || $file =~ /\.out/ ) {
                $dirList .= '<input type="radio"  name = "selectFile" value = "'.$file.'"><a href="./tmp/'.$file.'">'.$file.'</a>&nbsp;&nbsp;'."$fileStuff[7]".'&nbsp;&nbsp'."$fileTime".'<br/>';
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

<title>AUS Library Get OCLC Recs for Oxford eBooks</title>

</head>
<body>


<span class="Breadcrumbs"><a href="http://lib-apps.aus.edu/index.php">Lib-apps Home</a> &gt; Get OCLC Recs for Oxford eBooks</span>

<p><strong><span class="BigRedTitle">Get OCLC Records for an Oxford eBook File</span></strong></p>

<p>$opMessage</p>

<form action="FixAcqStuff.pl" method="POST">

<strong>Input Files</strong><br/>
<p>These are the existing MARC Files.  Upload new files from Oxford in data exchange, select them here for deletion or fixing.</p>

<p>$dirList</p>

<strong>Delete or Process</strong>
<select name="fileOp">
        <option value="2" selected="">Process</option>
        <option value="1">Delete</option>
</select>

<input type="submit" name="submit" value="Submit"/>

</form>

</body>
</html>
END_of_Start

} # end top sub

############  deleteFile ############

sub deleteFile {

my ($selectFile,$marcDirectory);

$selectFile = ${$_[0]};
$marcDirectory = ${$_[1]};
$selectFile = $marcDirectory.$selectFile;

if (-e $selectFile) { unlink ("$selectFile"); }

my $opMessage = '<p><b>'.$selectFile.' deleted</b></p>';

return ($opMessage)

}


##################################      process MARC ##############################################

sub processMarc {

my ($unmatchedBatch,$i );

my $selectFile = ${$_[0]}; my $marcDirectory = ${$_[1]}; my @priorityList = @{$_[2]};

my $unmatchedMARCFile = "$marcDirectory"."$selectFile";                                                                 #       source file for brief MARC records

my $matchedMARCFile = "$marcDirectory".'matched.mrc';                                                                   #       where to write out the matched/enhanced records
my $unmatchedTempMARCFile = "$marcDirectory".'unmatchedTemp.mrc';                                                               #       where to stash records that don't match at the current priority,

## \$selectFile,\$marcDirectory @priorityList $matchedMARCFile, $unmatchedMARCFile $unmatchedTempMARCFile


for ($i=1;$i<2;$i++) {

#       if (defined $priorityList[$i]) { print "\n".$i.' '."@{@priorityList[$i]}[0..2]"; print "\n";}           # debugging, script progress

        $unmatchedBatch = MARC::Batch->new('USMARC',"$unmatchedMARCFile");                              #       Open the SerSol.mrc file for matching from
        open (OUTPUT, ">> $matchedMARCFile") || die $!;                                                 #       Open new MARC file for matched/enriched records for append
        binmode OUTPUT, ":utf8";
        open (OUTTEMP, "> $unmatchedTempMARCFile") || die $!;                                           #       Open a temp file to store unmatched records unmatchable 
        binmode OUTTEMP, ":utf8";

        if ("$priorityList[$i][1]" eq 'Z39.50 Server') {                                                #       end if local MARC file, check for Z39.50
                searchZTarget(\$unmatchedBatch,\$priorityList[$i],\$unmatchedMARCFile,\*OUTPUT,\*OUTTEMP);
        }

        close (OUTTEMP);
        unlink ("$unmatchedMARCFile");                                                                  # overwrite SerSol.mrc with SerSolTemp.mrc 
        rename("$unmatchedTempMARCFile","$unmatchedMARCFile") || die "Can't rename $unmatchedTempMARCFile to $unmatchedMARCFile : $!";  # (effectively deletes matched unmatchedRecord's from unmatchedBatch)

        close (OUTPUT);                                                                                 # Close matched.mrc

} # end for through the priority list

renameMARCFiles(\$matchedMARCFile,\$unmatchedMARCFile,\$marcDirectory);                                         #               combine the two MARC files before ending

# combineMARCFiles(\$matchedMARCFile,\$unmatchedMARCFile);                                              #               combine the two MARC files before ending

my $opMessage = '<p><b>'.$selectFile.' processed</b></p>';

return ($opMessage);

}  ## end sub



##############################					Main script execution					##############################

my ($priorityFile,$matchedMARCFile,$unmatchedMARCFile,$unmatchedTempMARCFile,@priorityList,$i,$unmatchedBatch,$lastSplit,$k);
my ( $fileOp,$selectFile,$marcDirectory,$opMessage );

$priorityFile = './MARCPriorityOCLC.xml';                                                                       #       set the file names : configuration file

$opMessage = '';
$marcDirectory = '/var/www/html/ebookMARC/tmp/';
#$fileOp = '2';

@priorityList = getPriorities($priorityFile);                                                           #       get the priority records for MARC Sources

if (-e $matchedMARCFile) { unlink ("$matchedMARCFile"); }                                               #       Nuke the previous run's $matchedMARCFile

($fileOp,$selectFile) = &parseURL();

if ( $fileOp != 1 && $fileOp != 2 ) {
        &printHTML(\$selectFile,\$marcDirectory,\$opMessage);


} elsif ( $fileOp == 2 && $selectFile ne '' ) {

        $opMessage = &processMarc(\$selectFile,\$marcDirectory,\@priorityList);
#$opMessage = '<p>Hi</p>';
#print "$opMessage\t$marcDirectory\t$selectFile\n";
        &printHTML(\$selectFile,\$marcDirectory,\$opMessage);

} elsif ( $fileOp == 1 && $selectFile ne '' ) {
        $opMessage = &deleteFile(\$selectFile,\$marcDirectory);
#print "$opMessage\t$marcDirectory\t$selectFile\n";
        &printHTML(\$selectFile,\$marcDirectory,\$opMessage);


} else {
        &printHTML(\$selectFile,\$marcDirectory,\$opMessage);
}


##############################												##############################

