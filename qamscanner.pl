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

# Ensure that hdhomerun_config is somewhere in your path. You must have
# "unzip" installed.

# The program assumes that it will have exclusive access to any HDHR's, so
# don't run this while you're actually recording anything.

use strict;
use Getopt::Long;
use WWW::Mechanize;
use POSIX qw(strftime);
use JSON;

# If you're not insane like Ubuntu (https://bugs.launchpad.net/ubuntu/+source/libdigest-sha1-perl/+bug/993648)
# you probably want
# use Digest::SHA1 qw(sha1_hex);
use Digest::SHA qw(sha1_hex);

use Data::Dumper;

my $version  = "3.04";
my $date     = "2013-09-16";
my $randhash = "";

my ( @deviceID, @deviceIP, @deviceHWType );
my ( @he, @channel );
my $api           = 0;
my $i             = 0;
my $hdhrCCIndex   = -1;
my $hdhrQAMIndex  = -1;
my $channelNumber = 0;
my $startChannel  = 1;
my $endChannel    = 1000;
my $lineupID      = "";
my $ccDevice      = "";
my $ccTuner       = 99;     # Set bogus high value.
my $qamDevice     = "";
my $qamTuner      = 99;
my $username      = "";
my $password      = "";
my $vlcIPaddress  = "127.0.0.1";
my $help;
my $zipcode = "0";
my $response;
my $m = WWW::Mechanize->new( agent => "qamscanner v$version/$date" );
my $useBetaServer = 0;
my $baseurl;
my %ch;

# Keep track of which QAM frequency we've already looked at.
my %qamAlreadyScanned;

# If we find an unknown program during the scan, take a second look later.
my %unknownCallsign;

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
my $verifyType = "streaminfo";

# verifyType of "mpg" is used to create .mpg files using a non-cable card HDHR
# so that the user can check that they're not getting garbage.

# How long should we capture data for?
my $mpgDurationSeconds = 10;

# Set $debugEnabled to 0 to reduce output.
my $debugEnabled = 0;

GetOptions(
    'debug'       => \$debugEnabled,
    'authtype=s'  => \$authtype,
    'verify=s'    => \$verifyType,
    'duration=i'  => \$mpgDurationSeconds,
    'start=i'     => \$startChannel,
    'end=i'       => \$endChannel,
    'zipcode=s'   => \$zipcode,
    'ccdevice=s'  => \$ccDevice,
    'cctuner=i'   => \$ccTuner,
    'qamdevice=s' => \$qamDevice,
    'qamtuner=i'  => \$qamTuner,
    'lineupID=s'  => \$lineupID,
    'username=s'  => \$username,
    'password=s'  => \$password,
    'beta'        => \$useBetaServer,
    'vlc=s'       => \$vlcIPaddress,
    'help|?'      => \$help
);

############## Start of main program

if ($useBetaServer)
{
    # Test server. Things may be broken there.
    $baseurl = "http://23.21.174.111";
    print "Using beta server.\n";
    $api = 20130709;
}
else
{
    $baseurl = "https://data2.schedulesdirect.org";
    print "Using production server.\n";
    $api = 20130512;
}

if ($help)
{
    print <<EOF;
qamscanner.pl v$version $date
Usage: qamscanner.pl [switches]

This script supports the following command line arguments.
No arguments will run a scan from channel 1 through 1000.

--debug                    Enable debug mode. Prints additional information
                           to assist in troubleshooting any issues.
                           
--start=n                  Start channel. Default is channel 1.

--end=n                    End channel. Default is channel 1000.

--verify= streaminfo | mpg Some cable providers have pseudo clear QAM channels.
                           (Primarily "On Demand") The script will try to
                           verify that the channel is actually available via
                           clear QAM by using an ATSC HDHomerun to either
                           read the encryption status directly from the QAM
                           table via streaminfo or by creating sample mpg
                           files.  Default is to use streaminfo.

--duration                 If "--verify=mpg" is used, how long a sample
                           should be captured (in seconds).  Default is 10
                           seconds.

--vlc= IP.add.re.ss        VLC can be used to confirm unknown channels. Specify
                           the IP address of the host running VLC. Default is
                           "127.0.0.1"
                           
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


The following should only be used once you're familiar with the program.
--ccdevice                 Specify which cable card device will be used for the
                           scan.
--cctuner                  Specify which tuner will be used on the cable
                           card HDHR. Defaults to tuner 0.

--qamdevice                Specify which non-CC device is used to confirm the
                           results of the scan.
--qamtuner                 Specify which tuner will be used on the non-CC HDHR.
                           Automatically configures that tuner for coax, so
                           ensure that it's not connected to an antenna.
                           Defaults to tuner 0.

--lineupID                 Your headend identifier.

--help                     This screen.

Bug reports to qam-info\@schedulesdirect.org  Include the .txt file and the
complete output when the script is run with --debug

EOF
    exit;
}

