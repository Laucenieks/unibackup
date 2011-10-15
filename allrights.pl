#!/usr/bin/perl

# Allrights- A UNIX perl tool for making backups of file permissions, owners/groups and file flags

# Copyright (C) 2005 Norbert Klein <norbert@acodedb.com>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

# Version 1.0
# Tested on Freebsd 6.0 




use strict;
use warnings;
#use diagnostics;
use Cwd;
use File::Spec::Functions;


my $error="";
our $startdir="";

if ($ARGV[0]){
  #help text if argument is passed to script
  if ($ARGV[0] =~ /^(\?|help|-h|--help)$/) {
print <<'END';
  
  This script is only for UNIX, don't use it with Linux! A Linux version is available at
  http://www.acodedb.com.
  It allows you to backup and restore file properties. It backups the permissions, owners, 
  groups and file flags of all files and folders including all subfolders. 
  IT DOES NOT BACKUP THE FILES AND FOLDERS THEMSELVES !!!

  Usage: ./allrights.pl  [DIR | OPTION]

  Examples: ./allrights.pl
            ./allrights.pl --help
            ./allrights.pl /folder1/folder2
            ./allrights.pl ./folder2

  DIR: 
  Directory were to start the backup (starting point of recursive descend)
  
  OPTIONS: 
  ?, help, -help, --help will display this help text
  
  Without parameter the starting point for the backup will be the current working directory	
	
	
  BACKUP
  ------
  Run the script including the path to the directory you want to backup or run it inside this
  directory without paramters. Three executable shell scripts will be created within this folder:
  
  $permissions_backup
  $ownergroup_backup
  $fileflags_backup
 
  All are simple shell scripts (bash) which do not need Perl and can be run independently. 
  The program backups hidden files and hidden folders also. But note that symbolic links 
  will be ignored. If a symbolic link points to a file outside of the saved directory tree, 
  this file will remain unchanged. 
  If a user name or group name does not exist any more in /etc/passwd or /etc/group the uid or 
  gid itself will be written into the backup files instead of the names. This happens if
  a group or user has been deleted, but files with these ids still exist.
   
  The backup and restoration of the file flags may take a long time.  
	
  RESTORE
  -------
  You can run the backup scripts independently. If you want to restore permissions, owners/groups
  and file flags just run all three. In case you have removed some files since the last
  backup, the script output will show you which files couldn't be found. 
  
  
  Author: norbert@acodedb.com
  Have fun !
  
END
  exit();
  }else{
    #if user passes relative path, change to absolute path
    if (substr($ARGV[0],0,1) eq "/"){
      $startdir=$ARGV[0];
    }else{
      $startdir=cwd() . "/" . $ARGV[0];
      $startdir =~ s|^//|/|;
    }   
  }  
}else{
  $startdir=cwd();
}

#first line in every output shall be empty
#printf "\n";


exit unless($ARGV[1]);
my $outputfile = $ARGV[1];
#print "[$outputfile]\n";
#exit;
my $permissions_backup = $outputfile . "_permissions.sh";
my $ownergroup_backup = $outputfile . "_ownergroup.sh";
my $fileflags_backup = $outputfile . "_fileflags.sh";


#check if folder passed by user exists
if (!-e $startdir) {
  $error=" The folder $startdir does not exist";
  &finish();
}


#get content from /etc/passwd and /etc/group for uid/gid -> username/groupname translation
my %unames=();
my %gnames=();

