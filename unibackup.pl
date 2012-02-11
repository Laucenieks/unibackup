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

# base modules
use Module::Load; # devel/p5-Module-Load
use IO::Socket::INET;
use Mail::Sendmail; # mail/p5-Mail-Sendmail
use Time::Local; # devel/p5-Time-Local
use IO::Handle qw(autoflush);
use Data::Validate::IP qw(is_ipv4); # net-mgmt/p5-Data-Validate-IP
use Data::Validate::Domain qw(is_domain); # dns/p5-Data-Validate-Domain
use File::Path 'remove_tree'; # devel/p5-File-Path
use Getopt::Std; # perl built-in module

### The following modules for differrent transports are loaded when 
# backup transport is known

## ftp
#use Net::FTP; # net/p5-Net

## sftp, rsync, tar_ssh and rdiff_ssh
#use Net::SFTP::Foreign; # net/p5-Net-SFTP-Foreign

## dynamic_backuphost type http_txt_file
#use HTTP::Request; # www/p5-libwww
#use LWP::UserAgent; # www/p5-libwww

## smbclient
#use Filesys::SmbClient; # net/p5-Filesys-SmbClient

# Use the following line to enable unibackup from crontab
# 6 6 * * * root    /usr/local/scripts/unibackup/unibackup.pl 2>&1

sub execute; # command (mandantory), retrval (default 0), print output to log (default 0)
sub backup_server_up($$); # host, port
sub do_backup($); # backup_transport
sub is_time_to_run($$); # name, period
sub concat_directories($); # %hash
sub tar_files_local();
sub universal_upload_function();
sub remove_local_dir_tree($);
# smbclient
sub smbclient_upload_file();
sub smbclient_remove_old_files();
# ftp
sub ftp_upload_file();
sub ftp_remove_old_files();
# sftp
sub sftp_upload_file();
sub sftp_remove_old_files();
# for rsync, tar_ssh and rdiff_ssh
sub sftp_mkdir();
# tar-ssh passwordless
sub tar_ssh();
sub tar_files_ssh();
# rdiff
sub rdiff_ssh();
sub rdiff_ssh_process();
sub rdiff_ssh_remove_old_files();

sub time_taken($); # time,seconds
sub human_size($); # size, bytes
sub timestamp_to_date($); # timestamp
sub notify_error();
sub collect_permissions();
sub exec_pre();
sub exec_post();
sub cleanup();
sub check_success_email();
sub send_mail($$); # subject, mail_body

# Configuration
use constant DEBUG => 2; # debuglevels: 
use constant DEBUG_SCHEDULER => 1;
# 0 - no output 1 - minimal 2 - verbose
# 1 to show commands instead of execing them
our $testrun = 0;
my $config_file = "/etc/unibackup.conf";

# commands executed before backup
our @pre_commands = ();

# commands executed after backup
# usually cleanup
our @post_commands = ();

# files and directories that will be backed up
our %what_full = ();
our %what_incremental = ();

# this hosts hostname (for e-mail etc)
our $hostname;

# full backup period;
our $period_full = 0;

# incremental backup period
our $period_incremental = 0;

# how many full (and incr) backups are left on server
our $full_backup_count = 1;

# do only one full backup.
# handy in cases where we have huge amount of data
# and we want to store only oncrements
our $store_increments_only = 0;

# local directory that has enaugh space
# to create backups
our $backupdir = "/usr/backupdir";

# remote server that we will store
# backups on
our $backuphost;
our $backuphost_port;
# enable if address for backuphost is changing
our $dynamic_backuphost = 0;
our $dynamic_backuphost_function = "";
our $dynamic_backuphost_res;
our $dynamic_backuphost_res_usr = "";
our $dynamic_backuphost_res_pass = "";
sub http_error_code($$); # used by http_txt_file
sub http_txt_file();

# file containing excludes
our $exclude_file = "/etc/backup.exclude.conf";

# permission store path
our $permdir = "/tmp/permdir";

# our data stored on backup host
# will be encrypted = 1
our $insecure_backuphost = 1;

# backup password
our $encrypt_password = "";

# login credinteals and other transport 
# dependant information is saved in structure
our $login_conf = {};

# enable md5 hash file generation?
our $md5_enable = 0;

# backup transport type
our $backup_transport;
# system commands
our $rm = "/bin/rm";
our $tail = "/usr/bin/tail";
our $tar = "/usr/local/bin/gtar";
our $openssl = "/usr/bin/openssl";
our $perl = "/usr/bin/perl";
our $touch = "/usr/bin/touch";
our $dd = "/bin/dd";
our $rsync = "/usr/local/bin/rsync";
our $rdiff_backup = "/usr/local/bin/rdiff-backup";
our $bzip2 = "/usr/bin/bzip2";
our $md5 = "/sbin/md5";

# script root directory
our $script_directory;
# logs directory
our $log_dir = "";
our $rotate_logs = 1;
our $rotate_log_size = 20971520;
# state directory
our $state_dir = "";

# e-mail configuration
our $use_mail = 0; # send e-mail on failures
our $mail_from = 'source@mail.lv';
our $mail_to = 'unexistant@mail.lv';
our $relayhost = "";
our $relayport = "";
our $thishost = "127.0.0.1 (unconfigured hostname)";

### Script internally used variables
our $forced_backup = 0;
# backup type: full or increment
our $backup_type = "";
# mail trigger
our $send_mail = 0;
# current backup
our %what = ();
# This backup date
our $this_backup_timestamp = 0;
# backup date in YYYY-MM-DD-HH-MM format
our $this_backup_date = 0; 
# period when previous backup occurred
our $previous_backup;
# backup period timestamp
our $period = 0;
# timestamp of beginning of current period
our $current_period_beginning;
# previous backup status
our $prev_backup_failed = 0;
# transport dependant function callbacks
our $upload_function = "";
our $remove_old_files_function = "";
our %arguments;

getopts('c:f:t:', \%arguments);

# allow to pass configuration file from command line
if (defined($arguments{"c"}) and ($arguments{"c"})) {
	if (-r $arguments{"c"}) {
		print "Configuration file set to: $arguments{c}\n";
		$config_file = $arguments{c};
	} else {
		print "Configuration file [$arguments{c}] not readable\n";
		exit;
	}
}

if (defined($arguments{"f"}) and ($arguments{"f"})) {
	print "Forced incremental backup will be performed\n";
	$forced_backup = 1;
}

if ((defined($ARGV[0])) and ($ARGV[0])) {
	print "Unknown additional argument: $ARGV[0]\n";
}

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

# set log_dir and state_dir if done from config file
$log_dir = "$script_directory/logs" if ($log_dir eq "");
$state_dir = "$script_directory/state" if ($state_dir eq "");