if (   ( $startChannel < 1 )
    || ( $endChannel < $startChannel )
    || ( $startChannel > $endChannel )
    || ( $endChannel > 9999 ) )
{

    print "Invalid channel combination. Start channel must be greater than 0\n";
    print "and less than end channel. End channel must be greater than start\n";
    print "channel and less than 9999.\n";
    exit;
}

if (    $ccDevice eq ""
    and $qamDevice eq ""
    and $ccTuner == 99
    and $qamTuner == 99 )
{

    # User didn't specify anything, so we have to run the discover routine.
    &discoverHDHR();
    $ccTuner  = 0;
    $qamTuner = 0;
}
else
{
    if ( $ccTuner == 99 )  { $ccTuner  = 0; }
    if ( $qamTuner == 99 ) { $qamTuner = 0; }
}

if ( $username eq "" )
{
    print "Enter your Schedules Direct username: ";
    chomp( $username = <STDIN> );
}

if ( $password eq "" )
{
    print "Enter password: ";
    chomp( $password = <STDIN> );
}

print "Retrieving randhash from Schedules Direct.\n";
$randhash = &login_to_sd( $username, $password );

# Yes, goto sometimes considered evil. But not always.
START:
if ( $zipcode eq "0" )
{
    print "\nPlease enter your zip code / postal code to download lineups:\n";
    chomp( $zipcode = <STDIN> );
}

$zipcode = uc($zipcode);

unless ( $zipcode =~ /^\d{5}$/ or $zipcode =~ /^[A-Z0-9]{6}$/ )
{
    print "Invalid zip code specified. Must be 5 digits for U.S., 6 characters for Canada.\n";
    $zipcode = "0";
    goto START;
}

$response = &get_headends($randhash, $zipcode );

my $row = 0;

foreach my $e ( @{ $response->{"data"} } )
{
    $he[$row]->{'headend'}  = $e->{headend};
    $he[$row]->{'name'}     = $e->{name};
    $he[$row]->{'location'} = $e->{location};
    $row++;
}

$row--;

print "\n";

if ( $lineupID eq "" )    # if the lineupID wasn't passed as a parameter, ask the user
{
    for my $j ( 0 .. $row )
    {
        print "$j. $he[$j]->{'name'}, $he[$j]->{'location'} ($he[$j]->{'headend'})\n";
    }
    print "\nEnter the number of your lineup, 'Q' to exit, 'A' to try again: ";

    chomp( $response = <STDIN> );
    $response = uc($response);

    if ( $response eq "Q" )
    {
        exit;
    }

    if ( $response eq "A" )
    {
        $zipcode  = "0";
        $lineupID = "";
        goto START;
    }

    $response *= 1;    # Numerify it.

    if ( $response < 0 or $response > $row )
    {
        print "Invalid choice.\n";
        $zipcode  = "0";
        $lineupID = "";
        goto START;
    }

    $lineupID = $he[$response]->{'headend'};
}
else                   # we received a lineupID
{
    for my $elem ( 0 .. $row )
    {
        if ( $he[$elem]->{'headend'} eq $lineupID )
        {
            $response = $elem;
        }
    }

}

print "Do you need to add this lineup to your JSON-service beta account? (Y/n)\n";
print "NOTE: This is not the same as your existing SchedulesDirect XML service account.\n";
chomp( $response = <STDIN> );
$response = uc($response);

if ( $response ne "N" )
{
	&add_or_delete_headend($randhash, $lineupID, "add");	
}

print "\nDownloading lineup information.\n";

&download_lineup( $randhash, $lineupID );

print "Unzipping file.\n\n";
system("unzip -o $lineupID.headends.json.zip");

open( my $fh, "<", "$lineupID.json.txt" )
  or die "Fatal error: could not open $lineupID.json.txt: $!\n";

my $headend_lineup = <$fh>;
chomp($headend_lineup);
close $fh;

$response = JSON->new->utf8->decode($headend_lineup);

