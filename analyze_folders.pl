#!/usr/bin/perl
=licence
Copyright 2011 Normunds Neimanis. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of
      conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice, this list
      of conditions and the following disclaimer in the documentation and/or other materials
      provided with the distribution.

THIS SOFTWARE IS PROVIDED BY NORMUNDS NEIMANIS ''AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL NORMUNDS NEIMANIS OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those of the
authors and should not be interpreted as representing official policies, either expressed
or implied, of Normunds Neimanis.
=cut

use strict;
use warnings;

our $analysis_directory = "analysis";

our $config_file = "backup.conf";
our ($hostname, $backuphost, $script_directory,
	$backupdir, $backup_transport, $period_full, %what_full);

# load config file
unless (-f "$config_file") {die "config file $config_file doesn't exist\n" };
do "$config_file" or die "Error: Cannot load config file: $!\n";

# check configuration
if ($hostname eq "" or $backuphost eq ""
or $backupdir eq "" or $backup_transport eq ""
or $script_directory eq "" or $period_full lt 1) {
    die "Error: Config check failed. " .
        "Check configuration file $config_file\n";
}

# prepare analysis directory
if (!(-r $analysis_directory)) {
	print "Creating $analysis_directory\n";
	mkdir $analysis_directory;
}

my $totalsize = 0;
# loop through folders
my $directory;
foreach $directory (keys(%what_full)) {
	if (-r "$directory") {
		my $size = 0;
		# prepare output file name
		my $out_file = $directory;
		$out_file =~ s/\//\_/g;
		substr($out_file, 0, 1) = "" if ($out_file =~ /^\_/);
		chop $out_file if ($out_file =~ /\_$/);
		$out_file = $analysis_directory . "/" . $out_file;
		print "Analysing directory: $directory. Out file: $out_file\n";
		system("find $directory -type f -exec ls -l {} \\\; | awk '{ print \$5 \" \" \$9 }' | sort -n -k 1 -r > $out_file");
		system("cat $out_file | egrep -v -f /etc/backup.exclude > $out_file.include");
		system("cat $out_file | egrep -f /etc/backup.exclude > $out_file.exclude");
		if (open(FILE,"$out_file.include")) {
			while(<FILE>) {
				if (/(\d+)\s(.+)$/) {
					$totalsize += $1;
					$size += $1;
				}
			}
			close FILE;
		} else {
			print "Error: Couldn't open $out_file.include: $!\n";
		}
		print "size: " . int($size / 1024 / 1024) . " MB\n";
		$size = 0;
		if (open(FILE,"$out_file.exclude")) {
			while(<FILE>) {
				if (/(\d+)\s(.+)$/) {
					$size += $1;
				}
			}
			close FILE;
			print "excluded: " . int($size / 1024 / 1024) . " MB\n";
		} else {
			print "Error: Couldn't open $out_file.exclude: $!\n";
		}
	} else {
		print "Error: $directory: No such file/directory " .
		"or not readable by user\n";
	}
}
print "Total backup size is " . int($totalsize / 1024 / 1024) . " MB\n";
# find /usr/local -type f -size +5000k -exec ls -lh {} \; | awk '{ print $9 ": " $5 }' | sort -k 2 -r
