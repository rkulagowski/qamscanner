#!/usr/bin/perl -w
# Robert Kulagowski, 2011-11-09
# qamscanner.pl

# Scans through channels one at a time and obtains QAM and program
# information.  Assumes that there is at least one HDHomerun-Cable Card and
# one non-cable card HDHR.  The non-CC HDHR is used to tune the QAM freq and
# program that we received from the CC HDHR to create a .mpg file in the
# current directory.  You can use vlc {filename}.mpg to confirm that the QAM
# scan was accurate.

# Ensure that hdhomerun_config is somewhere in your path.  Make sure that
# you've run tv_grab_na_dd --configure at least once manually before you use
# this script.  Select the "digital" lineup when configuring tv_grab_na_dd
# to get maximum channel coverage.

# The program assumes that it will have exclusive access to the HDHR's, so
# don't run this while you're actually recording anything.

use strict;
use File::HomeDir;

my (@deviceid, @deviceip, @device_hwtype, @qam, @program, @hdhr_callsign);
my (@lineupinformation, @SD_callsign);
my $i=0;
my $hdhrcc_index=-1;
my $hdhrqam_index=0;
my $channel_number=0;
my $lineupid=0;

# Set $debugenabled to 0 to reduce output.
my $debugenabled=0;

# $create_mpg is used to create .mpg files using a non-cable card HDHR
# so that the user can check that they're not getting garbage.
# If you don't have a non-cable card HDHR, then set this to 0.
my $create_mpg=1;

# How long should we capture data for?
my $mpg_duration_seconds=10;

# Possibly parse wget http://ip.of.hdhr.cc/lineup.xml to determine the
# highest GuideNumber. For now, specify the start and end channels on the
# command line, or accept the default.  We're going to check every channel
# just in case.
my $start_channel = $ARGV[0] || "2";
my $end_channel = $ARGV[1] || "300";

print "\nScanning through tv_grab_na_dd.conf file for lineup id and channel map.\n";

# If you have more than 2000 channels, this isn't the program for you!  We
# want the array to have a known value in each element.  If the user has
# de-selected a particular channel, then we'll have *** as the call sign for
# that channel number, and that's ok, because we'll replace it later with
# whatever the provider is using as the call sign.

for (my $j=0; $j <=2000; $j++) { $SD_callsign[$j] = "***"; }

if (open LINEUP, File::HomeDir->my_home . "/.xmltv/tv_grab_na_dd.conf" ) {
  my $line;

# This next part is a line eater for now.  We don't do anything with the
# first three fields in the .conf file.
  $line = <LINEUP>;
  $line =~ /username:\s+(\S+)/;
  my $username = $1;  

  $line = <LINEUP>;
  $line =~ /password:\s+(\S+)/;
  my $password = $1;  

  $line = <LINEUP>;
  $line =~ /timeoffset:\s+(\S+)/;
  my $timeoffset = $1;  

  $line = <LINEUP>;
  $line =~ /lineup:\s+(\S+)/;
  $lineupid = $1;  

if ($debugenabled) { print "username is $username password is $password " .
    "timeoffset is $timeoffset lineupid is $lineupid\n"; }

  while (<LINEUP>) {
    chomp($line = $_);

    $line =~ /^channel:\s*(\d+)\s+(\w+)/;
    $SD_callsign[$1] = $2;

  } #end of the while loop
} #end of the Open
else {
  print "Fatal error: couldn't open tv_grab_na_dd.conf file.  Is it in the local directory?\n";
  exit;
}

if ($debugenabled) { print "lineup id is $lineupid\n"; }

# Find which HDHRs are on the network
my @output = `hdhomerun_config discover`;
chomp(@output); # removes newlines

print "\nDiscovering HDHRs\n";

foreach my $line(@output) {
if ($debugenabled) {  print "raw data from discover: $line\n"; } #prints the raw information

    ($deviceid[$i], $deviceip[$i]) = (split (/ /,$line))[2, 5];

    chomp($device_hwtype[$i] = `hdhomerun_config $deviceid[$i] get /sys/model`);

    print "device ID $deviceid[$i] has IP address $deviceip[$i] and is a $device_hwtype[$i]\n";

    if ($device_hwtype[$i] eq "hdhomerun3_cablecard") {
      $hdhrcc_index=$i;  #Keep track of which device is a HDHR-CC
    }  

    if ($device_hwtype[$i] eq "hdhomerun_atsc") {
      $hdhrqam_index=$i;  #Keep track of which device is a standard HDHR
    }  

    $i++;
}

