#!/usr/bin/perl

use strict;

use Date::Simple ('date','today');                                      #       Date::Simple is useful for making filenames
use Unicode::Normalize;
use Encode;                                                             #       to mess with utf8/unicode things

use MARC::Batch; 							#	MARC files and records, as well as field editing operations 
use MARC::Record;							#	are handled by the various MARC:: modules
use MARC::Field; 
use MARC::Charset;							#	for marc8 to utf8 conversions

use Data::Dumper::Simple;                                               #       Data::Dumper is just here for debugging some of the objects


########################		 subroutine to trimSpace ################################

sub trimString {

my $trimString = ${$_[0]};

while ( $trimString =~ /^ /) {
	$trimString =~ s/^ //;
}
while ( $trimString =~ /^"/) {
	$trimString =~ s/^"//;
}
while ( $trimString =~ /[ ]$/) {
	$trimString =~ s/ $//;
}

while ( $trimString =~ /"$/ ) {
	$trimString =~ s/"$//;
}
while ( $trimString =~ /\.$/) {
	$trimString =~ s/\.$//;
}
while ( $trimString =~ /:$/) {
	$trimString =~ s/:$//;
}
while ( $trimString =~ /=$/) {
	$trimString =~ s/=$//;
}
while ( $trimString =~ /\/$/) {
	$trimString =~ s/\/$//;
}
return ($trimString);
}


##############################				get Match Points from Target a record		##############################