# If you have more than 3000 channels, this isn't the program for you!  We
# want the arrays to have a known value in each element.  If the user has
# de-selected a particular channel, then we'll have *** as the call sign for
# that channel number, and that's ok, because we'll replace it later with
# whatever the provider is using as the call sign.
for my $j ( 0 .. 3000 )
{
    $channel[$j]->{"stationid"} = 0;
    $channel[$j]->{"callsign"}  = "***";
}

foreach my $e ( @{ $response->{"X"}->{"map"} } )
{
    $channel[ $e->{channel} + 0 ]->{stationid} = $e->{stationID};
    if ($debugEnabled)
    {
        print "stationID:" . $e->{stationID} . " channel:" . $e->{channel} . "\n";
    }
}

my %stationData;

foreach my $e ( @{ $response->{"stationID"} } )
{
    $stationData{ $e->{stationID} }->{callsign} = $e->{callsign};
    $stationData{ $e->{stationID} }->{name}     = $e->{name};
}

print "\nScanning channels $startChannel to $endChannel.\n";

for $i ( $startChannel .. $endChannel )
{
    print "Getting QAM data for channel $i\n";
    my $vchannelSetStatus = `hdhomerun_config $ccDevice set /tuner$ccTuner/vchannel $i`;
    chomp($vchannelSetStatus);

    next if ( $vchannelSetStatus =~ /ERROR/ );

    # Didn't get a tuning error (the channel number exists in the lineup), so
    # keep going.

    sleep(3);    #if you don't sleep, you don't get updated values for vstatus

    my $vchannel_get_status = `hdhomerun_config $ccDevice get /tuner$ccTuner/status`;
    chomp($vchannel_get_status);
    $vchannel_get_status =~ /ch=qam:(\d*)/;

    if ($debugEnabled)
    {
        print "channel is $i vcgvs is:\n$vchannel_get_status\n";
        print "qam frequency is $1\n";
    }

    my $qa = $1;

    # To avoid looking at the same qam frequencies over and over, keep track if we've already seen this one.
    next if ( exists $qamAlreadyScanned{$qa} );

    $qamAlreadyScanned{$qa} = 1;

    my $vchannel_get_vstatus = `hdhomerun_config $ccDevice get /tuner$ccTuner/vstatus`;
    chomp($vchannel_get_vstatus);

    sleep(3);

    if ($debugEnabled)
    {
        my $streamInfo = `hdhomerun_config $ccDevice get /tuner$ccTuner/streaminfo`;
        print "streaminfo is\n$streamInfo\n";
        sleep(3);
    }

    my @streamInfo = `hdhomerun_config $ccDevice get /tuner$ccTuner/streaminfo`;
    chomp(@streamInfo);

    foreach my $e (@streamInfo)
    {
        if ($debugEnabled) { print "e is $e\nlength of e is " . length($e) . "\n"; }
        next if $e =~ /(encrypted|control|internet|tsid|none)/;
        next if ( length($e) == 0 );

        $e =~ /^(\d+): (\d+)/;

        if ( $2 == 0 )
        {
            print "Did not get callsign. qamfreq:$qa program:$1\n";
            $unknownCallsign{"$qa+$1"} = 1;
        }
        else
        {

            $e =~ /^(\d+): (\d+) (.+)/;

            if ( ( defined $1 ) && ( defined $2 ) && ( defined $3 ) )
            {
                print "Found qamprogram:$1 virtual channel:$2 callsign from cable operator:$3\n";
                $ch{$2}->{qam}     = $qa;
                $ch{$2}->{program} = $1;
                if ( $2 > 0 )
                {
                    $ch{$2}->{stationID}     = $channel[$2]->{stationid};
                    $ch{$2}->{cableCallsign} = $3;
                    $ch{$2}->{cableCallsign} =~ s/\//-/g;
                }
            }
        }

    }

}    #end of main for loop.  We've scanned from $startchannel to $endchannel

# If we don't have a QAM device, then don't create the .mpg files or check
# the qam streaminfo for encrypted status.
if ( $qamDevice eq "" )
{
    $verifyType = "none";
}

# Dump the information gathered into an external file.  Normalize the
# lineupID so that we get rid of anything that's not alphanumeric.
$lineupID =~ s/\W//;

open( $fh, ">", strftime "%Y%m%d" . "-$lineupID.$verifyType.qam.txt", localtime );
print $fh "\n# qamscanner.pl v$version $date lineupID:$lineupID" . " $zipcode start:$startChannel" . " end:$endChannel authtype:$authtype verifytype:$verifyType\n";

