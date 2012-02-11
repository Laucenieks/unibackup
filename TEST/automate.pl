#!/usr/bin/perl
use warnings;
use strict;

# (pre) clean state directory, clear log file
# rm state/* && cat /dev/null > logs/backup.log
# copy configuration file
# call backup.pl, sleep 60 seconds, iterate 2400 times (40 backups)
# back up log file
# clean state -> iterate

our $increment = 0; # used by modify_files
our $pause_after_tests = 0;
our $backup_source_dir = '/home/long/backup_testdir';
our $testrun = 0;

my @tests = (
	{
		id => 1,
		desc => "smbclient backup",
		md5_enable => 0,
		insecure_backuphost => 1,
		backup_transport => "smbclient",
		remote_dir => "/long/unibackup_test_smbclient",
		realdir => "/home",
		port => 445,
	},
);

my $config;
my $step = '';
foreach $config (@tests) {
	$step = "Copy conffile";
	execute("cp unibackup.conf.template unibackup.conf.$config->{backup_transport}") and goto "FAIL";
	$step = "config: echo md5_enable\n";
	if (defined($config->{md5_enable})) {
		execute("echo '\$md5_enable = $config->{md5_enable};' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";
	}
	$step = "Config: echo insecure_backuphost";
	if (defined($config->{insecure_backuphost})) {
		execute("echo '\$insecure_backuphost = $config->{insecure_backuphost};' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";
	}
	$step = "Config: echo backup_transport";
	if (defined($config->{backup_transport})) {
		execute("echo '\$backup_transport = \"$config->{backup_transport}\";' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";
	}
	$step = "Config: echo remote_dir";
	if (defined($config->{remote_dir})) {
		execute("echo '\$login_conf->{'remote_dir'} = \"$config->{remote_dir}\";' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";
	}
	$step = "Config: echo port";
	if (defined($config->{remote_dir})) {
		execute("echo '\$backuphost_port = $config->{port};' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";
		execute("echo '\$login_conf->{\"port\"} = \$backuphost_port;' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";
	}

	$step = "Config: Finish config file\n";
	execute("echo '1;' >> unibackup.conf.$config->{backup_transport}") and goto "FAIL";

	$step = "Modify files";
	if (!modify_files()) { goto "FAIL"; };

	$step = "Run unibackup.pl";
	if (execute("perl ../unibackup.pl -c unibackup.conf.$config->{backup_transport} -t $backup_source_dir:$config->{realdir}")) {goto FAIL;};

	print "PASS test id $config->{'id'} [$config->{'desc'}]\n";
	next;

FAIL:
	print "FAIL test id $config->{'id'} [$config->{'desc'}] failed on step [$step]\n";
}

# modify backup files
sub modify_files {
	execute("echo $increment >> $backup_source_dir/incrementfile") and return 0;
	execute("echo $increment >> $backup_source_dir/dir1/incrementfile")
		and return 0;
	execute("mkdir -p $backup_source_dir/dir$increment") and return 0;
	execute("echo $increment >> $backup_source_dir/dir$increment/$increment")
		and return 0;
	return 1;
}

# helper functions

# executes command, calculates exec time,
# expects return value to match retrval 
# for command exectution to be successful
# returns: 1 - fail - 0 - success
sub execute {
	my $DEBUG = 0;
	my $command = $_[0];
	my $retrval = defined($_[1]) ? $_[1] : 0;
	my $log_output = defined($_[2]) ? $_[2] : 0;
	# check if executable is in path
	if ($command =~ /(.+?)\s/) {
		my $executable = $1;
		print "execute(): executable: $executable\n" if ($DEBUG >= 2);
		if ($executable =~ /^\//) {
			if (!(-r $executable)) {
				print "execute(): Error: $executable not found or not executable\n";
				return 1;
			}
		} else {
			`/usr/bin/which $executable`;
			if (($? >> 8) != 0) {
				print "execute(): Error: $executable not found in path\n";
				return 1;
			}
		}
	} else { print "execute(): Coulnd't match command.\n" };
	$? = 0;
	print "Execing [$command]\n" if ($DEBUG >= 2);
	unless ($main::testrun) {
		my $time_start = time;
		open(COMMAND, "$command 2>&1 |") or
			print "Error: Couldn't open command: $!\n";
		# for debugging porposes
		my $buffer;
		if ($log_output eq 1) {
			while(read(COMMAND, $buffer, 20)) {
				print $buffer;
			}
		} elsif ($log_output eq 2) {
			while(read(COMMAND, $buffer, 20)) {
				print $buffer;
			}
			print "\nCommand output finished\n";
		}
		my $output = '';
		while(<COMMAND>) {
			while(read(COMMAND, $buffer, 20)) {
				$output.=$buffer;
			}
		}
		close COMMAND;
		my $time_end = time;
		print "execute(): Time taken: " . time_taken($time_end - $time_start) . "\n" 
			if (($DEBUG >= 1) and ($time_end - $time_start gt 29));
		if (($? >> 8) != $retrval) {
			my $returned = ($? >> 8);
			print "command [$command] returned $returned\n";
			if (open FILE, ">/tmp/testbackup.log") {
				print FILE $output;
				print "Command output saved to /tmp/testbackup.log\n";
			} else {
				print "Couldn't open /tmp/testbackup.log: $!\n";
			}
			return 1;
		}
	}
	return 0;
}

# returns human-readable time string
# arguments - time, seconds
sub time_taken($) {
	my $endtime = shift;
	my $time_ = ($endtime > 60) ? int($endtime/60) : $endtime;
	my $text_ = ($endtime > 60) ? "minute(s)" : "second(s)";
	if ($time_ > 60) {
		$text_ = "hour(s)";
		$time_ = sprintf("%.2f", ($time_/60));
	}
	return $time_ . " $text_";
}
