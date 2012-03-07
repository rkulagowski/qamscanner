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

# Ensure that hdhomerun_config is somewhere in your path.

# The program assumes that it will have exclusive access to any HDHR's, so
# don't run this while you're actually recording anything.

use strict;
use Getopt::Long;
use WWW::Mechanize;

my $version = "2.00";
my $date="2012-03-05";

my (@deviceid, @deviceip, @device_hwtype, @qam, @program, @hdhr_callsign);
my (@lineupinformation, @SD_callsign, @xmlid);
my $i=0;
my $hdhrcc_index=-1;
my $hdhrqam_index=-1;
my $channel_number=0;
my $start_channel=1;
my $end_channel=1000;
my $lineupid=0;
my $username;
my $password;
my $timeoffset;
my $help;
my $zipcode="0";

# Extract the list of known device types
    my %device_type_hash = ('A' => 'Cable A lineup',
                            'B' => 'Cable B lineup',
                            'C' => 'Reserved',
                            'D' => 'Rebuild analog lineup',
                            'E' => 'Reserved',
                            'F' => 'D device cable ready and non-addressable for D',
                            'G' => 'Non-addressable converters and cable-ready sets',
                            'H' => 'Hamlin converter',
                            'I' => 'Jerrold impulse converter',
                            'J' => 'Jerrold converter',
                            'K' => 'Reserved',
                            'L' => 'Rebuild Digital',
                            'M' => 'Reserved',
                            'N' => 'Pioneer converter',
                            'O' => 'Oak converter',
                            'P' => 'Reserved',
                            'Q' => 'Reserved',
                            'R' => 'Cable-ready TV sets (non-rebuild)',
                            'S' => 'Reserved',
                            'T' => 'Tocom converter',
                            'U' => 'Cable-ready TV sets with Cable A',
                            'V' => 'Cable-ready TV sets with Cable B',
                            'W' => 'Scientific-Atlanta converter',
                            'X' => 'Digital (non-rebuild)',
                            'Y' => 'Reserved',
                            'Z' => 'Zenith converter',
                            ''  => 'Cable',
                           );

# auth=unspecified seems to mean that it's clear, but other users have
# stated that they needed to use "unknown" to get any channels. 
# "subscribed" is usually no good because it's a channel accessible via the
# Prime, but not necessarily clear QAM.  But, at least one user that has
# FIOS says that they need to use authtype subscribed, then check the
# streaminfo information from a non-CC HDHR to confirm that the channel isn't
# encrypted.  Furrfu!
my $authtype = "unspecified";

# Attempt to determine encryption status of channels using the streaminfo
# information obtained from an ATSC CC.  Required if user specifies
# "subscribed" as the auth type.  Patch and information from Sebastien
# Astie.
my $verify_type="streaminfo";
my $use_streaminfo=1;

# $create_mpg is used to create .mpg files using a non-cable card HDHR
# so that the user can check that they're not getting garbage.
# If you don't have a non-cable card HDHR, then set this to 0.
my $create_mpg=0;

# How long should we capture data for?
my $mpg_duration_seconds=10;

# Set $debugenabled to 0 to reduce output.
my $debugenabled=0;

GetOptions ('debug' => \$debugenabled,
            'authtype=s' => \$authtype,
            'verify=s' => \$verify_type,
            'duration=i' => \$mpg_duration_seconds,
            'start=i' => \$start_channel,
            'end=i' => \$end_channel,
            'zipcode=s' => \$zipcode,
            'help|?' => \$help);