# Load required perl modules
load "Net::FTP" if ($backup_transport eq "ftp");
load "Net::SFTP::Foreign" if (($backup_transport eq "sftp") or ($backup_transport eq "rsync")
	or ($backup_transport eq "tar_ssh") or ($backup_transport eq "rdiff_ssh"));
if (($dynamic_backuphost) and ($dynamic_backuphost_function eq "http_txt_file")) {
	load "HTTP::Request";
	load "LWP::UserAgent";
}
load "Filesys::SmbClient" if ($backup_transport eq "smbclient");

# set up logging
if (!(-r $log_dir)) {
	print "Log dir $log_dir doesn't exist. Creating\n";
	if (!(mkdir $log_dir)) {
		die "Error: Couldn't create $log_dir: $!\n";
	}
} elsif (-f "$log_dir/backup.log") {
	if (($rotate_logs) and ((-s "$log_dir/backup.log") > $rotate_log_size)) {
		print "Rotating $log_dir/backup.log\n";
		if (execute("$bzip2 -f $log_dir/backup.log")) {
			die "Couldn't rotate $log_dir/backup.log";
		}
	}
}
close STDOUT;
open (STDOUT, ">>$log_dir/backup.log") or die("Couldn't open $log_dir/backup.log: $!\n");
print "\n\nStarted at " . `date` . "\n";
close STDERR;
open (STDERR, ">&STDOUT");

# check if state dir exists
if (!(-r $main::state_dir)) {
	print "State dir $main::state_dir doesn't exist. Creating\n";
	if (!(mkdir $main::state_dir)) {
		die "Error: Couldn't create $main::state_dir: $!\n";
	}
}

# set up callback functions for ftp-like transports
if (($backup_transport eq "ftp") or ($backup_transport eq "sftp")
	or ($backup_transport eq "smbclient")) {
	$upload_function = "${backup_transport}_upload_file";
	$upload_function = \&$upload_function;
	$remove_old_files_function = "${backup_transport}_remove_old_files";
	$remove_old_files_function = \&$remove_old_files_function;
	$backup_transport = "universal_upload_function";
}

# run main, pass transpot function reference
if (defined(&$backup_transport)) {
    do_backup(\&$backup_transport);
} else {
    print "Error: Function $backup_transport not loaded\n";
}

# TEST part for this script
# t argument contents:
# localdir:remotedir_prepend
if (defined($arguments{"t"}) and ($arguments{"t"})) {
	# checks if full-<date> or increment-<date> (remote )directory is created
	my ($localdir, $remotedir_prepend) = split (/:/,$arguments{t});
	my $remotedir = $remotedir_prepend . $main::login_conf->{'remote_dir'} . "/" .
        $main::backup_type . "-" . $main::this_backup_date . "/";

	if (! -d "$remotedir") {
		print "FAIL: No remote dir \"$remotedir\"\n";
		exit 2;
	}
	# 
	# checks if backup file is created and can be opened, checks md5 file,
	# checks contents against original contents
	my $remotefile = $remotedir . "$main::thishost-$main::backup_type.enc";
	if (! -f "$remotefile") {
		print "FAIL: No remote file: \"$remotefile\"\n";
		exit 2;
	}

	if ($main::md5_enable) {
		my $remotemd5file = $remotedir . "$main::thishost-$main::backup_type.md5";
		if (! -f $remotemd5file) {
			print "FAIL: No md5 file\n"; exit 2;
		}
		if (`md5 $remotefile` ne `cat $remotemd5file`) {
			print "FAIL: md5 checksum failed\n"; exit 2;
		}
	}
	print "Test succesful\n";
}

print "Script Finished\n";

### subroutines folow

# main function
sub do_backup($) {
    my $callback = shift;
	my $return;
	# check if we have to do full or increment backup
	# set required vars
	if ($main::this_backup_timestamp = is_time_to_run("$main::hostname-full",
	$main::period_full)) {
		%main::what = %main::what_full;
		$main::backup_type = "full";
	} elsif ($main::this_backup_timestamp = is_time_to_run("$main::hostname-increment",
	$main::period_incremental)) {
		%main::what = %main::what_incremental;
		$main::backup_type = "increment";
	} elsif ($main::forced_backup) {
		%main::what = %main::what_incremental;
		$main::backup_type = "increment";
		$main::this_backup_timestamp = timestamp_to_date(time);
	}
	$main::this_backup_date = timestamp_to_date($main::this_backup_timestamp);
	# run backup if scheduled
	if ($main::this_backup_timestamp > 0) {
		# if store_increments_only is set, do incremental backup instead
		if (($store_increments_only) and ($main::backup_type eq "full")
		and ($main::prev_backup > 0)) {
			print "Will do incremental backup instead of full backup\n";
			# save success to prevent running 'full' again
			save_success("$main::hostname-$main::backup_type");
			$main::period = $main::period_incremental;
			$main::backup_type = "increment";
		}
		# check if remote host is UP (minor failure - mail is sent if 
		# failed twice)
		if ($dynamic_backuphost) {
			if (!(set_dynamic_backuphost($dynamic_backuphost_function))) {
				print "Error: Couldn't set dynamic backuphost addr\n";
				notify_error();
			} else {
				print "Addresses set successfully: $backuphost\n";
			}
		}
		if (!(backup_server_up($backuphost, $backuphost_port))) {
			print "Error: Couldn't connect() to backup host [$backuphost] " .
				"port [$backuphost_port]\n";
			notify_error();
		}
		# Running scheduled backup
	    if (&$callback) {
			save_success("$main::hostname-$main::backup_type");
			check_success_email();
			# Prevent script from running increment just after full backup
			# is made. set vars by is_time_to_run and save_success.
			# This should be execed just before script exit()s
			if ($main::backup_type eq "full") {
				is_time_to_run("$main::hostname-increment",
					$main::period_incremental);
				save_success("$main::hostname-increment");
			}
		} else { # backup failed
			print "Error: do_backup(): $main::hostname-$main::backup_type failed\n";
			notify_error();
		}
		exec_post();
		cleanup();
	}
}

# executes command, calculates exec time,
# expects return value to match retrval 
# for command exectution to be successful
# returns: 1 - fail - 0 - success
sub execute {
	my $command = $_[0];
	my $retrval = defined($_[1]) ? $_[1] : 0;
	my $log_output = defined($_[2]) ? $_[2] : 0;
	# check if executable is in path
	if ($command =~ /(.+?)\s/) {
		my $executable = $1;
		print "execute(): executable: $executable\n" if (DEBUG >= 2);
		if ($executable =~ /^\//) {
			if (!(-r $executable)) {
				print "execute(): Error: $executable not found or not executable\n";
				return 1;
			}
		} else {
			`/usr/bin/which $executable`;
			if ($? != 0) {
				print "execute(): Error: $executable not found in path\n";
				return 1;
			}
		}
	} else { print "execute(): Coulnd't match command.\n" };
	$? = 0;
	print "--> Execing [$command]\n";
	unless ($main::testrun) {
		my $time_start = time;
		open(COMMAND, "$command|") or
			print "Error: Couldn't open command: $!\n";
		# for debugging porposes
		if ($log_output) {
			my $buffer;
			while(read(COMMAND, $buffer, 20)) {
				print $buffer;
			}
		}
		close COMMAND;
		my $time_end = time;
		print "execute(): " . time_taken($time_end - $time_start) . "\n";
		if ($? != $retrval) {
			print "command [$command] returned $?\n";
			return 1;
		}
	}
	return 0;
}

