#!/usr/bin/perl

## 	This script fixes bad 050s in a MARC file, looking for missing Cutters and creating them from a table
##	
##	
##	

use strict;
use MARC::Batch; 							#	MARC files and records, as well as field editing operations 
use MARC::Record;							#	are handled by the various MARC:: modules
use MARC::Field; 
use MARC::Charset;							#	for marc8 to utf8 conversions
# use Encode;								#	to mess with utf8/unicode things
# use Unicode::Normalize;							#	normalize what MARC::Charset does
use Data::Dumper::Simple;						#	Data::Dumbper is just here for debugging some of the objects
use LWP::Simple;
use LWP::Simple::Cookies ( autosave => 1,
                            file => "$ENV{'HOME'}/lwp_cookies.dat" );
use CGI qw(:param);


##############################                                  Make a current timestamp                                ##############################

sub getDateTimeStamp {                                                                          # shouldn't need parameters passed, only returned
                                                                                                        # use this variously
my ($dateTimeStamp,$dateStamp008,$sec,$min,$hour,$mday,$mon,$year);

($sec,$min,$hour,$mday,$mon,$year) = localtime();                                       # make the current timestamp for 005
$year += 1900; $mon += 1;                                                                       # catering to offsets.
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


##############################					pick out a main entry					##############################

sub pick_main_entry {

# warn Dumper(@_);

	my ($main_entry);
	my @t245s = @{$_[0]};
	my @t1xxs = @{$_[1]};
	my $count1xx = ${$_[2]};

	if ( $count1xx > 0 ) {
		if ( $count1xx == 1) {
			$main_entry = $t1xxs[1];
#			print "1xx main entry : $main_entry\n";

		} elsif ( $count1xx > 1 ) {
			$main_entry = substr $t245s[0], $t245s[0]++;
#			print "245 main entry case 1 : $main_entry\n";
		}

	} else {
		my $offset = 0;
#		print "from title array :".($t245s[0])." \n";
		if ( $t245s[0]) { my $offset = $t245s[0]++; } 
		my $btitle = $t245s[1];
		$main_entry = substr  $btitle, $offset;
#		print "245 main entry case 2 : $main_entry\n";

	}

return ($main_entry);

} ## end sub

##############################					Make a cutter number from the main entry		##############################

sub make_a_cutter {


	my ($first_char, $second_char, $third_char, $first_number, $second_number, $cutter);

	my $main_entry = ${$_[0]};


	$main_entry =~ s/^([\w-]*)[', ]*.*/$1/g;
#	print "Half Normalized Main Entry : $main_entry\n";
	$main_entry =~ s/[\W]//g;

#	print "Normalized Main Entry : $main_entry\n";

	## Initial Valid letters
	my %cutterValidityTable = ( a => '1', b => '1', c => '1', d => '1', e => '1', f => '1', g => '1', h => '1', i => '1', j => '1', k => '1',
		l => '1', m => '1', n => '1', o => '1', p => '1', r => '1', s => '1', t => '1', u => '1', v => '1', w => '1', x => '1', y => '1',
		 z => '1' );
	## inValid letters to follow initial 'Q'
	my %cutterQinValidityTable = ( t => '1', v => '1', w => '1', x => '1', y => '1', z => '1' );

	## Numbers for 2nd character
	my %cutterTable = (
		a => { a => 2, b => 2, c => 2, d => 3, e => 3, f => 3, g => 3, h => 3, i => 3, j => 3, k => 3, l => 4, m => 4, n => 5, o => 5,
			 p => 6, q => 6, r => 7, s => 8,  t => 8, u => 9, v => 9, w => 9, x => 9, y => 9, z => 9 },
		e => { a => 2, b => 2, c => 2, d => 3, e => 3, f => 3, g => 3, h => 3, i => 3, j => 3, k => 3, l => 4, m => 4, n => 5, o => 5,
			 p => 6, q => 6, r => 7, s => 8,  t => 8, u => 9, v => 9, w => 9, x => 9, y => 9, z => 9 },
		i => { a => 2, b => 2, c => 2, d => 3, e => 3, f => 3, g => 3, h => 3, i => 3, j => 3, k => 3, l => 4, m => 4, n => 5, o => 5,
			 p => 6, q => 6, r => 7, s => 8,  t => 8, u => 9, v => 9, w => 9, x => 9, y => 9, z => 9 },
		o => { a => 2, b => 2, c => 2, d => 3, e => 3, f => 3, g => 3, h => 3, i => 3, j => 3, k => 3, l => 4, m => 4, n => 5, o => 5,
			 p => 6, q => 6, r => 7, s => 8,  t => 8, u => 9, v => 9, w => 9, x => 9, y => 9, z => 9 },
		u => { a => 2, b => 2, c => 2, d => 3, e => 3, f => 3, g => 3, h => 3, i => 3, j => 3, k => 3, l => 4, m => 4, n => 5, o => 5,
			 p => 6, q => 6, r => 7, s => 8,  t => 8, u => 9, v => 9, w => 9, x => 9, y => 9, z => 9 },
		s => { a => 2, b => 2, c => 3, ch => 3, d => 3, e => 4, f => 4, g => 4, h => 5, i => 5, j => 5, k => 5, l => 5, m => 6, n => 6,
			 o => 6, p => 6, q => 6, r => 7, s => 6, t => 7, u => 8, v => 8, w => 9, x => 9, y => 9, z => 9 },
		qu => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 8, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		qa => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qb => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qc => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qd => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qe => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qf => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qg => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qh => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qi => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qj => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qk => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		ql => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qm => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qn => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qo => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qp => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qq => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qr => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qs => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		qt => { a => 2, b => 2, c => 2, d => 2, e => 2, f => 2, g => 2, h => 2, i => 2, j => 2, k => 2, l => 2, m => 2, n => 2, o => 2,
			 p => 2, q => 2, r => 2, s => 2 },
		b => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		c => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		d => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		f => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		g => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		h => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		j => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		k => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		l => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		m => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		n => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		p => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		r => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		t => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		v => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		w => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		x => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		y => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 },
		z => { a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 5, n => 5, o => 6,
			 p => 6, q => 6, r => 7, s => 7, t => 7, u => 8, v => 8, w => 8, x => 8, y => 9, z => 9 }
	);

	## Numbers for 2nd character
	my %cutterExpansionTable = (
		a => 3, b => 3, c => 3, d => 3, e => 4, f => 4, g => 4, h => 4, i => 5, j => 5, k => 5, l => 5, m => 6, n => 6, o => 6,
			 p => 7, q => 7, r => 7, s => 7, t => 8, u => 8, v => 8, w => 9, x => 9, y => 9, z => 9 
	);

	if ( $cutterValidityTable{ lc substr $main_entry, 0, 1 } eq '1' ) {
#		print "Found in validity table\n";
		$first_char =  lc substr $main_entry, 0, 1 ;
		$second_char = lc substr $main_entry, 1, 1 ;
		$third_char = lc substr $main_entry, 2, 1 ;
		if ( $first_char eq 's' and $second_char eq 'c' and $third_char eq 'h' ) {
			$second_char = lc $second_char.$third_char;
			$third_char = lc substr $main_entry, 3, 1 ;
			$first_number = lc $cutterTable{$first_char}{$second_char};
			$second_number = lc $cutterExpansionTable{$third_char};
		} else {
			$first_number = lc $cutterTable{$first_char}{$second_char};
			$second_number = lc $cutterExpansionTable{$third_char};
		}
#		print "$first_char\t$second_char\t$third_char\t$first_number\t$second_number\n";

	} elsif (  ( lc substr $main_entry, 0, 1 )  eq 'q' ) {

			$first_char = lc substr $main_entry, 0, 2 ;

		if ( (lc substr $main_entry, 1, 1) eq 'u' ) {
			$second_char = lc substr $main_entry, 2, 1 ;
			$third_char = lc substr $main_entry, 3, 1 ;
			$first_number = lc $cutterTable{$first_char}{$second_char};
			$second_number = lc $cutterExpansionTable{$third_char};
#			print "$first_char\t$second_char\t$third_char\t$first_number\t$second_number\n";
			$first_char = lc substr $main_entry, 0, 1 ;
		} elsif ( $cutterQinValidityTable{ ( lc substr $main_entry, 1, 1 ) } ne '1' ) {
#			print "Not found in Q invalidity table\n";
			$second_char = lc substr $main_entry, 1, 1 ;
			$third_char = lc substr $main_entry, 2, 1 ;
			$first_number = lc $cutterTable{$first_char}{$second_char};
			$second_number = lc $cutterExpansionTable{$third_char};
#			print "$first_char\t$second_char\t$third_char\t$first_number\t$second_number\n";
			$first_char = lc substr $main_entry, 0, 1 ;
		} else {
#			print "Found in Q invalidity table\n";
			$cutter = 'Cannot make cutter';
		}


	} else {

#		print "Not Found in either validity table\n";
#		print "First character: ",'#',lc substr $main_entry, 0, 1 ;
#		print "#\tSecond character: ",lc substr $main_entry, 1, 1;
#		print "\tInvalidity value: ", $cutterQinValidityTable{ lc substr $main_entry, 1, 1 };
#		print  "\n";

## some kind of error, 
		$cutter = 'Cannot make cutter';

	}

	$first_char = uc $first_char;
	if ( $cutter ne 'Cannot make cutter' ) { $cutter = $first_char.$first_number.$second_number; }

return ($cutter);

}

##############################					Reassemble the call number				##############################

sub reassemble_LC_callno {


	my ($ind_2_245, $sub_a_245, $sub_a_050, $sub_b_050, $sub_a_090, $sub_b_050);


}

##############################					Get the date						##############################

sub get201x_date {



}

##############################					pick out a main entry					##############################

sub processMarc {

my ($MARCFile,$no050MARCFile,$has050MARCFile,$i,$fileBatch,$nextRecord,@nextFields,$has050,$nextField);

my $selectFile = ${$_[0]}; my $marcDirectory = ${$_[1]}; 

$MARCFile = "$marcDirectory"."$selectFile";                                                                 #       source file for brief MARC records

##my $fixedMARCFile = "$marcDirectory".'matched.mrc';                                                                   #       where to write out the matched/enhanced records
##my $unfixedTempMARCFile = "$marcDirectory".'unmatchedTemp.mrc';                                                               #       where to stash records that don't match at the current priority,
## \$selectFile,\$marcDirectory @priorityList $matchedMARCFile, $unmatchedMARCFile $unmatchedTempMARCFile
#my $MARCFile = './SpringerNovember_utf8.mrc';									

my $good050MARCFile = "$marcDirectory"."good050_"."$selectFile";
my $error050MARCFile = "$marcDirectory"."error050_"."$selectFile";	

if (-e $good050MARCFile) { unlink ("$good050MARCFile"); } 						
if (-e $error050MARCFile) { unlink ("$error050MARCFile"); } 						

my $fileBatch = MARC::Batch->new('USMARC',"$MARCFile"); 				

open (OUTPUT, ">> $error050MARCFile") or die $!;							
binmode OUTPUT, ":utf8";
open (OUTPUT2, "> $good050MARCFile") or die $!;						
binmode OUTPUT2, ":utf8";


while ( $nextRecord = $fileBatch->next() ) {								

	my (@t050s, @t090s, @t1xxs, @t245s, @t26xs);
	my $count1xx = 0;
	my $has050 = 0;										
	my $has090 = 0;										
	my ($sub_a_1xx, $ind_2_245, $sub_a_245, $sub_a_050, $sub_b_050, $sub_a_090, $sub_b_090);

	@nextFields = $nextRecord->fields();							

	foreach $nextField(@nextFields) {	
						
		if ($nextField->tag() == '050' and $nextField->subfield('a')) {			
			$has050++ ;
			my $this_sub_a_050 = $nextField->subfield('a');
			my $this_sub_b_050 = $nextField->subfield('b');
			push @t050s,[$this_sub_a_050,$this_sub_b_050];
		}

		if ($nextField->tag() == '090' and $nextField->subfield('a')) {			
			$has090++ ;
			my $this_sub_a_090 = $nextField->subfield('a');
			my $this_sub_b_090 = $nextField->subfield('b');
			push @t090s,[$this_sub_a_090,$this_sub_b_090];
		}

		if ($nextField->tag() >= '100' and $nextField->tag() <= '199' and $nextField->subfield('a')) {			
			$count1xx++ ;
			my $this_sub_a_1xx = $nextField->subfield('a');
			push @t1xxs, [$count1xx,$this_sub_a_1xx];
		}

		if ($nextField->tag() == '245' and $nextField->subfield('a')) {	
			my $this_ind_2_245 = $nextField->indicator(2);
			my $this_sub_a_245 = $nextField->subfield('a');
			push @t245s, [$this_ind_2_245,$this_sub_a_245];
		}

		if ($nextField->tag() >= '260' and $nextField->subfield('c')) {			
			my $this_sub_c_260 = $nextField->subfield('c');
			push @t26xs, $this_sub_c_260;
		} 

		if ($nextField->tag() >= '264' and $nextField->subfield('c')) {			
			my $this_sub_c_264 = $nextField->subfield('c');
			push @t26xs, $this_sub_c_264;
		} 
		

	} # end foreach through fields

## deal with editing the 050 field, inserting into the current record

$t26xs[0] =~ s/.*([\d]{4}).*/$1/;						### turn into a sub to do this to every value in array


####TODO There is some bug in this next section that leads to writing duplicate records.  Suspect it is a problem with more than 1 050 in an array
	if ($has050 > 0) {
		foreach (@t050s) {
#			warn Dumper ($_);
#			print ${$_}[0]."\n";
			if (${$_}[1]) {									## does an 050 have a $b ?
#				print "subfield b exists : ".${$_}[1]."\n";
				if ( ${$_}[1] =~ /.*201[\d ]{1,2}eb$/) {					## add complete 201*eb to cutter
					print OUTPUT2 $nextRecord->as_usmarc();				## OUTPUT2 is good records end this path	
				} elsif ( ${$_}[1] =~ /.*201.$/ ) {
					${$_}[1] .= 'eb';						## add just 'eb' to cutter

					my @callnos = $nextRecord->field('050');
					$nextRecord->delete_fields(@callnos);
					my $newcall = MARC::Field->new( '050','','','a' => ${$_}[0], 'b' =>${$_}[1] );
					$nextRecord->insert_fields_ordered($newcall);
					print OUTPUT2 $nextRecord->as_usmarc();				## OUTPUT2 is good records end this path	

#					print "subfield b fixed : ".${$_}[1]."\n";
				} else {
					my $this_date = &get201x_date;					## need a subroutine for this if we want to do anything more complex than take the first date
					${$_}[1] .= " ".$t26xs[0].'eb';
#					print "subfield b fixed : ".${$_}[1]."\n";

					my @callnos = $nextRecord->field('050');
					$nextRecord->delete_fields(@callnos);
					my $newcall = MARC::Field->new( '050','','','a' => ${$_}[0], 'b' =>${$_}[1] );
					$nextRecord->insert_fields_ordered($newcall);
					print OUTPUT2 $nextRecord->as_usmarc();				## OUTPUT2 is good records end this path	

				}
			} else {									#### check for if last 050
#				print "subfield B is undef \n";
				my $main_entry = &pick_main_entry (\@{$t245s[0]},\@{$t1xxs[0]},\$count1xx);		##	find main entry
#				print "Main Entry: $main_entry\n";
				my $cutter_number = &make_a_cutter(\$main_entry);
				if ( ${$_}[0] !~ /.*\.[a-zA-Z].*/ ) { $cutter_number = '.'.$cutter_number };
				$cutter_number .= " $t26xs[0]eb";
				${$_}[1] = $cutter_number;
#				print "Cutter Number: $cutter_number\n";
					my @callnos = $nextRecord->field('050');
					$nextRecord->delete_fields(@callnos);
#					print "Main Call : ${$_}[0] \n";
					if ( ( (${$_}[0]) =~ /2014eb/ )  || ((${$_}[0]) =~ /2014 eb/) ) {
						my $newcall = MARC::Field->new( '050','','','a' => ${$_}[0], 'b' =>${$_}[1] );
#						print "New Call Number Problem : ${$_}[0]\n";
						$nextRecord->insert_fields_ordered($newcall);
						print OUTPUT $nextRecord->as_usmarc();				## OUTPUT is records with problems end this path	
						next;
					}
					my $newcall = MARC::Field->new( '050','','','a' => ${$_}[0], 'b' =>${$_}[1] );
					$nextRecord->insert_fields_ordered($newcall);
				if ( $cutter_number =~ /Cannot make cutter [\d]{1,4}eb/ ) {
					print OUTPUT $nextRecord->as_usmarc();				## OUTPUT is records with problems end this path	
					next;
				} else {
					print OUTPUT2 $nextRecord->as_usmarc();				## OUTPUT2 is good records end this path	
				}

			}
		}

	} elsif ($has090 > 0) {										## no 050, check for 090

	} else {											## end elsif 090 exists
					print OUTPUT $nextRecord->as_usmarc();				## OUTPUT is error file, no 050 / 090  end this path	
	}


} # end while through the $unmatchedMARC file

close (OUTPUT2);
close (OUTPUT);									

my $opMessage = '<p><b>'.$selectFile.' processed</b></p>';

return ($opMessage);

} ## end sub


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

<title>AUS Library Fixing 050s for an eBook File</title>

</head>
<body>

<span class="Breadcrumbs"><a href="http://lib-apps.aus.edu/index.php">Lib-apps Home</a> &gt; Fix 050s in an eBook File</span>

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

<title>AUS Library Fix 050s for a Springer eBook File</title>

</head>
<body>

<span class="Breadcrumbs"><a href="http://lib-apps.aus.edu/index.php">Lib-apps Home</a> &gt; Fix 050s in an eBook File</span>

<p><strong><span class="BigRedTitle">AUS Library Fix 050s for a Springer eBook File</span></strong></p>

<p>$opMessage</p>

<form action="fix050s.pl" method="POST">

<strong>Input Files</strong><br/>
<p>These are the existing MARC Files.  Upload new files from Springer, Oxford, etc. with sftp, process them with a getOCLCRecs utility, then select them here for deletion or applying 050 fixes.</p>

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


##############################					Main script execution					##############################

my ($fixedMARCFile,$unfixedMARCFile,$unfixedTempMARCFile,$i,$unfixedBatch,$k);
my ( $fileOp,$selectFile,$marcDirectory,$opMessage );

$opMessage = '';
$marcDirectory = '/var/www/html/ebookMARC/tmp/';
#$fileOp = '2';

if (-e $fixedMARCFile) { unlink ("$fixedMARCFile"); }                                               #       Nuke the previous run's $matchedMARCFile

($fileOp,$selectFile) = &parseURL();

if ( $fileOp != 1 && $fileOp != 2 ) {
        &printHTML(\$selectFile,\$marcDirectory,\$opMessage);


} elsif ( $fileOp == 2 && $selectFile ne '' ) {

        $opMessage = &processMarc(\$selectFile,\$marcDirectory);
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