if ($help) {
  print <<EOF;
qamscanner.pl v$version $date
Usage: qamscanner.pl [switches]

This script supports the following command line arguments.
No arguments will run a scan from channel 1 through 1000.

--debug                    Enable debug mode. Prints additional information
                           to assist in troubleshooting any issues.
                           
--start n                  Start channel. Default is channel 1.

--end n                    End channel. Default is channel 1000.

--verify streaminfo | mpg  Some cable providers have pseudo clear QAM channels.
                           (Primarily "On Demand") The script will try to
                           verify that the channel is actually available via
                           clear QAM by using an ATSC HDHomerun to either
                           read the encryption status directly from the QAM
                           table via streaminfo or by creating sample mpg
                           files.  Default is to use streaminfo.
                           
--duration                 If "--verify=mpg" is used, how long a sample
                           should be captured (in seconds).  Default is 10
                           seconds.
                           
--authtype                 {unspecified | unknown | subscribed}
                           Unless explicitly passed, the default is
                           "unspecified".  If the scan returns no valid
                           channels, re-run this program with "--authtype
                           unknown" If you are on FIOS, you may need to use
                           "--authtype subscribed" which will automatically
                           enable --verify streaminfo

--zipcode                  When grabbing the channel list from Schedules Direct,
                           you can supply your 5-digit zip code or
                           6-character postal code to get a list of cable TV
                           providers in your area, otherwise you'll be
                           prompted.  If you're specifying a Canadian postal
                           code, then use six consecutive characters, no
                           embedded spaces.
                           
--help                     This screen.

Bug reports to qam-info\@schedulesdirect.org  Include the .conf file and the
complete output when the script is run with --debug

EOF
  exit;
}

  if (($start_channel < 1) || ($end_channel < $start_channel) 
    || ($start_channel > $end_channel) || ($end_channel > 9999)) {

    print 
    "Invalid channel combination. Start channel must be greater than 0\n" .
    "and less than end channel. End channel must be greater than start\n" .
    "channel and less than 9999.\n";
    exit;
  }

if ($verify_type eq "mpg") {
  $use_streaminfo = 0;
  $create_mpg = 1;
}

if ($authtype eq "subscribed") {
  $use_streaminfo = 1;
  $create_mpg = 0;
}

# Find which HDHRs are on the network
my @output = `hdhomerun_config discover`;
chomp(@output); # removes newlines

print "\nDiscovering HD Homeruns on the network.\n";