# tries to open tcp connection to
# args: host, port
# returns 1 on success, 0 on fail
sub backup_server_up($$) {
	my ($host, $port) = @_;
	my $tries = 0;
	my $connected = 0;
	while ($connected < 1) {
		my $connection = new IO::Socket::INET (
			PeerAddr => "$host",
			PeerPort => "$port",
			Proto => 'tcp',
			Timeout => '2',
		);
		$connected = 1 if ($connection);
		next if ($connection);
		print ".";
		last if ($tries > 3);
		$tries++;
		sleep 3;
	}
	return 1 if (($connected));
	return 0;
}

# sends e-mail
# args: subject, message
sub send_mail($$) {
	return if (!($main::use_mail));
	my $return = 0;
	my ($subject, $message) = @_;
	print "--> Sending mail\n" if (DEBUG);
	my %mail = (
		To  =>  "$main::mail_to",
		From    =>  "$main::mail_from",
		Subject =>  "Notice from Backup on $main::thishost - $subject",
		Message =>  "$message"
	);
	if ($relayhost) {
		print "Using relayhost $relayhost\n" if (DEBUG >= 2);
		$mail{'smtp'} = "$relayhost";
	}
	if ($relayport) {
		print "Using relay port $relayport\n" if (DEBUG >= 2);
		$mail{'port'} = "$relayport";
	}
	sendmail(%mail) or $return = $Mail::Sendmail::error;
	if ($return) {
		print "send_mail(): Error: $return\n";
		return 0;
	}
	return 1;
}

# uploads <type>-<date>.enc to host
# upload_function and remove_old_files_function must be set
# returns 0 on fail, 1 on success
sub universal_upload_function() {
	my $retrval = 0;
	# create test file to upload to remote host
	execute("$dd if=/dev/urandom of=$main::backupdir/$main::thishost-$main::backup_type.enc bs=1k count=512", 0);
	# try to upload to check if remote host is working
	if ($retrval = &$main::upload_function) {
		print "universal_upload_function(): Error: couldnt upload testfile: $retrval\n";
		return 0;
	}
	execute("$rm $main::backupdir/$main::thishost-$main::backup_type.enc", 0);

	if (!(exec_pre())) {
		print "universal_upload_function(): Error: exec_pre() failed\n";
		return 0;
	}
	if (!(tar_files_local())) {
		print "universal_upload_function(): Error: Failed to tar_files_local.\n";
		return 0;
	}
	if ($retrval = &$main::upload_function) {
		print "universal_upload_function(): Error: backup failed: $retrval\n";
		return 0;
	}
	# remove old files on full backup if store_increments_only is disabled
	if (($store_increments_only eq 0) and ($main::backup_type eq "full")) {
		if ($retrval = &$main::remove_old_files_function) {
			print "universal_upload_function(): Error: $retrval\n";
			return 0;
		}
	}
	return 1;
}

# tars files contained in %what
# encrypts if encryption is on
# creates <type>-<date>.enc
# creates <type>-<date>.enc.md5 if md5_enable is set to true
sub tar_files_local() {
	my $command_string = "$main::tar -czvf - ";
	if ($main::exclude_file ne "") {
		$command_string .= "--exclude-from $exclude_file ";
	}
	$command_string .= "--listed-incremental=$main::state_dir/$main::hostname.snar";
	if ($main::backup_type eq "full") {
		if (-e "/$main::state_dir/$main::hostname.snar") {
			print "increment file exists, removing " .
				"/$main::state_dir/$main::hostname.snar\n";
			if (execute("$rm /$main::state_dir/$main::hostname.snar", 0)) {
				print "tar_files_local(): Error: failed to remove file\n";
				return 0;
			}
		}
	}
	my $directories = "";
	$directories = concat_directories(%what);
	if ($directories eq "") {
		print "tar_files_local(): Error: Directories array empty. Nothing to back up.\n";
		return 0;
	}
	$command_string .= " $directories";

	$command_string .= "| ";

	if (($main::insecure_backuphost) and ($main::encrypt_password ne "")) {
		$command_string .= "$main::openssl enc -aes-256-cbc -salt " .
			"-pass pass:$main::encrypt_password | ";
	}
	
	$command_string .= "cat - > " .
		"$main::backupdir/$main::thishost-$main::backup_type.enc ";
	if (execute($command_string, 0)) {
		print "tar_files_local(): Error: Command failed\n";
		return 0;
	} else {
		if ($main::md5_enable) {
			$command_string = "$main::md5 $main::backupdir/$main::thishost-$main::backup_type.enc".
				" > $main::backupdir/$main::thishost-$main::backup_type.enc.md5";
			if (execute($command_string, 0)) {
				print "tar_files_local(): Error: Couldn't create md5 file\n";
				return 0;
			} else {
				return 1;
			}
		}
		return 1;
	}
}

