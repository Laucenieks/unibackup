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

use Net::SFTP::Foreign;
use Time::Local;
use Net::FTP;
use Cwd;

sub sftp_progress;
sub sftp_fetch_extract();
sub ftp_fetch_extract();
sub execute($$);
sub create_dir($);
sub time_taken($);
sub change_working_dir();
sub extract_files_ssh();
sub extract_files_local();

use constant DEBUG=>5;
use constant DEBUG_EXEC => 0;

our $aggressive = 0;
our $backuphost = "192.168.72.10";
our $backuphost_port = "21";
our $hostname = "cbox"; # host name what we are restoring
our $transport = "ftp";
our $user = "long";
our $pass = "";
our $remote_dir = "/data/backup/cbox";
our $insecure_backuphost = 1;
our $encrypt_password = "";
# full path to restore will be downloaded and extracted
our $dest_dir = "/home/long/restore/cbox_restore/"; 

our $rm = "/bin/rm";
our $openssl = "/usr/bin/openssl";
our $ssh_path = "/usr/bin/ssh";
our $tar = "/usr/local/bin/gtar";
our $testrun = 0;

sftp_fetch_extract() if $transport eq "sftp";
extract_files_ssh() if $transport eq "ssh";
ftp_fetch_extract() if $transport eq "ftp";
extract_files_local() if $transport eq "local";

sub sftp_progress {
	my($sftp, $data, $offset, $size) = @_;
	print "Read $offset / $size bytes\r";
}

sub sftp_get_file_list() {
	print "Entered sftp_get_file_list()\n" if (DEBUG >= 5); 
	my $starttime = time;
	my $server = $main::backuphost;
	my $user = $main::user;
	my $pass = $main::pass;
	my $folder = $remote_dir . "/";
	my @old_files;
	my $latest_full = 0;
	my $port = 0;
	$port = $main::backuphost_port if (defined($main::backuphost_port));
	if ($port eq 0) { $port = 22 };
	my %args = ();
	$args{user} = $user;
	$args{port} = $port;
	$args{password} = $pass if ($main::transport ne "ssh") and ($main::transport ne "rsync");
	$args{ssh_cmd} = $main::ssh_path;

	my $sftp = Net::SFTP::Foreign->new($server, %args);
	return "sftp_get_file_list() Error: NOLOGIN " .  $sftp->error if ($sftp->error);
	$sftp->setcwd("$folder")
		or return "sftp_get_file_list() Error: NOFILE couldn't cwd to $folder: " . $sftp->error;

	my $ls = $sftp->ls("$folder")
		or return "sftp_get_file_list() Error: NOFILE unable to retrieve directory $folder: ".
		$sftp->error;

	foreach my $n (@$ls) {
		next if $n->{filename} =~ /\./;
		print "Listing $n->{filename}\n" if (DEBUG >= 5);
		if ($n->{filename} =~ /(\w+)\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($type, $year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5, $6);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if (($type eq "full") and ($stamp > $latest_full)) {
				print "$n->{filename} is latest\n" if (DEBUG >= 3);
				$latest_full = $stamp;
			} else {
				print "$n->{filename} is not full or too older than ($stamp < " .
					"$latest_full)\n"
					if (DEBUG >= 3 );
			}
		}
	}

	print "--> Setting downloadable file list\n";
	foreach my $n (@$ls) {
		next if $n->{filename} =~ /\./;
		print "checking $n->{filename}\n" if (DEBUG >= 5);
		if ($n->{filename} =~ /(\w+)\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($type, $year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5, $6);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if ($stamp >= $latest_full) {
				print "Added $n->{filename} to restore list\n" if (DEBUG >= 2);
				push(@old_files, $n->{filename});
			}
		}
	}
	return @old_files;
}