foreach my $line(@output) {
if ($debugenabled) {  print "raw data from discover: $line\n"; } #prints the raw information

    ($deviceid[$i], $deviceip[$i]) = (split (/ /,$line))[2, 5];

    chomp($device_hwtype[$i] = `hdhomerun_config $deviceid[$i] get /sys/model`);

    print "device ID $deviceid[$i] has IP address $deviceip[$i] and is a $device_hwtype[$i]\n";

    if ($device_hwtype[$i] eq "hdhomerun3_cablecard") {
      $hdhrcc_index=$i;  #Keep track of which device is a HDHR-CC
    }  

    if ($device_hwtype[$i] =~ "_atsc" && ($create_mpg || $use_streaminfo)) {
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
  print "Fatal error: did not find a HD Homerun with a cable card.\n";
  exit;
}

if ($hdhrqam_index == -1 && $authtype eq "subscribed") {
  print
"\nFatal error: Using authtype \"subscribed\" without verifying resulting\n" .
"QAM table using a non-Cable Card HDHR is not supported.\n" .
"Did not find a non-CC HDHR connected to the coax.\n";
exit;
}

# Yes, goto sometimes considered evil. But not always.
START:
if ($zipcode eq "0")
{
  print "\nPlease enter your zip code / postal code to download lineups:\n";
  chomp ($zipcode = <STDIN>);
}

$zipcode = uc($zipcode);

unless ($zipcode =~ /^\d{5}$/ or $zipcode =~ /^[A-Z0-9]{6}$/)
{
  print "Invalid zip code specified. Must be 5 digits for U.S., 6 characters for Canada.\n";
  $zipcode = "0";
  goto START;
}

my $m = WWW::Mechanize->new();

$m->get("http://rkulagow.schedulesdirect.org/process.php?command=get&p1=headend&p2=$zipcode");
$m->save_content("available_headends.txt");

open (my $fh, "<","available_headends.txt") or 
  die "Fatal error: could not open available.txt: $!\n";
  my $row=0;
  my @he;
  while (my $line = <$fh>) {
    chomp($line);
    # Skip the ones that aren't cable lineups.
    next if ($line =~ /^DISH/);
    next if ($line =~ /^ECHOST/);
    next if ($line =~ /^DITV/);
    next if ($line =~ /^4DTV/);
    next if ($line =~ /^AFN/);
    next if ($line =~ /^C-BAND/);
    next if ($line =~ /^GLOBCST/);
    next if ($line =~ /^SKYANGL/);
    next if ($line =~ /Name:Antenna/);
    # lineup identifier, name, location, url
    ($he[$row][0],$he[$row][1],$he[$row][2],$he[$row][3]) = split(/\|/,$line);
    $row++;
  } #end of the while loop
  $row--;
  close $fh;

  print "\n";

for my $j (0 .. $row)
{
  print "$j. $he[$j][1], $he[$j][2] ($he[$j][0])\n";
}
print "\nEnter the number of your lineup, 'Q' to exit, 'A' to try again: ";

my $response;
chomp ($response = <STDIN>);
$response = uc($response);

if ($response eq "Q")
{
  exit;
}

if ($response eq "A")
{
  $zipcode = "0";
  goto START;
}

$response *= 1; # Numerify it.

if ($response < 0 or $response > $row)
{
  print "Invalid choice.\n";
  $zipcode = "0";
  goto START;
}

print "\nDownloading lineup information.\n";

$lineupid = $he[$response][0];

$m->get($he[$response][3]);
$m->save_content("$he[$response][0].txt.gz");

print "Unzipping file.\n\n";
system("gunzip --force $he[$response][0].txt.gz");

open ($fh, "<", "$he[$response][0].txt") or 
  die "Fatal error: could not open $he[$response][0].txt: $!\n";

  my @headend_lineup = <$fh>;
  chomp(@headend_lineup);
  close $fh;

  $row = 0;
  my $line = -1; # Deliberately start less than 0 to catch the first entry.
  my @device_type;

  foreach my $elem (@headend_lineup)
  {
    $line++;  
    next unless $elem =~ /^Name/;
    $elem =~ /devicetype:(.?)|fulldevicename:(\w)/;
    $device_type[$row][0] = $1; # The device type
    $device_type[$row][1] = $line; # store the line number as the second element.

    if ($device_type[$row][0] eq "|")
    {
      $device_type[$row][0]="";
    }
    $row++;
  }
  $row--;

if ($row > 0) # More than one device type was found.
{
  print "The following lineups are available on this headend:\n";
  for my $j (0 .. $row)
  {
    print "$j. $device_type_hash{$device_type[$j][0]}\n";
  }

  print "Enter the number of the lineup you are scanning: ";
  chomp ($response = <STDIN>);
  $response = uc($response);

  if ($response eq "Q")
  {
    exit;
  }

  $response *= 1; # Numerify it.

  if ($response < 0 or $response > $row)
  {
    print "Invalid choice.\n";
    $zipcode = "0";
    goto START;
  }
}
else
{
  $response = 0;
}

# If the user selects the last entry, then create a fake so that we look
# through the end of the file.
if ($response == $row)
{
  $device_type[$row+1][1] = scalar (@headend_lineup);
}

# If you have more than 3000 channels, this isn't the program for you!  We
# want the arrays to have a known value in each element.  If the user has
# de-selected a particular channel, then we'll have *** as the call sign for
# that channel number, and that's ok, because we'll replace it later with
# whatever the provider is using as the call sign.
for my $j (0 .. 3000) { 
  $SD_callsign[$j] = "***"; 
  $xmlid[$j] = "0"; 
}

# Start at the first line after the "Name" line, end one line before the next "Name" line.
for my $elem ($device_type[$response][1]+1 .. ($device_type[$response+1][1])-1)
{
  my $line = $headend_lineup[$elem];
  $line =~ /^channel:(\d+) callsign:(\w+) stationid:(\d+)/;
  $SD_callsign[$1] = $2;
  $xmlid[$1] = $3;
}

print "\nScanning channels $start_channel to $end_channel.\n";

for ($i=$start_channel; $i <= $end_channel; $i++) {
    print "Getting QAM data for channel $i\n";
    my $vchannel_set_status = `hdhomerun_config $deviceid[$hdhrcc_index] set /tuner0/vchannel $i`;
    chomp($vchannel_set_status);

# If we get anything back, that indicates an error, so print it out.
    if ($vchannel_set_status) { 
      print "vcss is $vchannel_set_status\n"; 
    }

    if ($vchannel_set_status !~ /ERROR/) { 
# Didn't get a tuning error (the channel number exists in the lineup), so
# keep going.

      sleep (3); #if you don't sleep, you don't get updated values for vstatus

      my $vchannel_get_vstatus = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner0/vstatus`;
      chomp($vchannel_get_vstatus);

if ($debugenabled) {  print "channel is $i vcgvs is:\n$vchannel_get_vstatus\n"; }

      if ($vchannel_get_vstatus =~ /auth=$authtype/) {

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

        chomp($qam[$i] = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner0/channel`);
        $qam[$i]=substr $qam[$i],4;  
        chomp($program[$i] = `hdhomerun_config $deviceid[$hdhrcc_index] get /tuner0/program`);
      } # done getting QAM information for a valid channel
    } # end of vchannel wasn't an error
} #end of main for loop.  We've scanned from $startchannel to $endchannel