# uploads <type>-<date>.enc to smbclient host
# returns 0 on success, error string on failure
sub smbclient_upload_file() {
	if (!(-r "$main::backupdir/$main::thishost-$main::backup_type.enc")) {
		return "Error: File $main::backupdir/$main::thishost-".
		"$main::backup_type.enc doesn't exist\n"; 
	}
	my $dir = "//" . $main::login_conf->{'host'} . 
		$main::login_conf->{'remote_dir'} . "/" .
		$main::backup_type . "-" . $main::this_backup_date . "/";

	my $link = $dir . "$main::thishost-$main::backup_type.enc";
	my $local_file = "$main::backupdir/$main::thishost-$main::backup_type.enc",
	my $domain = $main::login_conf->{'domain'},
	my $username = $main::login_conf->{'user'},
	my $password = $main::login_conf->{'pass'},
	my $size = -s "$main::backupdir/$main::thishost-$main::backup_type.enc";

	print "smbclient_upload_file(): Uploading file: $local_file size: " .
	human_size($size) . "\n\tto $link\n" if (DEBUG>=2);
	my $smb = new Filesys::SmbClient(username  => "$username",
		password  => "$password",
		workgroup => "$domain",
		debug     => 0);
	# create directory
	print "Trying to create directory: smb:$dir\n";
	$smb->mkdir("smb:$dir",'0666') 
		or print "Error mkdir: ", $!, "\n";

	# create and upload file
	my $fd = $smb->open(">smb:$link", '0666');
	if ($!) {
		return "NOLOGIN" if $! eq "Permission denied";
		return "NOFILE No such file or directory"
			if $! eq "No such file or directory";
		return "NOSERVER" if $! eq "Connection timed out";
		return "Unknown error: [$!]";
	}
	open(FILE, "$local_file") or return "NOLOCALFILE";
	binmode(FILE);
	my $tmp;
	my $start = time;
	while (read(FILE, $tmp, 64512)) { 
		$smb->write($fd, $tmp) or print $!,"\n";
	}
	my $end = time;
	close FILE;
	my $diff = ($end - $start);
	$smb->close($fd);
	if ($main::md5_enable) {
		$fd = $smb->open(">smb:$link.md5", '0666');
		if ($!) {
			return "NOLOGIN" if $! eq "Permission denied";
			return "NOFILE No such file or directory"
				if $! eq "No such file or directory";
			return "NOSERVER" if $! eq "Connection timed out";
			return "Unknown error: [$!]";
		}
		open(FILE, "$local_file.md5") or return "NOLOCALFILE";
		binmode(FILE);
		my $tmp;
		while (read(FILE, $tmp, 64512)) {
			$smb->write($fd, $tmp) or print $!,"\n";
		}
		close FILE;
	}
	$diff++ if ($diff == 0);
	print "smbclient_upload_file(): " . time_taken($diff) ." to upload $link,",
		" size: ". human_size($size) . ", speed: " . int($size/1024/$diff),
		"KB/sec\n" if (DEBUG>=3);
	return 0;
}

# given the oldest date, add $full_backup_count periods
# to it, search for directories older than this period
# and remove files/directories
# returns 0 on success, error string on failure
sub smbclient_remove_old_files() {
	my @old_files = ();
	my $error_message_head = "smbclient_remove_old_files() Error:";
	my $dir = "//" . $main::login_conf->{'host'} . "/" .
	$main::login_conf->{'remote_dir'} . "/";
	
	my $domain = $main::login_conf->{'domain'};
	my $username = $main::login_conf->{'user'};
	my $password = $main::login_conf->{'pass'};
		
	my $starttime = time;
	my $smb = new Filesys::SmbClient(username  => "$username",
		password  => "$password",
		workgroup => "$domain",
		debug     => 0);

	print "Opening directory $dir\n" if (DEBUG >= 2);
	my $fd = $smb->opendir("smb:$dir");
	if ($!) {
		return "$error_message_head NOLOGIN" if $! eq "Permission denied";
		return "$error_message_head NOFILE No such file or directory"
			if $! eq "No such file or directory";
		return "$error_message_head NOSERVER" if $! eq "Connection timed out";
		return "$error_message_head Unknown error: [$!]";
	}
	print "Listing directories:\n" if (DEBUG >=5);
	foreach my $n ($smb->readdir($fd)) {
		next if $n =~ /\./;
		print $n,"\n" if (DEBUG >= 5);
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
		print "Removing $_\n" if (DEBUG >= 2);
		$smb->rmdir_recurse("smb:$dir/$_")
			or print "Error rmdir_recurse: ", $!, "\n";
	}
	my $endtime = time;
	print "smbclient_remove_old_files(): Time taken: ". ($endtime - $starttime) . " seconds\n";
	eval {close($fd)};
	return 0;
}

# check files/directories and append them to string
# handy when creating tar archive
sub concat_directories($) {
	my %hash = %main::what;
	my $directories_string = "";
	my $directory;
	foreach $directory (keys(%hash)) {
		if (-r "$directory") {
			$directories_string .= "$directory ";
		} else {
			print "concat_directories(): Warn: $directory: No such file/directory " .
				"or not readable by user\n";
		}
	}
	return $directories_string;
}

# scheduler.
# checks timestamp written in state file,
# by comparing timestamp in file and timestamp when current 
# period begins.
# Decides if scheduled backup should be run now
# arguments: name (for file), period (seconds)
# returns: beginning time of current period on success
# 0 on failure
sub is_time_to_run($$) {
	my $name = shift;
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

	my $last_run = 0;
	# read status file, if exists
	if (-r "$main::state_dir/$name.state") {
	my @command =  qq($main::tail -1 $main::state_dir/$name.state);
	open(COMMAND, "@command|") or die "Cannot open " .
		join(" ",@command) . "\n";
	while (<COMMAND>) {
		chomp;
		# we want to send failure message when two backups have failed
		# check if previous run was successful
		if ($_ <= ($current_period_beginning
		- $period)) {
			print "--> Previous backup failed: " .
				"timestamp: $_ prev should occur at " .
				($current_period_beginning - $period) . "\n"
				if (DEBUG_SCHEDULER);
			$main::prev_backup_failed++;
		}
		# Special case with full backups. Previous check is bad if full backup failed.
		# In such case we will delay sending failure e-mail for 2xfull_backup time.
		# Solution: Since backup script should re-try uploading every every night, it can 
		# check if period_full + 2 days has passed.
		if (($name =~ /full/) and ($_ <= ($current_period_beginning - 60*60*24*3))) {
			print "--> Previous Full! backup failed: " .
				"timestamp: $_ prev should occur at " .
				($current_period_beginning - 60*60*24*3) . "\n"
				if (DEBUG_SCHEDULER);
			$main::prev_backup_failed++;
		}
		$last_run = $_;
	}
	close COMMAND;
	} # if exist state file
	if ($last_run eq 0) {
		print "--> Previous backup failed: " .
			"This is first run\n" if (DEBUG_SCHEDULER);
		$main::prev_backup_failed++;
	}

	print "--> Type: $name\nLast covered period: " . localtime($last_run) . " ($last_run)\n" .
		"Current time: " . localtime($current_timestamp) . " ($current_timestamp)\n"
		if (DEBUG_SCHEDULER);
	# set previous_backup to make increment_only possible
	$main::prev_backup = $last_run;
	# Set up date used to name remote directories
	$main::this_backup_timestamp = $current_period_beginning;
	$main::this_backup_date = 
		timestamp_to_date($current_period_beginning);
	$main::current_period_beginning = $current_period_beginning;
	$main::period = $period;

	# check if we must run at current period
	if ($last_run <= $current_period_beginning) {
		print "--> Running job at " . `date`
			if (DEBUG_SCHEDULER);
		return $current_period_beginning;
	} else {
		print "Next run is after " . 
			localtime($current_period_beginning + $period) . " (" . 
			($current_period_beginning + $period) . ")\n"
			if (DEBUG_SCHEDULER);
		return 0;
	}
}