if ( $verifyType ne "none" )
{
    `hdhomerun_config $qamDevice set /tuner$qamTuner/channelmap us-cable`;
}

#foreach my $e ( sort keys %ch )
foreach my $e ( sort { $a <=> $b } keys %ch )
{
    print $fh "$e|qamfreq:$ch{$e}->{qam}|qamprogram:$ch{$e}->{program}|stationID:$ch{$e}->{stationID}|cableCallsign:$ch{$e}->{cableCallsign}\n";
}

print $fh "---\n";

`hdhomerun_config $qamDevice  set /tuner$qamTuner/channelmap us-cable`;

foreach $i ( sort { $a <=> $b } keys %ch )
{
    next if !( defined $ch{$i}->{cableCallsign} );
    print "\nChannel $i: $ch{$i}->{cableCallsign}\n";
    if ( $ch{$i}->{cableCallsign} eq "***" )
    {
        print "Did not get a call sign from Schedules Direct";
    }

    print "Setting device $qamDevice to qam freq $ch{$i}->{qam}\n";
    my $tunestatus = `hdhomerun_config $qamDevice set /tuner$qamTuner/channel auto:$ch{$i}->{qam}`;
    sleep(5);
    chomp($tunestatus);
    my $channelisclear = 0;
    next if ( $tunestatus eq "ERROR: invalid channel" );

    print "Setting device $qamDevice to program $ch{$i}->{program}\n";
    sleep(5);
    `hdhomerun_config $qamDevice set /tuner$qamTuner/program $ch{$i}->{program}`;
    sleep(5);

    if ( $verifyType eq "streaminfo" )
    {
        print " Getting encryption status for channel via streaminfo.\n";

        #we need to sleep so that the hdhr can tune itself
        sleep(3);
        my @streamInfo = `hdhomerun_config $qamDevice get /tuner$qamTuner/streaminfo`;
        chomp(@streamInfo);

        foreach my $e (@streamInfo)
        {
            if ($debugEnabled) { print "e is $e\n"; }
            next if $e =~ /(encrypted|control|internet|tsid)/;
            $channelisclear = 1;
            last;
        }
    }

    if ( $verifyType eq "mpg" )
    {
        print "\nCreating $mpgDurationSeconds second file for channel $i callsign " . $ch{$i}->{cableCallsign} . "\n";

        # The files created will always have a 4-digit channel number, with
        # leading 0's so that the files sort correctly.
        $channelNumber = sprintf "%04d", $i;

        # next routine is from http://arstechnica.com/civis/viewtopic.php?f=20&t=914012
        my $fileName = "channel$channelNumber.$ch{$i}->{cableCallsign}.mpg";

        &saveMpgFile( $fileName, $mpgDurationSeconds, $qamDevice, $qamTuner );

        # if the filesize is 0-bytes, then don't put it into the qamdump file; for whatever reason
        # the channel isn't tunable.
        if ( -s $fileName )
        {
            $channelisclear = 1;
        }
    }    #end of $createMPG

    if ($channelisclear)
    {
        print $fh "$i|$ch{$i}->{cableCallsign}|$ch{$i}->{qam}|$ch{$i}->{program}|QAM_256|$ch{$i}->{stationID}|\n";
    }
}    #end of for loop

# Kill any remaining strays.  Of course, if we didn't create MPGs, then
# there won't be any to kill.

print "Terminating any stale processes.\n";

`killall hdhomerun_config`;

my $unknownChannelCount = scalar( keys %unknownCallsign );