sub assembleHoldings {

my %captions = %{$_[0]};
my %holdings = %{$_[1]};
my %titles = %{$_[2]};
#warn Dumper (%holdings);
#warn Dumper (%titles);
#warn Dumper (%captions);
my @allHoldings;

open (OUT, '> ./KBARTFile_loadable.txt') || die $!;						# 	Open new MARC file for matched from the Z source
binmode OUT, ":utf8";
print OUT "publication_title\tcoverage_depth\toclc_number\tdate_first_issue_online\tnum_first_vol_online\tnum_first_issue_online\tdate_last_issue\tnum_last_vol_online\tnum_last_issue_online\tACTION\tNote\n";

open (CHECK, '> ./KBARTFile_check.txt') || die $!;						# 	Open new MARC file for matched from the Z source
binmode CHECK, ":utf8";

foreach my $tkey (keys %titles) {						## iterate the title info hash keys


	my %theseHoldings = %{$holdings{$tkey}};				## get the holdings and captions hashes for the title
	my %theseCaptions = %{$captions{$tkey}};

#warn Dumper (%theseCaptions);

	my %this_title_holdings;

	foreach my $hkey (keys %theseHoldings) {				## iterate the set of holdings for the title

		my $linkSeq = $theseHoldings{$hkey}->{'8'};			## get the link and sequence numbers for each holding
		my ($link,$sequence) = split /\./, $linkSeq;
		my $chron1 = $theseHoldings{$hkey}->{'i'};			## get the first and 2nd chronology elements for the holdings
		my $chron2 = $theseHoldings{$hkey}->{'j'};
		my ($display_chron2,$sort_chron2);
		if ( $chron2 eq '21')  { $display_chron2 = ' Spring'; $sort_chron2 = '03'; }		# fix up the seasons and dates in chronology element 2
		if ( $chron2 eq '22')  { $display_chron2 = ' Summer'; $sort_chron2 = '06'; }		# and make them suitable for display
		if ( $chron2 eq '23')  { $display_chron2 = ' Autumn'; $sort_chron2 = '09'; }
		if ( $chron2 eq '24')  { $display_chron2 = ' Winter'; $sort_chron2 = '12'; }
		if ( $chron2 eq '01')  { $display_chron2 = ' Jan'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '02')  { $display_chron2 = ' Feb'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '03')  { $display_chron2 = ' Mar'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '04')  { $display_chron2 = ' Apr'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '05')  { $display_chron2 = ' May'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '06')  { $display_chron2 = ' Jun'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '07')  { $display_chron2 = ' Jul'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '08')  { $display_chron2 = ' Aug'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '09')  { $display_chron2 = ' Sep'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '10')  { $display_chron2 = ' Oct'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '11')  { $display_chron2 = ' Nov'; $sort_chron2 = $chron2; }
		if ( $chron2 eq '12')  { $display_chron2 = ' Dec'; $sort_chron2 = $chron2; }

		my $chron3 = $theseHoldings{$hkey}->{'k'};						## get the 3rd chronology element for the holding
		my $enum1 = $theseHoldings{$hkey}->{'a'};						## get the 3 enumeration elements for the holding
		my $enum2 = $theseHoldings{$hkey}->{'b'};
		my $enum3 = $theseHoldings{$hkey}->{'c'};

		if ( $chron1 eq '*' ) { $chron1 = $enum1; }						## dates have been entered as the enumeration

		my $enumcap1 = $theseCaptions{$link}->{'a'};						## get the 3 corresponding captions for the 3 enumeration elements from the captions hash
		my $enumcap2 = $theseCaptions{$link}->{'b'};
		my $enumcap3 = $theseCaptions{$link}->{'c'};
#		print "$link\t$sequence\t$chron1$chron2$chron3\t$enumcap1$enum1:$enumcap2$enum2\n";
#		print "$tkey\t$titles{$tkey}\t$chron1$chron2$chron3\t$enumcap1$enum1:$enumcap2$enum2\n";

## TODONE account for multiple month/day/week issues - 06/07, etc. to keep it sortable/subractable - 
##	make a kkey for each ?  separator chars : are / and - and ??  : add same record for each
		my ($kkey,$chron2a,$chron2b,$chron3a,$chron3b);

		if ( $chron2 =~ /(-)/ || $chron2 =~ /(\/)/ ) {						## account for multiple month/day/week issues
			($chron2a,$chron2b) = split /$1/,$chron2;
		}
		if ( $chron3 =~ /-/ || $chron3 =~ /\// ) {
			($chron3a,$chron3b) = split /$1/,$chron3;
		}

## TODO maybe do the above for enumeration as well

		if ( $enum2 =~ /(-)/ || $enum2 =~ /(\/)/ ) {						## account for multiple month/day/week issues
			($enum2a,$enum2b) = split /$1/,$enum2;
		}
		if ( $enum1 =~ /-/ || $enum1 =~ /\// ) {
			($enum1a,$enum1b) = split /$1/,$enum1;
		}

		my ($full_enum1,$full_enum2);								## make the ful enumeration, it's the same for all cases
		if ( $enum1 ne '' ) { $full_enum1 = $enumcap1.$enum1; } else { $full_enum1 = ''; }
		if ( $enum2 ne '' ) { $full_enum2 = $enumcap2.$enum2; } else { $full_enum2 = ''; }
		my $display_enum = $enumcap1.$enum1.':'.$enumcap2.$enum2;

		my $ekey_enum1 = $enum1;
		my $ekey_enum2 = $enum2;
		if ( $length $enum1 <4 ) { $e = 4 - $length $enum1; for ($f=1:$f++;$f<=$e) { $ekey_enum1 = '0'.$ekey_$enum1; }		## frontpad the $ekey $eun1 with 0's
		if ( $length $enum2 <4 ) { $e = 4 - $length $enum2; for ($f=1:$f++;$f<=$e) { $ekey_enum2 = '0'.$ekey_$enum2; }		## frontpad the $ekey $eun2 with 0's
		$ekey = $ekey_enum1.$ekey_enum2

		$this_title_holdings{$ekey} = {'year' = $chron1; 'display_date'=>$display_date, 'display_enum'=>$display_enum, 'full_enum1'=>$full_enum1, 'full_enum2'=>$full_enum2 };	# add complete enum and chrons to a hash for this title


##		if ($chron2a ne '' ) {
##			if ($chron2a ne '') { $kkey = $chron1.$chron2a; } else { $kkey = $chron1; }		## create $kkey from the chronology elements, basically  a sortable date
##			if ($chron3 ne '') { $kkey = $kkey.$chron3; } else { $kkey = $kkey; }
##			my $display_date = $chron1.$display_chron2.' '.$chron3;					## make displayable date and enumerations
##			$this_title_holdings{$kkey} = {'display_date'=>$display_date, 'display_enum'=>$display_enum, 'full_enum1'=>$full_enum1, 'full_enum2'=>$full_enum2 };	# add complete enum and chrons to a hash for this title
##			if ($chron2b ne '') { $kkey = $chron1.$chron2b; } else { $kkey = $chron1; }		## create $kkey from the chronology elements, basically  a sortable date
##			if ($chron3 ne '') { $kkey = $kkey.$chron3; } else { $kkey = $kkey; }
##			my $display_date = $chron1.$display_chron2.' '.$chron3b;					## make displayable date and enumerations
##			$this_title_holdings{$kkey} = {'display_date'=>$display_date, 'display_enum'=>$display_enum, 'full_enum1'=>$full_enum1, 'full_enum2'=>$full_enum2 };	# add complete enum and chrons to a hash for this title
##
##		} elsif ( $chron3a ne '' ) {							## check for chron2a/b or $chron3a/b, add 2 kkey entries if found
## do some stuff here
##			if ($chron2 ne '') { $kkey = $chron1.$chron2; } else { $kkey = $chron1; }		## create $kkey from the chronology elements, basically  a sortable date
##			if ($chron3a ne '') { $kkey = $kkey.$chron3a; } else { $kkey = $kkey; }
##			my $display_date = $chron1.$display_chron2.' '.$chron3a;					## make displayable date and enumerations
##			$this_title_holdings{$kkey} = {'display_date'=>$display_date, 'display_enum'=>$display_enum, 'full_enum1'=>$full_enum1, 'full_enum2'=>$full_enum2 };	# add complete enum and chrons to a hash for this title
##			if ($chron2 ne '') { $kkey = $chron1.$chron2; } else { $kkey = $chron1; }		## create $kkey from the chronology elements, basically  a sortable date
##			if ($chron3b ne '') { $kkey = $kkey.$chron3b; } else { $kkey = $kkey; }
##			my $display_date = $chron1.$display_chron2.' '.$chron3b;					## make displayable date and enumerations
##			$this_title_holdings{$kkey} = {'display_date'=>$display_date, 'display_enum'=>$display_enum, 'full_enum1'=>$full_enum1, 'full_enum2'=>$full_enum2 };	# add complete enum and chrons to a hash for this title
##		} else {
##
##			if ($chron2 ne '') { $kkey = $chron1.$chron2; } else { $kkey = $chron1; }		## create $kkey from the chronology elements, basically  a sortable date
##			if ($chron3 ne '') { $kkey = $kkey.$chron3; } else { $kkey = $kkey; }
##			my $display_date = $chron1.$display_chron2.' '.$chron3;					## make displayable date and enumerations
##			$this_title_holdings{$kkey} = {'display_date'=>$display_date, 'display_enum'=>$display_enum, 'full_enum1'=>$full_enum1, 'full_enum2'=>$full_enum2 };	# add complete enum and chrons to a hash for this title
##		} ## end check for chron2a, 3a

	}  ## end foreach through keys for this title

#		warn Dumper(%this_title_holdings);
		my %this_sorted_title_holdings;
		my @sorted_holdings_keys = (sort keys %this_title_holdings);				## sort the complete enum and chrons by $kkey (sortable date)

##TODO write something here to iterate the sorted keys and check for gaps in the holdings.  Split any such titles at the gap and print individual records for each segment  : use length of skey + subtract current from previous > ?? to determine

## TODO logic here :  If gap detected, keep previous first sorted key, set last key to prev_skey, print out KBART record, set new first_key to skey
##   if no gap, keep iterating.  When end reached, last key is last key, print final or only holding

		my $first_sorted_key = $sorted_holdings_keys[0];					## get the firt and last sorted $kkeys for the title
		my $i;
		for ($i=1;$i<=$#sorted_holdings_keys;$i++) {
			my $skey = $sorted_holdings_keys[$i];
			my $prev_skey = $sorted_holdings_keys[$i-1];		## check if $i -1 is < 0
			if ( (length $skey == 4 && $skey-$prev_skey > 1) || (length $skey == 6 && $skey-$prev_skey > 1) || (length $skey == 8 && $skey-$prev_skey > 35) )  {

##TODO this logic is wrong, prints out too many lines, see spreadsheet
				my $last_sorted_key = $prev_skey;
				print OUT "$titles{$tkey}\tprint\t$tkey\t$first_sorted_key\t$this_title_holdings{$first_sorted_key}->{'full_enum1'}\t$this_title_holdings{$first_sorted_key}->{'full_enum2'}\t$last_sorted_key\t$this_title_holdings{$last_sorted_key}->{'full_enum1'}\t$this_title_holdings{$last_sorted_key}->{'full_enum2'}\traw\t$this_title_holdings{$first_sorted_key}->{'display_date'}$this_title_holdings{$first_sorted_key}->{'display_enum'}-$this_title_holdings{$last_sorted_key}->{'display_date'} $this_title_holdings{$last_sorted_key}->{'display_enum'}\n";
				$first_sorted_key = $skey;
#			} else {
## TODO this here ?  or after loop ?
#				my $last_sorted_key = $sorted_holdings_keys[$#sorted_holdings_keys];			## then print the complete holding for the title to the KBARTfile
#				next;
			} # end if check for gap

		} # end for through sorted keys

		my $last_sorted_key = $sorted_holdings_keys[$#sorted_holdings_keys];			## then print the complete holding for the title to the KBARTfile
		print OUT "$titles{$tkey}\tprint\t$tkey\t$first_sorted_key\t$this_title_holdings{$first_sorted_key}->{'full_enum1'}\t$this_title_holdings{$first_sorted_key}->{'full_enum2'}\t$last_sorted_key\t$this_title_holdings{$last_sorted_key}->{'full_enum1'}\t$this_title_holdings{$last_sorted_key}->{'full_enum2'}\traw\t$this_title_holdings{$first_sorted_key}->{'display_date'}$this_title_holdings{$first_sorted_key}->{'display_enum'}-$this_title_holdings{$last_sorted_key}->{'display_date'} $this_title_holdings{$last_sorted_key}->{'display_enum'}\n";

		print CHECK "$tkey\t$titles{$tkey}\n";
		foreach my $skey (sort keys %this_title_holdings) {					## a debugging thing to check the data structure on screen
			$this_sorted_title_holdings{$skey} = %{$this_title_holdings{$skey}};
			print CHECK "$skey\t$this_title_holdings{$skey}->{'display_date'}\t$this_title_holdings{$skey}->{'display_enum'}\n";
		}
#		warn Dumper(%this_sorted_title_holdings);

} # end foreach

return (\@allHoldings);

}


##############################				get Match Points from Target a record				##############################

sub getBibFields {									# needs (@theseFields)

my ($this001,$this003,$this004,$this035a,$this245a,%these853s,%these863s);

my $BorM = '';

my @theseFields = @{$_[0]};

foreach my $thisField(@theseFields) {							# 	Read through the fields			###	Modify to get all ISBN's	

        if ($thisField->tag() == '001' )  {                                             #       SpringerLink uses the print ISBN as an OO1      
                $this001 = $thisField->data();
        }

        if ($thisField->tag() == '003' )  {                                             #       SpringerLink uses the print ISBN as an OO1      
                $$this003 = $thisField->data();
        }

        if ($thisField->tag() == '004' )  {                                             #       SpringerLink uses the print ISBN as an OO1      
		$BorM = 'M';
                $this004 = $thisField->data();
        }

	if ($thisField->tag() == '035' and $thisField->subfield('a')) {			# 	If field is 040 and has subfield b, get the subfield b
		$BorM = 'B';
		$this035a = $thisField->subfield('a');
	}

	if ($thisField->tag() == '245') {						# 	If field is 245, get the main title value 
		$BorM = 'B';
		$this245a = $thisField->subfield('a');
		$this245a = &trimString(\$this245a);
	}

	if ($thisField->tag() == '852') {						# 	If field is 245, get the main title value 
		$BorM = 'M';
	}
} # end foreach through unmatched fields


if ( $BorM eq 'M' ) {

	foreach my $thisField(@theseFields) {							# 	Read through the fields			###	Modify to get all ISBN's	

		if ($thisField->tag() == '853' ) {	# 	If field is 948, get $h
			my (%hash853);
			my @theseSubfields = $thisField->subfields();
			foreach my $thisSubfield (@theseSubfields) {
				my ($code,$data) = (@$thisSubfield);
				if ($code =~ /[8abcdefijkl]/ and $data ne '') {
					$hash853{$code} = $data;	
				}
			}
#warn Dumper (%hash853);
			$these853s{$hash853{'8'}} = {%hash853};
		}

		if ($thisField->tag() == '863' ) {	# 	If field is 948, get $h
			my (%hash863);
			my @theseSubfields = $thisField->subfields();
			foreach my $thisSubfield (@theseSubfields) {
				my ($code,$data) = (@$thisSubfield);
				if ($code =~ /[8abcdefijkl]/ and $data ne '') {
					$hash863{$code} = $data;	
				}
			}
#warn Dumper (%hash863);
			$these863s{$hash863{'8'}} = {%hash863};
		}

	} # end foreach through unmatched fields

} # end if B or M

#print "$BorM\n";

#warn Dumper (%these853s);
#warn Dumper (%these863s);

return ($BorM,$this001,$this004,$this245a,\%these853s,\%these863s);

}


###########################################             Main Execution          #######################################

my (%titles,%captions,%holdings);

my $queryMARCFile = $ARGV[0];								#	source file for MARC records from the periodicals query
$queryMARCFile =~ s/\.mrc$//;							       	#       get the filename stem
my $queryKBARTFile = $queryMARCFile.'.txt';						#	make an output KBART file name
$queryMARCFile = $queryMARCFile.'.mrc';							#	make the original filename

if (-e $queryKBARTFile) { unlink ("$queryKBARTFile"); } 				#	Nuke the previous run's KBART Fiel

my $queryBatch = MARC::Batch->new('USMARC',"$queryMARCFile"); 				#	Open the source .mrc file to read the record
open (OUTPUT, ">> $queryKBARTFile") || die $!;						# 	Open new KBART file 
binmode OUTPUT, ":utf8";

while ( my $queryRecord = $queryBatch->next() ) {					# 	get the next record
	my @queryFields = $queryRecord->fields();					# 	get the record fields
	my ($BorM,$bib001,$mfhd004,$bib245a,$mfhd853_ref,$mfhd863_ref) = &getBibFields(\@queryFields);		#	Get the needed Bib fields from the MARC record
	if ( $BorM eq 'M') {								#	if the record is a MFHD, make 853 and 863 hashes for the record
		my %mfhd853s = %{$mfhd853_ref}; 
#print "In main execution\n";
#warn Dumper (%mfhd853s);
		if (defined $captions{$mfhd004}) {
			$captions{$mfhd004} = (%{$captions{$mfhd004}},{%mfhd853s});	## 	if there's an entry for the title in the captions hash, add the current 853 hash to the array
		} else {
			$captions{$mfhd004} = {%mfhd853s};				## 	if there's no entry for the title, add the 853 hash to create it
		}
#warn Dumper ($captions{$mfhd004});
		my %mfhd863s = %{$mfhd863_ref}; 					##	if there's an entry for the title in the holdings hash, add the current 863 hash to the array
#warn Dumper (%mfhd863s);
				$holdings{$mfhd004} = {%mfhd863s};			## 	if there's no entry for the title, add the 856 hash to create it
#warn Dumper ($holdings{$mfhd004});
	} elsif ($BorM eq 'B' ) {							##	if record is a bib, add info to the titles hash
		$titles{$bib001} = $bib245a;
	}
}

my @allHoldings = &assembleHoldings(\%captions,\%holdings,\%titles);			##	run a routine to create one big datastructure of all the holdings

#warn Dumper (%captions);
#warn Dumper (%holdings);
#warn Dumper (%titles);

close (OUTPUT);