# If we don't have a QAM device, then don't create the .mpg files or check
# the qam streaminfo for encrypted status.

if ($hdhrqam_index == -1) {
  $create_mpg = 0;
  $use_streaminfo = 0;
}

# Dump the information gathered into an external file.  Normalize the
# lineupid so that we get rid of anything that's not alphanumeric.

$lineupid =~ s/\W//;
open MYFILE, ">", "$lineupid.qam.conf";
print MYFILE "\n# qamscanner.pl v$version $date $lineupid:$device_type[$response][0]".
" $zipcode start:$start_channel" .
" end:$end_channel authtype:$authtype streaminfo:$use_streaminfo\n";

if ($create_mpg || $use_streaminfo) {
  `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/channelmap us-cable`;
}

for (my $j = $start_channel; $j <= $end_channel; $j++) {
  if ($qam[$j]) {
    print "\nChannel $j: ";
    if ($SD_callsign[$j] eq "***") {
      print "Did not get a call sign from Schedules Direct";
      if ($hdhr_callsign[$j] ne "***") {
        print ", using provider-assigned call sign.\n";
      }
      else {
        print " and provider did not supply call sign either, using ***\n";
      }
      $SD_callsign[$j] = $hdhr_callsign[$j];
    }
    if ($create_mpg || $use_streaminfo) {
      my $tunestatus = `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/channel auto:$qam[$j]`;
      chomp($tunestatus);
      my $channelisclear = 0;
      if ($tunestatus ne "ERROR: invalid channel") {
        `hdhomerun_config $deviceid[$hdhrqam_index] set /tuner0/program $program[$j]`;
        if ($use_streaminfo) {
          print " Getting encryption status for channel via streaminfo.";
	  #we need to sleep so that the hdhr can tune itself	
	  sleep(3);
	  my @streaminfo = `hdhomerun_config $deviceid[$hdhrqam_index] get /tuner0/streaminfo`;
	  my $len = $#streaminfo -1; #the last value in the streaminfo we do not care about (tsid).
          for (my $idx = 0; $idx < $len; $idx++) {
            #check if the string starts with the programid
	    chomp($streaminfo[$idx]);
            if(($streaminfo[$idx] =~ m/^$program[$j]:/) && ($streaminfo[$idx] !~ m/(encrypted)/ )) {
              $channelisclear = 1;
              last;
            }
	  }
        } #end of $use_streaminfo
        elsif ($create_mpg) {
          print "\nCreating $mpg_duration_seconds second file for channel $j callsign $SD_callsign[$j]\n";
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
          };
          my $filesizetest = "channel$channel_number.$SD_callsign[$j].mpg";
          # if the filesize is 0-bytes, then don't put it into the qamdump file; for whatever reason
          # the channel isn't tunable.
	  if (-s $filesizetest) {
            $channelisclear = 1;
          }
        }  #end of $create_mpg
        
        # Also, we're going to hijack the VID / AID field in channels.conf to
        # store the channel number and the XMLID from Schedules Direct.  Those
        # fields aren't used by MythTV as far as I can tell.  This will help
        # correlate data between users if we get an odd provider-assigned call
        # sign and need to figure out the "real" call sign.
        if ($channelisclear) {
          print MYFILE "$SD_callsign[$j]:$qam[$j]:QAM_256:$j:$xmlid[$j]:$program[$j]\n";
        }
      } #end of tunestatus
    } #end of $create_mpg || $use_streaminfo
    else {
     # We're not creating mpgs or using streaminfo, but we should still dump the qamscan.
      print MYFILE "$SD_callsign[$j]:$qam[$j]:QAM_256:$j:$xmlid[$j]:$program[$j]\n";
    }
  } #end of $qam[$j]  
}#end of for loop     

# Kill any remaining strays.  Of course, if we didn't create MPGs, then
# there won't be any to kill.
if ($create_mpg || $use_streaminfo) { `killall hdhomerun_config`; }

close (MYFILE);

print "\nDone.\n";

print "Please email the .conf file to qam-info\@schedulesdirect.org\n";
exit;