#the script will produce a correct backup, also if etc/passwd cannot be opened
if (!open(FILE,"/etc/passwd")){
  $error=" The file \"/etc/passwd\" could not be opened\n";
#  $error.=" This means that your backup scripts (.sh) have been created with UIDs instead of names (just a matter of clearness)\n";
#  $error.=" Your backup has been created successfully\n";
#  $error.=" You can restore your permissions and owners/groups by running \"./$permissions_backup\" and/or \"./$ownergroup_backup\"";
}else {
  my $uname="";
  my $uid="";
  while (<FILE>) {
    #skip comments
    if($_=~/^\s*#/){ next; }
    my @l=split(":",$_);
    $uname=$l[0];
    $uid=$l[2];
    $unames{$uid}=$uname;
  }
}
close(FILE);

#the script will produce a correct backup, also if /etc/group cannot be opened
if (!open(FILE,"/etc/group")){
  $error=" The file \"/etc/group\" could not be opened\n";
#  $error.=" This means that your backup scripts (.sh) have been created with GIDs instead of names (just a matter of clearness)\n";
#  $error.=" Your backup has been created successfully\n";
#  $error.=" You can restore your permissions and owners/groups by running \"./$permissions_backup\" and/or \"./$ownergroup_backup\"";
}else {
  my $gname="";
  my $gid="";
  while (<FILE>) {
    #skip comments
    if($_=~/\s*#/){ next; }
    my @l=split(":",$_);
    $gname=$l[0];
    $gid=$l[2];
    $gnames{$gid}=$gname;
  }
} 
close(FILE);


#check if backupfiles already exists
if (-e "$permissions_backup"){
  $error= " The backup file \"$permissions_backup\" already exists\n";
  $error.=" Please rename or remove it as previous backup files will not be overwritten";
  &finish();
}
if (-e "$ownergroup_backup"){
  $error= " The backup file \"$ownergroup_backup\" already exists\n";
  $error.=" Please rename or remove it as previous backup files will not be overwritten";
  &finish();
}
if (-e "$fileflags_backup"){
  $error= " The backup file \"$fileflags_backup\" already exists\n";
  $error.=" Please rename or remove it as previous backup files will not be overwritten";
  &finish();
}



#printf " Creating backup files. This may take a while...\n";


system("touch $permissions_backup");

if (!open FILE, "+< $permissions_backup"){
  $error= " The file \"$permissions_backup\" could not be opened";
  &finish();
}
seek FILE,0,0;

#permission backup
sub recdirs_p($);    #prototype needed before
print FILE "#!/bin/sh\n";
print FILE "#THE RESTORATION OF PERMISSIONS STARTS HERE: $main::startdir\n";
print FILE "#START > ---------------\n";
print FILE "\necho\necho \" Restoring PERMISSIONS for $main::startdir\"\n";
&recdirs_p($startdir,"");
print FILE "\necho \" Completed\"\necho\n";
print FILE "\n#END < ---------------\n";

#make executable shell script out of it
system ("chmod 00700 $permissions_backup");  
close (FILE);

#printf " \"$permissions_backup\" created\n";




system("touch $ownergroup_backup");

if (!open FILE, "+< $ownergroup_backup"){
  $error= " The file \"$ownergroup_backup\" could not be opened";
  &finish();
}
seek FILE,0,0;

#owner, group backup
sub recdirs_og($);    #prototype needed before
print FILE "#!/bin/sh\n";
print FILE "#THE RESTORATION OF OWNERS/GROUPS STARTS HERE: $startdir\n";
print FILE "#START > ---------------\n";
print FILE "\necho\necho \" Restoring OWNERS/GROUPS for $startdir\"\n";
&recdirs_og($startdir,"");
print FILE "\necho \" Completed\"\necho\n";
print FILE "\n#END < ---------------\n";

#make executable shell script out of it 
system ("chmod 00711 $ownergroup_backup");  
close(FILE);

#printf " \"$ownergroup_backup\" created\n";




#system("touch $fileflags_backup");

#if (!open FILE, "+< $fileflags_backup"){
#  $error= " The file \"$fileflags_backup\" could not be opened";
#  &finish();
#}
#seek FILE,0,0;
#
##file flags backup
#sub recdirs_ff($);    #prototype needed before
#print FILE "#!/bin/sh\n";
#print FILE "#THE RESTORATION OF FILE FLAGS STARTS HERE: $startdir\n";
#print FILE "#START > ---------------\n";
#print FILE "\necho\necho \" Restoring FILE FLAGS...\"\n";
#&recdirs_ff($startdir,"");
#print FILE "\necho \" Completed\"\necho\n";
#print FILE "\n#END < ---------------\n";

##make executable shell script out of it 
#system ("chmod 00711 $fileflags_backup");  
#close(FILE);

#printf " \"$fileflags_backup\" created\n";


&finish();


#functions ------------------------------------------------------------------------------------------------

sub finish(){
  #error output
  if ($error ne "") { 
    printf(" Error(s) occurred:\n%s\n",$error);
  }else{
#    printf " Backup completed\n\n";
#    printf " You can restore your permissions, owners/groups and file flags by running \"./$permissions_backup\", \"./$ownergroup_backup\" and \"$fileflags_backup\"\n\n";
#    printf " Please note: When you restore the permissions or owners/groups it may happen that for certain objects this is not possible (due to file flags).\n";
#    printf " For all affected objects an error message is displayed.\n";
#    printf " You can restore them manually or do a \"chflags -R 0 yourfolder/\".\n";
#    printf " The latter will erase all file flags of the objects below yourfolder/!\n";
#    printf " Then another restore of permissions and owners/groups will be completely successful.\n";
#    printf " If you do this, don't forget to run $fileflags_backup at last to restore your file flags!\n";
  }
#  printf "\n";
  #cleanup
  exit();
}


sub recdirs_p($){
  my $path=$_[0];
  if(opendir(DIR, $path)) {
    #get all objects besides . and ..
    my @obj=grep!/^\.$|^\.\.$/,readdir(DIR);  
 
    #all
    my $mode="";
    my $file="";	
    my $full_path="";
    foreach(@obj){
      $file=$path . "/" . $_;
      #ignore symbolic links
      if (-l $file) { next; }
      $mode=(stat($file))[2];	    
      $mode=sprintf("0%o ", $mode & 07777);
      #if necessary fill with leading zeros 
      if (length($mode) < 6){ $mode = '0' x (6 - length($mode)) . $mode; }
      #support for file names with quotes
      $full_path = shell_escape(catfile($path, $_));
      print FILE qq{chmod $mode "$full_path"\n};
    }  
 
    #directories
    foreach(@obj) {
      #(-d "file") also recognizes symbolic links, if they point to a directory
      if((-d "$path/$_") && (!-l "$path/$_")) {
        &recdirs_p("$path/$_");
      }
   }
   close DIR;
 }
}


sub recdirs_og($){
  my $path=$_[0];
  if(opendir(DIR, $path)) {
  my @obj=grep!/^\.$|^\.\.$/,readdir(DIR);
 
    my $uname="";
    my $gname="";
    my $file="";
    my $full_path="";
    foreach(@obj){
      $file=$path . "/" . $_;
      if (-l $file) { next; }
      #get username/groupname for uid/gid. if username/groupname don't exist keep uid/gid 
      if (!defined($uname=$unames{((stat($file))[4])})) { $uname=(stat($file))[4]; }	
      if (!defined($gname=$gnames{((stat($file))[5])})) { $gname=(stat($file))[5]; }	
      $full_path = shell_escape(catfile($path, $_));
      print FILE qq{chown $uname:$gname "$full_path"\n};
    }  
 
  foreach(@obj) {
    if((-d "$path/$_") && (!-l "$path/$_")) {
      &recdirs_og("$path/$_");
    }
   }
   close DIR;
 }
}


sub recdirs_ff($){
  my $path=$_[0];
  if(opendir(DIR, $path)) {
  my @obj=grep!/^\.$|^\.\.$/,readdir(DIR);
    
    my $file="";
    my $fileflags="";
    foreach(@obj){
      $file=shell_escape(catfile($path,$_));
      if (-l $file) { next; }
      #get file flags as an octal value
      $fileflags=`stat -f "%Of" "$file"`;
      #remove trailing newlines
      chomp($fileflags);
      if (length($fileflags) < 8){ $fileflags = '0' x (8 - length($fileflags)) . $fileflags; }
      #chflags needs an octal value to set the file flags
      print FILE qq{chflags $fileflags "$file"\n};
    }

  foreach(@obj) {
    if((-d "$path/$_") && (!-l "$path/$_")) {
      &recdirs_ff("$path/$_");
    }
   }
   close DIR;
 }
}


sub shell_escape($){
    my $string = $_[0];
    $string =~ s/([\$"`\\])/\\$1/g;
    return $string;
}

# end of code ----------------------------------------------------------------------------------------------