sub save_success($) {
	my $name = shift;
	print "save_success(): saving $name " .
		timestamp_to_date($main::this_backup_timestamp + $main::period) .
		"\n" if (DEBUG >= 3);
	open FILE, ">$main::state_dir/$name.state"
		or die("Couldn't open $main::state_dir/$name.state: $?\n");
	print FILE $main::this_backup_timestamp + $main::period . "\n";
	close FILE;
}

sub timestamp_to_date($) {
	my $timestamp = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
		localtime($timestamp);
	$year+=1900; $mon++;
	return "$year-$mon-$mday-$hour-$min";
}

sub date_to_timestamp($$$$$) {
	my ($year,$mon,$mday,$hour,$min) = @_;
	$mon--;
	return timelocal(0,$min,$hour,$mday,$mon,$year);
}

# creates permission files in $permdir
# returns 0 on failure, 1 on success
sub collect_permissions() {
	my $directory;

	# maintain permission directory
	if (-d $main::permdir) {
		remove_local_dir_tree($main::permdir);
	} else {
	    print "Permission save directory $permdir doesn't " .
			"exist, creating\n" if (DEBUG >= 1);
	    if (!(mkdir("$permdir", 0700))) {
			print "Error: Couldn't create permdir: $?\n";
			return 0;
		}
	}

	# run allrights.pl to create executable file with permissions
	foreach $directory (keys(%main::what)) {
		next if (!(-e $directory));
		my $dest = $main::what{$directory};
		my $permname = $dest;
		chop $permname;
		if (execute("$main::perl $script_directory/allrights.pl " . 
				"$directory $main::permdir$permname", 0)) {
			return 0;
		}
	}
	return 1;
}

# run pre commands
# returns 0 - fail 1 - success
sub exec_pre() {
	print "Entered exec_pre()\n" if (DEBUG >= 5);
	my $a;
	foreach $a (@pre_commands) {
		if (execute("$a", 0)) {
			print "exec_pre(): Error executing $a\n";
			return 1;
		}
	}
    if (!(collect_permissions())) {
		print "exec_pre(): couldn't collect_permissions()\n";
		return 0;
	}
    $main::what{"$main::permdir"} = "/permdir/";
	return 1;
}

# run post commands
sub exec_post() {
	print "Entered exec_post()\n" if (DEBUG >= 5);
	my $a;
	foreach $a (@post_commands) {
		if (execute("$a", 0)) {
			print "exec_post(): Command failed\n";
		}
	}
}

sub cleanup() {
	print "Etnered cleanup()\n" if (DEBUG >= 5);
	if (-d $main::permdir) {
		remove_local_dir_tree($main::permdir);
	}
	if (-d $main::backupdir) {
		remove_local_dir_tree($main::backupdir);
	}
}

# this function cleans up temporary files,
# notifies error and exits.
sub notify_error() {
	print "Entered notify_error()\n" if (DEBUG >= 5);
	exec_post();
	cleanup();
	my $message = "Log output follows\n\n";
	exit 1 if (($main::prev_backup_failed == 0) or 
		(-e "$main::state_dir/$main::hostname-sent"));
	autoflush STDOUT 1;
	if (open(FILE, "$main::log_dir/backup.log")) { 
		my $line_nr = 0;
		while(<FILE>) {
			$line_nr = tell(FILE) if (/Started/);
		}
		seek(FILE,$line_nr,0);

		while(<FILE>) {
			$message .= $_;
		}
		close FILE;
	} else {
		print "Error: Couldn't open $main::log_dir/backup.log: $?\n";
		$message = "Couldn't open $main::log_dir/backup.log: $?\n";
	}
	if (send_mail("Problem",$message)) { 
		if (execute("$touch $main::state_dir/$main::hostname-sent", 0)) {
			print "notify_error(): Couldn't create " .
				"$main::state_dir/$main::hostname-sent\n";
		}
	} else {
		print "notify_error(): Sending mail failed. Mail will be " . 
			"re-sent on next occurrance\n"
	}
	print "Script finished by notify_error()\n";
	exit 1;
}

# checks if e-mail has been sent,
# sends e-mail if required.
sub check_success_email() {
	print "Entered check_success_email()\n" if (DEBUG >= 5);
	if (($main::prev_backup_failed == 0) and
	(-e "$main::state_dir/$main::hostname-sent")) {
		print "Sending Restore mail\n";
		if (send_mail("Restored", "Backup process restored at " . `date`)) {
			if (execute("$rm $main::state_dir/$main::hostname-sent", 0)) {
				print "Error: Failed to remove $main::state_dir/$main::hostname-sent\n";
			}
		} else {
			print "check_success_email(): Sending mail failed, " .
				"I will try to re-send on next occurrance.\n";
		}
	}
}

sub ftp_upload_file() {
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/" . $main::backup_type . "-" . $main::this_backup_date . "/";
	my $srcfile = "$main::backupdir/$main::thishost-$main::backup_type.enc";
	my $port = 0;
	$port = $main::login_conf->{'port'} if (defined($main::login_conf->{'port'}));
	if ($port eq 0) { $port = 21 };
	my $ftp = Net::FTP->new("$server", Debug => 0, Passive => 1, Port => $port);
	return "NOSERVER" unless ($ftp);
	return "NOLOGIN" unless $ftp->login("$user","$pass");
	$ftp->mkdir("$folder") or print "ftp_upload_file(): couldn't create $folder\n";
	$ftp->cwd("$folder") or return "NOFILE couldn't cwd $folder";
	$ftp->binary;
	my $size = -s "$srcfile";
	my $start = time;
	unless (eval{($ftp->put("$srcfile"))}) {
		my $message = $ftp->message;
		return "NOFILE ftp message: $message";
	}
	my $end = time;
	if ($main::md5_enable) {
		unless (eval{($ftp->put("$srcfile.md5"))}) {
			my $message = $ftp->message;
			return "NOFILE ftp message: $message";
		}
	}
	$ftp->quit;
	my $diff = ($end - $start);
	$diff++ if ($diff == 0);
	print "ftp_upload_file(): Time taken was ", $diff, " seconds, size: " . human_size($size) .
	", speed: " . int(($size/1024)/$diff), "KB/Sec\n" if (DEBUG >= 1);
	return 0
}