sub sftp_fetch_extract() {
	my $starttime = time;
	my $server = $main::backuphost;
	my $user = $main::user;
	my $pass = $main::pass;
	my $folder = $remote_dir . "/";
	my @old_files;
	my $latest_full = 0;
	my $port = 0;
	$port = $main::backuphost_port if (defined($main::backuphost_port));
	if ($port eq 0) { $port = 22 };
	my %args = ();
	$args{user} = $user;
	$args{port} = $port;
	$args{password} = $pass if ($main::transport ne "ssh") and ($main::transport ne "rsync");
	$args{ssh_cmd} = $main::ssh_path;

	my $sftp = Net::SFTP::Foreign->new($server, %args);
	return "sftp_fetch_extract() Error: NOLOGIN " .  $sftp->error if ($sftp->error);
	$sftp->setcwd("$folder")
		or return "sftp_fetch_extract() Error: NOFILE couldn't cwd to $folder: " . $sftp->error;

	my @file_list = sftp_get_file_list();
	if (create_dir($main::dest_dir)) {
		print "Error: Cannot continue without $main::dest_dir. Exiting\n";
		exit;
	}

	my $callback = "sftp_progress";
	$callback = \&$callback;
	foreach (sort(@file_list)) {
		print "Aggregating $_\n";
		if ($_ =~ /(\w+)\-\d+-\d+-\d+-\d+-\d+/) {
			my $type = $1;
			print "Getting $main::remote_dir/$_/$main::hostname-$type.enc\n";
			if (create_dir("$main::dest_dir/$_")) {
				print "Error: no $main::dest_dir/$_ . Exiting\n";
				exit;
			}
			$sftp->get("$main::remote_dir/$_/$main::hostname-$type.enc",
				"$main::dest_dir/$_/$main::hostname-$type.enc", (callback => $callback));
			print "\nDownload successful.\n";
		}
	}

	print "--> Extracting archive\n";
	change_working_dir();

	my $command = "";
	foreach (sort(@file_list)) {
		if ($_ =~ /(\w+)\-\d+-\d+-\d+-\d+-\d+/) {
			my $type = $1;
			$command = "cat $main::dest_dir/$_/$main::hostname-$type.enc | ";
			if (($main::insecure_backuphost) and ($main::encrypt_password ne "")) {
				$command .= "$main::openssl enc -d -aes-256-cbc -salt " .
				"-pass pass:$main::encrypt_password | ";
			}
			$command .= "gtar -xzf -";
			execute($command, 0);
		}
	}

    my $endtime = time;
	print "sftp_fetch_extract() Time taken: ". ($endtime - $starttime) . " seconds\n";
	return 0;
}

sub ftp_get_file_list() {
	print "Entered ftp_get_file_list()\n" if (DEBUG >= 5); 
	my $starttime = time;
	my $server = $main::backuphost;
	my $user = $main::user;
	my $pass = $main::pass;
	my $folder = $remote_dir . "/";
	my @old_files;
	my $latest_full = 0;
	my $port = 0;
	$port = $main::backuphost_port if (defined($main::backuphost_port));
	if ($port eq 0) { $port = 21 };
	my $ftp = Net::FTP->new("$server", Debug => 0, Passive => 1, Port => $port);
	return "NOSERVER" unless ($ftp);
	return "NOLOGIN" unless $ftp->login("$user","$pass");
#	$ftp->mkdir("$folder") or print "ftp_get_file_list(): couldn't create $folder\n";
	$ftp->cwd("$folder") or return "ftp_get_file_list(): NOFILE couldn't: cwd $folder";
	$ftp->binary;
	
	foreach my $n ($ftp->ls()) {
		next if $n =~ /\./;
		print "Listing $n\n" if (DEBUG >= 5);
		if ($n =~ /(\w+)\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($type, $year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5, $6);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if (($type eq "full") and ($stamp > $latest_full)) {
				print "$n is latest\n" if (DEBUG >= 3);
				$latest_full = $stamp;
			} else {
				print "$n is not full or too older than ($stamp < " .
					"$latest_full)\n"
					if (DEBUG >= 3 );
			}
		}
	}

	print "--> Setting downloadable file list\n";
	foreach my $n ($ftp->ls()) {
		next if $n =~ /\./;
		print "checking $n\n" if (DEBUG >= 5);
		if ($n =~ /(\w+)\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($type, $year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5, $6);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if ($stamp >= $latest_full) {
				print "Added $n to restore list\n" if (DEBUG >= 2);
				push(@old_files, $n);
			}
		}
	}
	return @old_files;
}

