#!/usr/bin/perl -w
# Robert Kulagowski
# qam-info@schedulesdirect.org
# qamscanner.pl

# Scans through channels one at a time and obtains QAM and program
# information.  You must have at least one HDHomerun-Cable Card available on
# the network.

# If you also have at least one non-cable card HDHR connected to your coax,
# it can be used to tune the QAM frequency and program that we received from
# the CC HDHR to create a .mpg file in the current directory.  You can use
# vlc {filename}.mpg to confirm that the QAM scan was accurate.

# Ensure that hdhomerun_config is somewhere in your path.  You must run
# tv_grab_na_dd --configure at least once manually before you use this
# script.  Select the "digital" lineup when configuring tv_grab_na_dd to get
# maximum channel coverage.

# The program assumes that it will have exclusive access to any HDHR's, so
# don't run this while you're actually recording anything.

use strict;
use File::HomeDir;
use Getopt::Long;

my $version = "1.04";
my $date="2011-12-21";

my (@deviceid, @deviceip, @device_hwtype, @qam, @program, @hdhr_callsign);
my (@lineupinformation, @SD_callsign, @xmlid);
my $i=0;
my $hdhrcc_index=-1;
my $hdhrqam_index=-1;
my $channel_number=0;
my $start_channel=2;
my $end_channel=300;
my $lineupid=0;
my $username;
my $password;
my $timeoffset;
my $help;

# Set $debugenabled to 0 to reduce output.
my $debugenabled=0;

# $create_mpg is used to create .mpg files using a non-cable card HDHR
# so that the user can check that they're not getting garbage.
# If you don't have a non-cable card HDHR, then set this to 0.
my $create_mpg=0;

# How long should we capture data for?
my $mpg_duration_seconds=10;

GetOptions ('debug' => \$debugenabled, 
            'create-mpg' => \$create_mpg,
            'duration=i' => \$mpg_duration_seconds,
            'start=i' => \$start_channel,
            'end=i' => \$end_channel,
            'help|?' => \$help);

if ($help) {
  print "\nqamscanner.pl v$version $date\n" .
        "This script supports the following command line arguments." .
        "\nNo arguments will run a scan from channel 2 through 300.\n" .
        "\n--debug      Enable debug mode.  Prints additional information " .
        "\n             to assist with any issues." .
        "\n--create-mpg If you have an ATSC HDHR on your network, it will " .
        "\n             be used to create sample .mpg files to verify channel " .
        "\n             information. Default is false." .
        "\n--duration   If you're creating .mpg files, how long should they " .
        "\n             be (in seconds). Default is 10 seconds." .
        "\n--start      Start channel.  Default is channel 2." .
        "\n--end        End channel.  Default is channel 300." .
        "\n--help       This screen.\n" .
        "\nBug reports to qam-info\@schedulesdirect.org  Include the .conf " .
        "\nfile and the complete output when the script is run with " .
        "\n--debug\n\n";
  exit;
}

  if (($start_channel < 1) || ($end_channel < $start_channel) 
    || ($start_channel > $end_channel) || ($end_channel > 9999)) {

    print 
    "Invalid channel combination. Start channel must be 1 or greater\n" .
    "and less than end channel.  End channel must be greater than start\n" .
    "channel and less than 9999.\n";
    exit;
  }

print "\nScanning through tv_grab_na_dd.conf file for lineup id and channel map.\n";

# If you have more than 2000 channels, this isn't the program for you!  We
# want the arrays to have a known value in each element.  If the user has
# de-selected a particular channel, then we'll have *** as the call sign for
# that channel number, and that's ok, because we'll replace it later with
# whatever the provider is using as the call sign.
for my $j (0 .. 2000) { 
  $SD_callsign[$j] = "***"; 
  $xmlid[$j] = "0"; 
}

open LINEUP, "<", File::HomeDir->my_home . "/.xmltv/tv_grab_na_dd.conf" or 
  die "Fatal error: couldn't open tv_grab_na_dd.conf file.  Have you run \"tv_grab_na_dd --configure\" first?\n";

  while (my $line = <LINEUP>) {
    chomp($line);

    if ($line =~ /username:\s+(\S+)/) {
      $username = $1;
    }

    if ($line =~ /password:\s+(\S+)/) {
      $password = $1;
    }

    if ($line =~ /timeoffset:\s+(\S+)/) {
      $timeoffset = $1;
    }
    
    if ($line =~ /lineup:\s+(\S+)/) {
      $lineupid = $1;  
    }

    if ($line =~ /^channel:\s*(\d+)\s+(\w+)/) {
      $SD_callsign[$1] = $2;
    }
  } #end of the while loop