sub ftp_remove_old_files() {
	print "Entered ftp_remove_old_files()\n" if (DEBUG >= 5); 
	my $starttime = time;
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/";
	my $port = 0;
	$port = $main::login_conf->{'port'} if (defined($main::login_conf->{'port'}));
	if ($port eq 0) { $port = 21 };
	my @old_files;
	my $ftp = Net::FTP->new("$server", Debug => 0, Passive => 1, Port => $port);
	return "ftp_remove_old_files() Error: NOSERVER" unless ($ftp);
	return "ftp_remove_old_files() Error: NOLOGIN" unless $ftp->login("$user","$pass");
	$ftp->cwd("$folder")
		or return "ftp_remove_old_files() Error: NOFILE Couln't cwd to $folder";

	foreach my $n ($ftp->ls()) {
		next if $n =~ /\./;
		print "Listing " . $n,"\n" if (DEBUG >= 5);
		if ($n =~ /\w+\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if ($stamp < ($main::current_period_beginning -
			($main::period * $main::full_backup_count))) {
				print "$n scheduled for removal\n" if (DEBUG >= 3);
				push(@old_files, $n);
			} else {
			print "$n is not old enaugh($stamp > $main::current_period_beginning)\n"
					if (DEBUG >= 3 );
			}
		}
	}
	foreach (@old_files) {
		print "Removing $_\n";
		$ftp->rmdir($main::login_conf->{'remote_dir'} . "/$_", 1)
			or print "Error rmdir_recurse: ", $!, "\n";
	}
	my $endtime = time;
	print "ftp_remove_old_files() Time taken: ". ($endtime - $starttime) . " seconds\n";
	$ftp->quit;
	return 0;
}

sub sftp_upload_file() {
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/" . 
		$main::backup_type . "-" . $main::this_backup_date . "/";
	my $srcfile = "$main::backupdir/$main::thishost-$main::backup_type.enc";
	my $port = 0;
	$port = $main::login_conf->{'port'} if (defined($main::login_conf->{'port'}));
	if ($port eq 0) { $port = 22 };
	my $sftp = Net::SFTP::Foreign->new($server, 
		( user => $user,
			port => $port,
			password => $pass,
			more => [qw(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no)],
		)
	);
	return "NOLOGIN " .  $sftp->error if ($sftp->error);
	$sftp->mkdir("$folder") or print "sftp_upload_file(): couldn't create $folder\n";
	$sftp->setcwd("$folder") or return "NOFILE couldn't cwd $folder " . $sftp->error;
	my $size = -s "$srcfile";
	my $start = time;
	unless (eval{($sftp->put("$srcfile", $main::thishost."-".$main::backup_type . ".enc"))}) {
		my $message = $sftp->error;
		return "NOFILE sftp message: $message";
	}
	if ($main::md5_enable) {
		unless (eval{($sftp->put("$srcfile.md5", $main::thishost."-".$main::backup_type . ".enc.md5"))}) {
			my $message = $sftp->error;
			return "NOFILE sftp message: $message";
		}
	}
	my $end = time;
	my $diff = ($end - $start);
	$diff++ if ($diff == 0);
	print "sftp_upload_file(): Time taken was ", $diff, " seconds, size: $size: " . human_size($size) .
	", speed: " . int(($size/1024)/$diff), "KB/Sec\n" if (DEBUG >= 1);
	return 0;
}

sub sftp_remove_old_files() {
	print "Entered sftp_remove_old_files()\n" if (DEBUG >= 5); 
	my $starttime = time;
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/";
	my @old_files;
	my $port = 0;
	$port = $main::login_conf->{'port'} if (defined($main::login_conf->{'port'}));
	if ($port eq 0) { $port = 22 };
	my %args = ();
	$args{user} = $user;
	$args{port} = $port;
	$args{password} = $pass if (($main::backup_transport ne "rsync_ssh")
		and ($main::backup_transport ne "tar_ssh"));
	$args{ssh_cmd} = $main::login_conf->{'ssh_path'};
	$args{more} = [qw(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no)];

	my $sftp = Net::SFTP::Foreign->new($server, %args);
	return "sftp_remove_old_files() Error: NOLOGIN " .  $sftp->error if ($sftp->error);
	$sftp->setcwd("$folder")
		or return "sftp_remove_old_files() Error: NOFILE couldn't cwd to $folder: " . $sftp->error;

	my $ls = $sftp->ls("$folder")
		or return "sftp_remove_old_files() Error: NOFILE unable to retrieve directory $folder: ".
		$sftp->error;

	foreach my $n (@$ls) {
		next if $n->{filename} =~ /\./;
		print "Listing $n->{filename}\n" if (DEBUG >= 5);
		if ($n->{filename} =~ /\w+\-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)/) {
			my ($year,$mon,$mday,$hour,$min) = ($1, $2, $3, $4, $5);
			my $stamp = date_to_timestamp($year,$mon,$mday,$hour,$min);
			if ($stamp < ($main::current_period_beginning -
			($main::period * $main::full_backup_count))) {
				print "$n->{filename} scheduled for removal\n" if (DEBUG >= 3);
				push(@old_files, $n->{filename});
			} else {
				print "$n->{filename} is not old enaugh($stamp > " .
				"$main::current_period_beginning)\n"
				if (DEBUG >= 3 );
			}
		}
	}
	foreach (@old_files) {
		print "Removing $_\n";
		$sftp->rremove($main::login_conf->{'remote_dir'} . "/$_", 
			on_error => sub { print "Error: rremove: " . $sftp->error; });
	}
	my $endtime = time;
	print "sftp_remove_old_files() Time taken: ". ($endtime - $starttime) . " seconds\n";
	return 0;
}

# call sftp_remove_old_files if rsync was successful
# retursn 0 - failure 1 - success
sub rsync_ssh() {
	my $retrval = "";
	if ($retrval = sftp_mkdir()) {
		print "rsync_ssh(): Error: couldnt sftp_mkdir(): $retrval\n";
		return 0;
	}
	if (!(exec_pre())) {
		print "rsync_ssh(): exec_pre() failed\n";
		return 0;
	}
	if (!(rsync_ssh_process())) {
		print "rsync_ssh(): rsync_ssh_process() failed\n";
		return 0;
	}
	if ($main::backup_type eq "full") {
		if ($retrval = sftp_remove_old_files()) {
			print "rsync_ssh(): Error: sftp_remove_old_files() failed: $retrval\n";
			return 0;
		}
	}
	return 1;
}

# this procedure uses passwordless logins for rsync-ssh
# rsync backup phylosophy looks upside-down from tar perspective
# full backup is most current one and increments are 
# backups for changed files.
# But this still allows us to use sftp_remove_old_files()
# when 'full backup' occurs
# remote dir listing after few backups looks like:
# full    <------- current
# increment-hour <- backups files that changed in current
# increment-hour
# increment-hour
# ..
sub rsync_ssh_process() {
	my $retval = "";
	my $return = 1;
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/";
	my $port = (defined($main::login_conf->{'port'})) ? $main::login_conf->{'port'} : "22";
	my $backupdir = $main::backupdir;
	my $real_backupdir = $backupdir;
	my $directory;
	my $starttime = time;
	foreach $directory (keys(%main::what)) {
		if (!(-r "$directory")) {
			print "Warn: $directory: No such file/directory " .
				"or not readable by user\n";
			next;
		}
		my $dest = $main::what{$directory};
		my $date = `date +%Y-%m-%d-%H-%M`;
		chomp $date;
		my $permname = $dest;
		chop $permname;
		# remove double-slashes for rsync command
		my $rsync_dest = "$folder/full/$dest";
		my $backup_dir = "$folder/increment-$main::this_backup_date/$dest";
		$rsync_dest =~ s/\/\//\//g;
		$backup_dir =~ s/\/\//\//g;
		my $rsync_args = qq($rsync -e 'ssh -p $port -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' --force --ignore-errors --delete --delete-excluded --backup --backup-dir=$backup_dir -av --exclude-from=$main::exclude_file $directory $user\@$main::backuphost\:$rsync_dest);
		if (execute($rsync_args, 0, 1)) {
			$return = 0;
		}
	}
	my $endtime = time;
	print "rsync_ssh(): Total " . time_taken($endtime - $starttime) . "\n";
	return $return;
}