sub ftp_fetch_extract() {
	my $starttime = time;
	my $server = $main::backuphost;
	my $user = $main::user;
	my $pass = $main::pass;
	my $folder = $remote_dir . "/";
	my @old_files;
	my $latest_full = 0;
	my $port = 0;
	$port = $main::backuphost_port if (defined($main::backuphost_port));
	if ($port eq 0) { $port = 21 };
	my $ftp = Net::FTP->new("$server", Debug => 0, Passive => 1, Port => $port);
	return "NOSERVER" unless ($ftp);
	return "NOLOGIN" unless $ftp->login("$user","$pass");
#	$ftp->mkdir("$folder") or print "ftp_fetch_extract(): couldn't create $folder\n";
	$ftp->cwd("$folder") or return "ftp_fetch_extract(): NOFILE couldn't: cwd $folder";
	$ftp->binary;

	my @file_list = ftp_get_file_list();
	if (create_dir($main::dest_dir)) {
		print "Error: Cannot continue without destination directory: $main::dest_dir. Exiting\n";
		exit;
	}

    foreach (sort(@file_list)) {
		print "Aggregating $_\n";
		if ($_ =~ /(\w+)\-\d+-\d+-\d+-\d+-\d+/) {
			my $type = $1;
			print "Getting $main::remote_dir/$_/$main::hostname-$type.enc\n";
			if (create_dir("$main::dest_dir/$_")) {
				print "Error: no $main::dest_dir/$_ . Exiting\n";
				exit;
			}
			my $dir = getcwd;
			chdir "$main::dest_dir/$_/" or die("ftp_fetch_extract(): Couldn't chdir to [$main::dest_dir/$_/]. Exiting.\n");
			my $start = time;
			my $size_real = $ftp->size("$main::remote_dir/$_/$main::hostname-$type.enc");
			if ($ftp->get("$main::remote_dir/$_/$main::hostname-$type.enc")) {
				print "Download successful.\n";
			} else {
				print "---> !!! Couldn't download [$main::remote_dir/$_/$main::hostname-$type.enc]. Proceeding with download.\n";
			#	exit;
			}
			my $end = time;
			my $diff = ($end - $start);
			$diff++ if ($diff == 0); 
			print "ftp_fetch_extract(): Time taken was ", time_taken($diff), " speed: " ,
		int(($size_real/1024)/$diff), "KB/sec\n" if (($size_real) and (DEBUG>=3));
			chdir $dir;
		}
    }

	print "--> Extracting archive\n";
	change_working_dir();

	my $command = "";
	foreach (sort(@file_list)) {
		if ($_ =~ /(\w+)\-\d+-\d+-\d+-\d+-\d+/) {
			my $type = $1;
			$command = "cat $main::dest_dir/$_/$main::hostname-$type.enc | ";
			if (($main::insecure_backuphost) and ($main::encrypt_password ne "")) {
				$command .= "$main::openssl enc -d -aes-256-cbc -salt " .
				"-pass pass:$main::encrypt_password | ";
			}
			$command .= "gtar -xzf -";
			execute($command, 0);
		}
	}

    my $endtime = time;
	print "sftp_fetch_extract() Time taken: ". ($endtime - $starttime) . " seconds\n";
	return 0;
}


sub change_working_dir() {
	if ($main::aggressive eq 1) {
		if (!(chdir "/")) {
			print "Couldn't chdir to / . Exiting\n";
			exit;
		} else {
			print "Current directory: /\n";
		}
	} elsif ($main::aggressive eq 0) {
		if (create_dir("$main::dest_dir/01_extract")) {
			print "Error: no $main::dest_dir/01_extract . Exiting\n";
			exit;
		} 
		if (!(chdir "$main::dest_dir/01_extract")) {
			print "Couldn't chdir to $main::dest_dir/01_extract . Exiting\n";
			exit;
		} else {
			print "Current directory: $main::dest_dir/01_extract\n";
		}
	} else {
		print "Couldnt determine restore type (check \$aggressive)\nExiting.";
		exit;
	}
}

sub create_dir($) {
	my $dir = shift;
	if (!(-r $dir)) {
		if (!(mkdir $dir)) {
			print "Error: create_dir(): Couldn't create $dir: $!\n";
			return 1;
		}
	}
}

# tars files contained in %what
# encrypts if encryption is on
# creates <type>-<date>.enc
# passes to remote host (passwordless login)
# in short: gar files | openssh encrypt | ssh user@host "cat - > dir/<type>-<date>.enc"
sub extract_files_ssh() {
	my @file_list = sftp_get_file_list();

	change_working_dir();

	my $command_string = "";
	foreach (sort(@file_list)) {
		if ($_ =~ /(\w+)\-\d+-\d+-\d+-\d+-\d+/) {
			my $type = $1;

			$command_string = "$main::ssh_path $main::user\@$main::backuphost ";
			$command_string .= " \"(cat $remote_dir" . "/" .
				"$_/$main::hostname-$type.enc )\"";
		 
			$command_string .= "| ";

			if (($main::insecure_backuphost) and ($main::encrypt_password ne "")) {
				$command_string .= "$main::openssl enc -d -aes-256-cbc -salt " .
					"-pass pass:$main::encrypt_password | ";
			}
	
			$command_string .= "$main::tar -xzf - ";
			print "$command_string\n";
			if (execute($command_string, 0)) {
				print "!!! --> Extract failed\n";
			}
		}
	} # end of foreach @file_list
}