if ( $unknownChannelCount > 0 )
{
    print $fh "---\nUnknown\n";
    foreach ( keys %unknownCallsign )
    {
        my ( $qamFreq, $program ) = split(/\+/);
        print $fh "qamfreq:$qamFreq program:$program\n";
    }

    print "\n\n$unknownChannelCount unknown channels.\n";
    print "Would you like to try to determine what the unknown channels are? (Y/N)\n";
    chomp( $response = <STDIN> );
    $response = uc($response);

    last if ( $response eq "N" );

    print "VLC or create MPG file? (V/M/Quit)\n";
    chomp( $response = <STDIN> );
    $response = uc($response);

    if ( $response eq "V" )
    {
        print "Experimental! You will need to run a new VLC session for each test.\nStart VLC, connect to network udp://\@:5000 each time.\n";
    }

    if ( $response eq "M" )
    {

        print "Once scan is complete, use mplayer or similar program to view\n";
        print "each 'unknown' filename.  Edit the .txt file and insert what was\n";
        print "found.  If you can't tell what the program is, consider extending\n";
        print "the timeout, or leave UNKNOWN.\n";
    }

    last if ( $response eq "Q" );

    foreach ( keys %unknownCallsign )
    {
        my ( $qamFreq, $program ) = split(/\+/);

        print "Setting device $qamDevice to qamfreq $qamFreq\n";
        my $tunestatus = `hdhomerun_config $qamDevice set /tuner$qamTuner/channel auto:$qamFreq`;
        chomp($tunestatus);
        sleep(3);
        print "Setting device $qamDevice to program $program\n";
        sleep(5);
        `hdhomerun_config $qamDevice set /tuner$qamTuner/program $program`;
        sleep(5);

        if ( $response eq "M" )
        {
            my $fileName = "unknown-qam$qamFreq-prog$program.mpg";
            &saveMpgFile( $fileName, $mpgDurationSeconds, $qamDevice, $qamTuner );
            print $fh "Unknown|qamfreq:$qamFreq|program:$program|UNKNOWN\n";
        }
        if ( $response eq "V" )
        {
            print "Setting target for VLC to $vlcIPaddress\nPress ENTER once VLC is running.\n";
            $response = <STDIN>;
            `hdhomerun_config $qamDevice set /tuner$qamTuner/target $vlcIPaddress:5000`;
            print "Enter description of what was found, ENTER if can't deduce.";
            chomp( $response = <STDIN> );
            print $fh "Unknown|qamfreq:$qamFreq|program:$program|$response\n";

        }
    }
}

close($fh);

print "\nDone.\n";

print "Terminating any stale processes.\n";
`killall hdhomerun_config`;

print "Please email the .txt file to qam-info\@schedulesdirect.org\n";
exit(0);

sub discoverHDHR()
{

    # Find which HDHRs are on the network
    my @output = `hdhomerun_config discover`;
    chomp(@output);    # removes newlines

    print "\nDiscovering HD Homeruns on the network.\n";

    foreach my $line (@output)
    {
        if ($debugEnabled)
        {
            print "raw data from discover: $line\n";
        }              #prints the raw information

        ( $deviceID[$i], $deviceIP[$i] ) = ( split( / /, $line ) )[ 2, 5 ];

        chomp( $deviceHWType[$i] = `hdhomerun_config $deviceID[$i] get /sys/model` );

        print "device ID $deviceID[$i] has IP address $deviceIP[$i] and is a $deviceHWType[$i]";

        if ( $deviceHWType[$i] eq "hdhomerun3_cablecard" )
        {
            $hdhrCCIndex = $i;    #Keep track of which device is a HDHR-CC
            print "; skipping this device.\n";
        }

        if ( $deviceHWType[$i] =~ "_atsc"
            && ( $verifyType ne "none" ) )
        {
            print "\n";
            print "Is this device connected to an Antenna, or is it connected to your Cable system? (A/C/Skip) ";
            my $response;
            chomp( $response = <STDIN> );
            $response = uc($response);
            if ( $response eq "C" )
            {
                $hdhrQAMIndex = $i;    #Keep track of which device is connected to coax - can't do a QAM scan on Antenna systems.
            }
        }

        $i++;
    }

    if ($debugEnabled)
    {
        print "hdhrCCIndex is $hdhrCCIndex\nhdhrQAMIndex is $hdhrQAMIndex\n";
    }

    if ( $hdhrCCIndex == -1 )
    {
        print "Fatal error: did not find a HD Homerun with a cable card.\n";
        exit;
    }

    if ( $hdhrQAMIndex == -1 && $authtype eq "subscribed" )
    {
        print "\nFatal error: Using authtype \"subscribed\" without verifying resulting\n" . "QAM table using a non-Cable Card HDHR is not supported.\n" . "Did not find a non-CC HDHR connected to the coax.\n";
        exit;
    }

    $ccDevice  = $deviceID[$hdhrCCIndex];
    $qamDevice = $deviceID[$hdhrQAMIndex];

}    # end of the subroutine.