# tars files contained in %what
# encrypts if encryption is on
# creates <type>-<date>.enc
# passes to remote host (passwordless login)
# in short: gar files | openssh encrypt | ssh user@host "cat - > dir/<type>-<date>.enc"
sub tar_files_ssh() {
	my $return = "";
	my $port = (defined($main::login_conf->{'port'})) ? $main::login_conf->{'port'} : "22";
	my $command_string = "$main::tar -czvf - ";
	if ($main::exclude_file ne "") {
		$command_string .= "--exclude-from $exclude_file ";
	}
	$command_string .= "--listed-incremental=/$main::state_dir/$main::hostname.snar";
	if ($main::backup_type eq "full") {
		if (-e "/$main::state_dir/$main::hostname.snar") {
			print "increment file exists, removing " .
				"/$main::state_dir/$main::hostname.snar\n";
			if (execute("$rm /$main::state_dir/$main::hostname.snar", 0)) {
				print "tar_files_ssh(): Error: failed to remove " .
					"/$main::state_dir/$main::hostname.snar file\n";
				return 1;
			}
		}
	}
	my $directories = "";
	$directories = concat_directories(%what);
	if ($directories eq "") {
		print "tar_files_ssh(): Error: Directories array empty. Nothing to back up.\n";
		return 1;
	}
	$command_string .= " $directories";

	$command_string .= "| ";

	if (($main::insecure_backuphost) and ($main::encrypt_password ne "")) {
		$command_string .= "$main::openssl enc -aes-256-cbc -salt " .
			"-pass pass:$main::encrypt_password | ";
	}

	$command_string .= "ssh -p $port -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no " .
		"$main::login_conf->{'user'}\@" . 
		$main::login_conf->{'host'};
	
	$command_string .= " \"(cat - > " .
		$main::login_conf->{'remote_dir'} . "/" .
		$main::backup_type . "-" . $main::this_backup_date . "/" .
		"$main::thishost-$main::backup_type.enc)\"";
	if (execute($command_string, 0, 1)) {
		print "tar_files_ssh(): Error: Command failed\n";
		return 1;
	} else {
		return 0;
	}
}