close LINEUP;

if ($debugenabled) { print "username is $username\npassword is $password\n" .
    "timeoffset is $timeoffset\nlineupid is $lineupid\n"; }

# Pull in the station mapping.  We do this part to get the XMLIDs.
print "\nGetting one day of data from Schedules Direct to determine station mapping.\n";
`tv_grab_na_dd --days 1 --dd-data lineup.xml --download-only`;

print "\nScanning through downloaded xml file for xmlid's.\n";

if (open LINEUP, "lineup.xml" ) {
  while (<LINEUP>) {
    my $line = $_;
    if ( $line =~ /^<map station='(\d+)' channel='(\d+)'/ ) {
      $xmlid[ $2 ] = $1;
    }
  }
}
else {
  print "\nFatal error: Couldn't get lineup.\n";
  exit;
}

close LINEUP;

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

    if ($device_hwtype[$i] eq "hdhomerun_atsc" && $create_mpg) {
      print "Is this device connected to an Antenna, or is it connected to your Cable system? (A/C/Skip) ";
      my $response;
      chomp ($response = <STDIN>);
      $response = uc($response);
      if ($response eq "C") { 
        $hdhrqam_index=$i;  #Keep track of which device is connected to coax - can't do a QAM scan on Antenna systems.
      }
    }  

    $i++;
}

if ($debugenabled) { 
  print "hdhrcc_index is $hdhrcc_index\nhdhrqam_index is $hdhrqam_index\n"; 
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
      # auth=unspecified seems to mean that it's clear.

        my $k = (split(/=/,$vchannel_get_vstatus))[2];
        $hdhr_callsign[$i] = substr $k,0,length($k)-5;

        # Replace any slash characters in the name of the channel with a
        # hyphen so that we get a valid filename later.
        $hdhr_callsign[$i] =~ s/\//-/g;

        # Remove trailing white space.  Some channels seem to have a lot of
        # trailing whitespace.
        $hdhr_callsign[$i] =~ s/\s+$//;

        # Sometimes the provider doesn't supply a callsign.
        if (!$hdhr_callsign[$i]) { $hdhr_callsign[$i] = "***"; }

if ($debugenabled) {  print "channel name is $hdhr_callsign[$i]\n"; }

        chomp($qam[$i] = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner2/channel`);
        $qam[$i]=substr $qam[$i],4;  
        chomp($program[$i] = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner2/program`);
      } # done getting QAM information for a valid channel
    } # end of vchannel wasn't an error
} #end of main for loop.  We've scanned from $startchannel to $endchannel

# If we don't have a QAM device, then don't create the .mpg files.
if ($hdhrqam_index == -1) {
  $create_mpg = 0;
}

# Dump the information gathered into an external file.  Normalize the
# lineupid so that we get rid of anything that's not alphanumeric

$lineupid =~ s/\W//;
open MYFILE, ">", "$lineupid.qam.conf";
print MYFILE "\n# qamscanner.pl v$version $date $lineupid\n";

if ($create_mpg) {
  `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/channelmap us-cable`;
}

for (my $j = $start_channel; $j <= $end_channel; $j++) {
  if ($qam[$j]) {
    if ($SD_callsign[$j] eq "***") {
      print "\n\nDid not get a call sign from Schedules Direct";
      if ($hdhr_callsign[$j] ne "***") {
        print ", using provider-assigned call sign.";
      }
      else {
        print " and provider did not supply call sign either, using ***";
      }
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

      # Also, we're going to hijack the VID / AID field in channels.conf to
      # store the channel number and the XMLID from Schedules Direct.  Those
      # fields aren't used by MythTV as far as I can tell.  This will help
      # correlate data between users if we get an odd provider-assigned call
      # sign and need to figure out the "real" call sign.
      
      if (-s $filesizetest) { print MYFILE "$SD_callsign[$j]:$qam[$j]:QAM_256:$j:$xmlid[$j]:$program[$j]\n"; }
    } #end of the $create_mpg
    else { # We're not creating mpgs, but we should still dump the qamscan.
      print MYFILE "$SD_callsign[$j]:$qam[$j]:QAM_256:$j:$xmlid[$j]:$program[$j]\n";    
    }
  }
}

# Kill any remaining strays.  Of course, if we didn't create MPGs, then
# there won't be any to kill.
if ($create_mpg) { `killall hdhomerun_config`; }

close (MYFILE);

print "\nDone.\n";

print "Please email the .conf file to qam-info\@schedulesdirect.org\n";