if ($debugenabled) { 
  print "hdhrcc_index is $hdhrcc_index\nhdhrqam_index is$hdhrqam_index\n"; 
}

if ($hdhrcc_index == -1) {
  print "Fatal error:  did not find a HD Homerun with a cable card.\n";
  exit;
}

print "\nScanning channels $start_channel to $end_channel.\n";

for ($i=$start_channel; $i <= $end_channel; $i++) {
    print "Getting QAM data for channel $i\n";
    my $vchannel_set_status = `hdhomerun_config $deviceid[$hdhrcc_index] set /tuner2/vchannel $i`;
    chomp($vchannel_set_status);

# If we get anything back, that indicates an error, so print it out.
    if ($vchannel_set_status){ print "vcss is $vchannel_set_status\n"; }

    if ($vchannel_set_status !~ /ERROR/) { 
# Didn't get a tuning error (the channel number exists in the lineup), so
# keep going.

      sleep (1); #if you don't sleep, you don't get updated values for vstatus

      my $vchannel_get_vstatus = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner2/vstatus`;
      chomp($vchannel_get_vstatus);

if ($debugenabled) {  print "channel is $i vcgvs is:\n$vchannel_get_vstatus\n"; }

      if ($vchannel_get_vstatus =~ /auth=unspecified/) { 
      #auth=unspecified seems to mean that it's clear

        my $k = (split(/=/,$vchannel_get_vstatus))[2];
        $hdhr_callsign[$i] = substr $k,0,length($k)-5;

        # Replace any slash characters in the name of the channel with a hyphen so
        # that we get a valid filename later.
        $hdhr_callsign[$i] =~ s/\//-/g;

        # Remove trailing white space.  Some channels seem to have a lot of trailing
        # whitespace.
        $hdhr_callsign[$i] =~ s/\s+$//;

if ($debugenabled) {  print "channel name is $hdhr_callsign[$i]\n"; }

        chomp($qam[$i] = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner2/channel`);
        $qam[$i]=substr $qam[$i],4;  
        chomp($program[$i] = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner2/program`);
      } # done getting QAM information for a valid channel
    } # end of vchannel wasn't an error
} #end of main for loop.  We've scanned from $startchannel to $endchannel


# Dump the information gathered into an external file.
open MYFILE, ">", "$lineupid.qam.conf";

if ($create_mpg) {
  `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/channelmap us-cable`;
}

for (my $j = $start_channel; $j <= $end_channel; $j++) {
  if ($qam[$j]) {
    if ($SD_callsign[$j] eq "***" ) {
      print "\n\nDid not get a call sign from Schedules Direct, using provider-assigned call sign.";
      $SD_callsign[$j] = $hdhr_callsign[$j];    
    }
    if ($create_mpg) {
      print "\nCreating $mpg_duration_seconds second file for channel $j callsign $SD_callsign[$j]\n";
      my $tunestatus = `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/channel auto:$qam[$j]`;
      chomp($tunestatus);

      if ($tunestatus ne "ERROR: invalid channel") {

        `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/program $program[$j]`;

        # The files created will always have a 4-digit channel number, with
        # leading 0's so that the files sort correctly.
        $channel_number = sprintf "%04d",  $j;
        
# next routine is from http://arstechnica.com/civis/viewtopic.php?f=20&t=914012
if ($debugenabled) { print "About to start timeout\n"; }

        eval {
          local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
          alarm $mpg_duration_seconds;
          system ("hdhomerun_config", "$deviceid[$hdhrqam_index]", "save",
          "/tuner0", "channel$channel_number.$SD_callsign[$j].mpg");
          alarm 0;
        }


      } #end of the tunestatus routine.

      `killall hdhomerun_config`;

      my $filesizetest = "channel$channel_number.$SD_callsign[$j].mpg";
      # if the filesize is 0-bytes, then don't put it into the qamdump file; for whatever reason
      # the channel isn't tunable.
      if (-s $filesizetest) { print MYFILE "$SD_callsign[$j]:$qam[$j]:QAM_256:0:0:$program[$j]\n"; }
    } #end of the $create_mpg
    else { # We're not creating mpgs, but we should still dump the qamscan.
      print MYFILE "$SD_callsign[$j]:$qam[$j]:QAM_256:0:0:$program[$j]\n";    
    }
  }
}

# Kill any remaining strays.  Of course, if we didn't create MPGs, then
# there won't be any to kill.
if ($create_mpg) { `killall hdhomerun_config`; }

close (MYFILE);

print "\nDone.\n";