sub extract_files_local() {
	my @file_list = get_file_list();

	change_working_dir();

	my $command_string = "";
	foreach (sort(@file_list)) {
		if ($_ =~ /(\w+)\-\d+-\d+-\d+-\d+-\d+/) {
			my $type = $1;

			$command_string = " cat $dest_dir" . "/" .
				"$_/$main::hostname-$type.enc ";
		 
			$command_string .= "| ";

			if (($main::insecure_backuphost) and ($main::encrypt_password ne "")) {
				$command_string .= "$main::openssl enc -d -aes-256-cbc -salt " .
					"-pass pass:$main::encrypt_password | ";
			}
	
			$command_string .= "$main::tar -xzf - ";
			print "$command_string\n";
			if (execute($command_string, 0)) {
				print "!!! --> Extract failed\n";
			}
		}
	} # end of foreach @file_list
}

sub get_file_list() {
	print "Entered get_file_list()\n" if (DEBUG >= 5); 
	my $starttime = time;
	my $folder = $dest_dir . "/";
	my @old_files;
	my $latest_full = 0;

	opendir(DIRHANDLE, "$folder" ) || die("Cannot open $folder: $!\n");
	my @ls = readdir(DIRHANDLE);
	closedir(DIRHANDLE);

	foreach my $n (@ls) {
		next if $n =~ /\./;
		print "Listing $n\n" if (DEBUG >= 5);
		if ($n =~ /(\w+)\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($type, $year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5, $6);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if (($type eq "full") and ($stamp > $latest_full)) {
				print "$n is latest\n" if (DEBUG >= 3);
				$latest_full = $stamp;
			} else {
				print "$n is not full or too older than ($stamp < " .
					"$latest_full)\n"
					if (DEBUG >= 3 );
			}
		}
	}

	print "--> Setting extractable file list\n";
	foreach my $n (@ls) {
		next if $n =~ /\./;
		print "checking $n\n" if (DEBUG >= 5);
		if ($n =~ /(\w+)\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($type, $year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5, $6);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if ($stamp >= $latest_full) {
				print "Added $n to restore list\n" if (DEBUG >= 2);
				push(@old_files, $n);
			}
		}
	}
	return @old_files;
}


sub date_to_timestamp($$$$$) {
	my ($year,$mon,$mday,$hour,$min) = @_;
	$mon--;
	return timelocal(0,$min,$hour,$mday,$mon,$year);
}

# executes command, calculates exec time,
# expects return value to match retrval 
# for command exectution to be successful
sub execute($$) {
	my $command = shift;
	my $retrval = shift;
	$? = 0;
	my $buffer;
	print "--> Execing [$command]\n";
	unless ($main::testrun) {
		my $time_start = time;
		open(COMMAND, "$command|") or
			print "Error: Couldn't open command: $!\n";
		# for debugging porposes
		if (DEBUG_EXEC) {
			while(read(COMMAND, $buffer, 20)) {
				print $buffer;
			}
			print "\n";
		}
		close COMMAND;
		my $time_end = time;
		print "execute(): " . time_taken($time_end - $time_start) . "\n";
		if ($? != $retrval) {
			print "command [$command] returned $?\n";
			return 1;
		}
		}
	return;
}

# returns human-readable time string
# arguments - time, seconds
sub time_taken($) {
	my $endtime = shift;
	my $time_ = ($endtime > 60) ? int($endtime/60) : $endtime;
	my $text_ = ($endtime > 60) ? "minutes" : "seconds";
	if ($time_ > 60) {
		$text_ = "hours";
		$time_ = sprintf("%.2f", ($time_/60));
	}
	return "Time taken: " . $time_ . " $text_";
}

=pod

=head1 NAME

restore.pl - restores files backed up by backup.pl.

=head1 SUMMARY

Configuration is done in this file

=head2 Restore Transports

two restore transports: sftp or rsync (passwordless) backuped files

=over 4

=item o sftp - suitable for small backups

Uses username/password combination to access remote host,
fetches latest backup and extracts it to temporary directory or 
root directory according to restore option. Do not use it for large
backups since files are copied first and then extraction is done.

=item o ssh

This is better transport option than sftp, but requires 
passwordless ssh login. Suitable for large backups since backup
is extracted on the fly.

=item o rsync

Suitable to fetch backups made by rsync transport.

=head2 Restore Options

Two restore options are available. Controlled by configuration variable 
$aggressive

=item o aggressive 

Files are restored directly in system. TODO Existing files are backed up.

=item o normal 

Files are restored in some tmp directory and restored by operator

=back

=head1 Restore process

for sftp - list directories, get date of latest full backup,
download and extract the full backup and all increments for latest full backup.
for rsync - simply download all files.

=cut