sub get_headends()
{

    # This function returns the headends which are available in a particular
    # geographic location.

    my $randhash = $_[0];
    my $to_get   = "PC:" . $_[1];

    print "Retrieving headends.\n";

    my %req;

    $req{1}->{"action"}  = "get";
    $req{1}->{"object"}  = "headends";
    $req{1}->{"request"} = $to_get;
    $req{1}->{"api"}     = $api;

    if ( $randhash ne "none" )
    {
        $req{1}->{"randhash"} = $randhash;
    }

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugEnabled)
    {
        print "get->headends: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    return ($response);

}

sub send_request()
{

    # The workhorse routine. Creates a JSON object and sends it to the server.

    my $request = $_[0];
    my $fname   = "";

    if ( defined $_[1] )
    {
        $fname = $_[1];
    }

    if ($debugEnabled)
    {
        print "send->request: request is\n$request\n";
    }

    $m->get("$baseurl/request.php");

    my $fields = { 'request' => $request };

    $m->submit_form( form_number => 1, fields => $fields, button => 'submit' );

    if ( $debugEnabled && $fname eq "" )

      # If there's a file name, then the response is going to be a .zip file, and we don't want to try to print a zip.
    {
        print "Response from server:\n" . $m->content();
    }

    if ( $fname eq "" )
    {
        return ( $m->content() );    # Just return whatever we got from the server.
    }

    $fname =~ s/PC:/PC_/;

    $m->save_content($fname);

    # Make a json response so that other functions don't need to get re-written
    my %response;
    $response{1}->{code}     = 200;
    $response{1}->{response} = "OK";
    my $json1 = new JSON::XS;
    return ( $json1->utf8(1)->encode( $response{1} ) );
}

sub download_lineup()
{

    # A lineup is a specific mapping of channels for a provider.

    $randhash = $_[0];
    my $to_get = $_[1];
    print "Retrieving lineup $to_get.\n";

    my %req;

    $req{1}->{"action"}   = "get";
    $req{1}->{"randhash"} = $randhash;
    $req{1}->{"object"}   = "lineups";
    $req{1}->{"request"}  = [$to_get];
    $req{1}->{"api"}      = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugEnabled)
    {
        print "download->lineup: created $json_text\n";
    }

    my $response = JSON->new->utf8->decode( &send_request( $json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    my $url      = $response->{"URL"};
    my $fileName = $response->{"filename"};

    print "url is: $url\n";
    $m->get( $url, ':content_file' => $fileName );
}

sub login_to_sd()
{
    my %req;

    $req{1}->{"action"}                = "get";
    $req{1}->{"object"}                = "randhash";
    $req{1}->{"request"}->{"username"} = $_[0];
    $req{1}->{"request"}->{"password"} = sha1_hex( $_[1] );
    $req{1}->{"api"}                   = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );

    if ($debugEnabled)
    {
        print "login_to_sd: created $json_text\n";
    }

    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    return ( $response->{"randhash"} );
}

sub saveMpgFile()
{
    my $name      = $_[0];
    my $duration  = $_[1];
    my $qamDevice = $_[2];
    my $qamTuner  = $_[3];

    if ($debugEnabled) { print "About to start $duration seconds timeout.\n"; }
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };    # NB: \n required
        alarm $duration;
        system( "hdhomerun_config", "$qamDevice", "save", "/tuner$qamTuner", "$name" );
        alarm 0;
    };

}

sub add_or_delete_headend()
{

    # Order of parameters:randhash,headend,action

    my %req;

    if ( $_[2] eq "add" )
    {
        print "Sending addHeadend request to server.\n";
        $req{1}->{"action"} = "add";
    }

    if ( $_[2] eq "delete" )
    {
        print "Sending deleteHeadend request to server.\n";
        $req{1}->{"action"} = "delete";
    }

    $req{1}->{"object"}   = "headends";
    $req{1}->{"randhash"} = $_[0];
    $req{1}->{"request"}  = $_[1];

    $req{1}->{"api"} = $api;

    my $json1     = new JSON::XS;
    my $json_text = $json1->utf8(1)->encode( $req{1} );
    if ($debugEnabled)
    {
        print "add/delete->headend: created $json_text\n";
    }
    my $response = JSON->new->utf8->decode( &send_request($json_text) );

    if ( $response->{"response"} eq "ERROR" )
    {
        print "Received error from server:\n";
        print $response->{"message"}, "\nExiting.\n";
        exit;
    }

    print "Successfully sent Headend request.\n";

    if ($debugEnabled)
    {
        print Dumper($response);
    }

    return;

}