# creates folder named as shown in $folder further
# returns 0 on success, error message on failure
sub sftp_mkdir() {
	# rsync_ssh stores full backup without date,
	# so we need to create this dir only once
	return 0 if (($main::backup_transport eq "rsync_ssh")
		#and ($main::backup_type eq "full")
		and ($main::prev_backup > 0));

	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/" .
		$main::backup_type . "-" . $main::this_backup_date . "/";
	# create folder "full" once for rsync_ssh
	$folder = $main::login_conf->{'remote_dir'} . "/" .
		$main::backup_type if (($main::backup_type eq "full")
		and ($main::backup_transport eq "rsync_ssh"));
	my $port = 0;
	$port = $main::login_conf->{'port'} if (defined($main::login_conf->{'port'}));
	if ($port eq 0) { $port = 22 };
	my %args = ();
	$args{user} = $user;
	$args{port} = $port;
	$args{password} = $pass if (($main::backup_transport ne "rsync_ssh")
		and ($main::backup_transport ne "tar_ssh"));
	$args{ssh_cmd} = $main::login_conf->{'ssh_path'};
	$args{more} = [qw(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no)];
	my $sftp = Net::SFTP::Foreign->new($server, %args);
	return "NOLOGIN " .  $sftp->error if ($sftp->error);
	$sftp->mkdir("$folder")
		or print "sftp_mkdir(): Warn: couldn't create $folder: (" . $sftp->error . ")\n";
	$sftp->setcwd("$folder")
		or return "NOFILE couldn't cwd to $folder: " . $sftp->error;
	return 0;
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

sub human_size($) {
	my $size = shift;
	$size = ($size / 1024); # convert to KB
	my $size_ = ($size > 1024) ? int($size/1024) : $size;
	my $text_ = ($size > 1024) ? "MB" : "KB";
	if ($size_ > 1024) {
		$text_ = "GB";
		$size_ = sprintf("%.2f", ($size/1024));
	}
	return "$size_ $text_";
}

sub tar_ssh() {
	my $return = "";
	my $retrval;
	if ($return = sftp_mkdir()) {
		print "tar_ssh(): Error sftp_mkdir(): $return\n";
		return 0;
	}

	if (!(exec_pre())) {
		print "rsync_ssh(): exec_pre() failed\n";
		return 0;
	}

	# upload only one full backup if $store_increments_only enabled
	if (($store_increments_only eq 1) and ($main::prev_backup_failed eq 1) 
	and ($main::backup_type eq "full")) {
		if (tar_files_ssh()) {
			print "tar_ssh(): tar_files_ssh() full backup failed.\n";
			return 0;
		}
	} else {
		if (tar_files_ssh()) {
			print "tar_ssh(): tar_files_ssh() failed.\n";
			return 0;
		}
	}
	# remove old files on full backup if store_increments_only is disabled
	if (($store_increments_only eq 0) and ($main::backup_type eq "full")) {
		if ($retrval = sftp_remove_old_files()) {
			print "tar_ssh(): Error: sftp_remove_old_files() failed: $retrval\n";
			return 0;
		}
	}
	return 1;
}

# removes directory contents, 
# leaves root dir intact
sub remove_local_dir_tree($) {
	my $dir = shift;
	my $err;
	remove_tree("$dir", {error => \$err, keep_root => 1}) or sub {
	if (@$err) {
		for my $diag (@$err) {
			my ($file, $message) = %$diag;
			if ($file eq '') {
				print "general error: $message\n";
			} else {
				print "problem unlinking $file: $message\n";
			}
		}
	}} 
}

sub set_dynamic_backuphost($) {
	my $function = shift;
	my $function_call = \&$function;
	my $newhost;
	if (defined(&$function)) {
		if ($newhost = &$function_call) {
			
		} else {
			return 0;
		}
	} else {
		print "set_dynamic_backuphost(): Error: Function $function not loaded\n";
		return 0;
	}
	if ((is_domain($newhost)) or (is_ipv4($newhost))) {
		$main::backuphost = $newhost;
		$main::login_conf->{'host'} = $newhost;
	} else {
		print "set_dynamic_backuphost(): Error: Dynamic host " .
			"name check failed: $newhost is not IP or Domain\n";
		return 0;
	}
	return 1;
}

sub http_txt_file() {
	my $page = $main::dynamic_backuphost_res;
	my $user = $main::dynamic_backuphost_res_usr;
	my $pass = $main::dynamic_backuphost_res_pass;
	my $result = 0;
#	if ($page =~ /^http:\/\/(.+?)\//) {
#		if (is_domain($1)) {
#			return "NODNS" unless (nslookup($1));
#		}
#	}
	my $req = HTTP::Request->new(GET => "$page");
	my $ua = LWP::UserAgent->new(keep_alive=>0); #ua
	$req->content_type('text/html');
	$req->content("");
	if (($user) and ($pass)) {
		$req->authorization_basic("$user", "$pass");
	}
	$ua->agent("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1)");
	my $res = $ua->request($req); # ua
	if ($res->is_success) {
		$result = $res->content;
		chomp $result;
		# print $res->content;
		# print "Success: size [$size] diff [$diff]";
		return $result;
	} else {
		print "http_txt_file(): Error: ". http_error_code($page, \$res) . "\n";
		return 0;
	}
}

sub http_error_code($$) {
	my ($page, $res) = @_;
	print $$res->status_line . "\n";
	if ($$res->status_line =~ /500 Can't connect to/) {
		return "TIMEOUT"; # DOWN
	} elsif ($$res->status_line =~ /Bad hostname/) {
		return "NODNS"; # DOWN
	} elsif ($$res->status_line =~ /timeout/) {
		return "TIMEOUT"; # DOWN
	} elsif ($$res->status_line =~ /timed out/){
		return "TIMEOUT";
	} elsif ($$res->status_line =~ /^404/) {
		my $message = $$res->status_line;
		return "NOFILE $message";
	} elsif ($$res->status_line =~ /^401/) {
		return "NOLOGIN"; # NOLOGIN
	} elsif ($$res->status_line =~ /^4\d+/) {
		print "Answer for $page: " . $$res->status_line . "\n";
		my $message = $$res->status_line;
		return "NOFILE $message";
	} elsif ($$res->status_line =~ /^500/) {
		return "BUSY"; # BUSY
	} elsif ($$res->status_line =~ /^5\d+/) {
		print "Answer for $page: " . $$res->status_line . "\n";
		return "BUSY";
	} else {
		print "Answer for $page: " . $$res->status_line . "\n";
		return "NOSERVER"; # NOSERVER
	}
}

sub rdiff_ssh() {
## test server
# rdiff-backup --test-server long@192.168.72.1::/home/long/backup-test/etc/
## run backup, print statistics
# rdiff-backup --print-statistics --exclude-globbing-filelist /etc/backup.exclude.conf /etc/ long@192.168.72.1::/home/long/backup-test/etc/
## remove old files
# rdiff-backup --remove-older-than 5D long@192.168.72.1::/home/long/backup-test/etc/
## set differrent port
# rdiff-backup --remote-schema "ssh -C -p 9222 %s rdiff-backup --server"
# -o ConnectTimeout=10
	my $retval = "";
	my $return = 1;
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/";
	my $port = (defined($main::login_conf->{'port'})) ? $main::login_conf->{'port'} : "22";
	my $starttime = time;

	# test server. We know that ssh is answering from remove host
	# Now we should test if rdiff is OK on remote host.
	my $command = qq($rdiff_backup --remote-schema "ssh -C -p $port -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 \%s rdiff-backup --server" --test-server $user\@${server}::$folder);
	if (execute($command, 0, 1)) {
		print "rdiff_ssh(): Error: Testing $server failed.\n";
		return 0;
	}

	if (!(exec_pre())) {
		print "rsync_ssh(): exec_pre() failed\n";
		return 0;
	}
	if (!(rdiff_ssh_process())) {
		print "rdiff_ssh(): Error: backup failed.\n";
		$return = 0;
	}
	if ($main::backup_type eq "full") {
		if (!(rdiff_ssh_remove_old_files())) {
			print "Error: rdiff_ssh_remove_old_files() failed\n";
			$return = 0;
		}
	}
	return $return;
}

sub rdiff_ssh_process() {
	my $retval = "";
	my $return = 1;
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/";
	my $port = (defined($main::login_conf->{'port'})) ? $main::login_conf->{'port'} : "22";
	my $starttime = time;

	# iterate and upload each directory
	my $directory;
	foreach $directory (keys(%main::what)) {
		if (!(-r "$directory")) {
			print "rdiff_ssh_process(): Error: $directory: No such file/directory " .
				"or not readable by user\n";
			next;
		}
		my $dest = $main::what{$directory};
		my $date = `date +%Y-%m-%d-%H-%M`;
		chomp $date;
		my $permname = $dest;
		chop $permname;
		# remove double-slashes for rdiff command
		my $rsync_dest = "$folder$dest";
		$rsync_dest =~ s/\/\//\//g;
		my $command = qq($rdiff_backup --remote-schema "ssh -C -p $port -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 \%s rdiff-backup --server" $directory $user\@${server}::$rsync_dest);
		if (execute($command, 0, 1)) {
			$return = 0;
		}
	}
	print "rdiff_ssh_process(): Total " . time_taken(time - $starttime) . "\n";
	return $return;
}

sub rdiff_ssh_remove_old_files() {
	my $retval = "";
	my $return = 1;
	my $server = $main::login_conf->{'host'};
	my $user = $main::login_conf->{'user'};
	my $pass = $main::login_conf->{'pass'};
	my $folder = $main::login_conf->{'remote_dir'} . "/";
	my $port = (defined($main::login_conf->{'port'})) ? $main::login_conf->{'port'} : "22";
	my $starttime = time;
	my $remove_older_than = $main::period_full * $main::full_backup_count;

	# iterate and remove files from each remote directory
	my $directory;
	foreach $directory (keys(%main::what)) {
		if (!(-r "$directory")) {
			print "rdiff_ssh_remove_old_files(): Error: $directory: No such file/directory " .
				"or not readable by user\n";
			next;
		}
		my $dest = $main::what{$directory};
		# remove double-slashes for rdiff command
		my $rsync_dest = "$folder$dest";
		$rsync_dest =~ s/\/\//\//g;
		my $command = qq($rdiff_backup --force --remote-schema "ssh -C -p $port -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 \%s rdiff-backup --server" --remove-older-than ${remove_older_than}s $user\@${server}::$rsync_dest);
		if (execute($command, 0, 1)) {
			$return = 0;
		}
	}
	print "rdiff_ssh_remove_old_files(): Total " . time_taken(time - $starttime) . "\n";
	return $return;
}
