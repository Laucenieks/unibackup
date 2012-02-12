#!/usr/bin/perl
=licence
Copyright 2011 Normunds Neimanis. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY NORMUNDS NEIMANIS ''AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL NORMUNDS NEIMANIS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those
of the authors and should not be interpreted as representing official policies,
either expressed or implied, of Normunds Neimanis.
=cut

use strict;
use warnings;

use Time::Local;
use File::Path 'rmtree';

sub set_period_begginning($);
sub remove_old_files();
sub date_to_timestamp($$$$$);

our $full_backup_count = 2;

# backup period timestamp
our $period = 0;
# timestamp of beginning of current period
our $current_period_beginning;
# full backup period
our $period_full = (60*60*24); # one day
# local backup directory
our $backup_dir = "/home/long/backup_test/";

# set up logging
close STDOUT;
open (STDOUT, ">>logs/remove_old_files.pl") or die("Couldn't open logs/remove_old_files.log: $!\n");
print "\n\nStarted at " . `date`;
close STDERR;
open (STDERR, ">&STDOUT");

# do process
my $retrval = "";
set_period_begginning($period_full);
if ($retrval = remove_old_files()) {
	print "Error: remove_old_files(): $retrval\n";
}

print "Script finished\n";

# given the oldest date, add $full_backup_count periods
# to it, search for directories older than this period
# and remove files/directories
# returns 0 on success, error string on failure
sub remove_old_files() {
	my @old_files = ();
	my $dir = $main::backup_dir;
	my $err;
	
	print "Opening directory $dir\n";
	opendir(DIR, $dir) or return "Couldn't open $dir: $!\n";
	# print "Listing directories:\n";
	foreach my $n (readdir(DIR)) {
		next if $n =~ /\./;
		#print $n,"\n";
		if ($n =~ /\w+\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if ($stamp < ($main::current_period_beginning - 
				($main::period * $main::full_backup_count))) {
				print "$n scheduled for removal\n";
				push(@old_files, $n);
			} else {
				print "$n is not old enaugh($stamp > $main::current_period_beginning)\n";
			}
		}
	}
	foreach (@old_files) {
		print "Removing $_\n";
		my $starttime = time;
		
#		remove_tree("$dir/$_", error => \$err)
#			or sub {
#				if (@$err) {
#				for my $diag (@$err) {
#				my ($file, $message) = %$diag;
#				if ($file eq '') {
#					print "general error: $message\n";
#				} else {
#					print "problem unlinking $file: $message\n";
#				}
#				}
#				}
#			}
		my $endtime = time;
		print "Time taken: ". ($endtime - $starttime) . " seconds\n";
	}
	closedir DIR;
	return 0;
}

sub date_to_timestamp($$$$$) {
	my ($year,$mon,$mday,$hour,$min) = @_;
	$mon--;
	return timelocal(0,$min,$hour,$mday,$mon,$year);
}

sub set_period_begginning($) {
	my $period = shift; # (10 * 60) for 10 min
	my $year = (localtime(time))[5];
	$year+=1900;
	my $period_beginning = timelocal(0,0,0,1,0,$year);

	## calculate beginning timestamp of current period
	my $current_timestamp = timelocal(localtime(time));
	# get rounded-down passed period count
	my $passed_period_count = int((($current_timestamp - $period_beginning)
		/ $period));
	my $current_period_beginning = ($period_beginning
		+ ($passed_period_count * $period));
	$main::current_period_beginning = $current_period_beginning;
	$main::period = $period;
}
