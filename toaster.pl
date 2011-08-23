#
# UC Berkeley IEEE Bus schedule Announcer Kiosk
# Copyright 2010, Hike Danakian <hdana2@gmail.com>
#
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this 
#   list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice, 
#   this list of conditions and the following disclaimer in the documentation 
#   and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
#  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
#  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
#  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

use strict;
use warnings;
#use Data::Dumper;
use Carp;

use LWP::Simple; # for making http requests
use Term::ReadKey; # for getting term size
#use Text::FIGlet; # for initial IEEE banner
# for playing voices
my $mplayer;
eval {
	require Audio::Play::MPlayer;
	$mplayer = Audio::Play::MPlayer->new;
};

use Term::ANSIColor; # for status colors

my ($wchar, $hchar) = GetTerminalSize();

#my $figlet = Text::FIGlet->new(-d => "/usr/share/figlet");

# sprint_status_col
# given: $param, $status
# returns: param and status styled as follows - "$param ...(padding)... 
#		[$status]", with padding according to the size of the terminal 
#		window.
sub sprint_status_col {
	my ($param, $status) = @_;
# NOTE: why doesn't this padding work?
#	return sprintf("%s%" . ($wchar - length($param) - length($status) - 2) . "s\n",
#			$param, "[$status]");
	return "$param " . ("." x ($wchar - length($param) - length($status) 
		- 4)) . " [" . colored($status, 'cyan') . "]"; # note the 4 is for 2 spaces + 2 brackets
}
# print_status_col
# given: $param, $status
# action: prints the param and status as follows - "$param ...(padding)... [$status]"
sub print_status_col {
	$| = 1;
	print &sprint_status_col; # note that & is used to pass @_ due to stack reuse
}
# make_bus_url
# given: $bus, $stop_id, ?$agency
# returns: url of nextbus page
sub make_bus_url {
	my ($bus, $stop_id, $agency) = @_;
	$agency = defined($agency) ? $agency : 'actransit';
	return "http://www.nextbus.com/predictor/simplePrediction.shtml?a=$agency&r=$bus&s=$stop_id";
}
# get_bus_prediction
# given: $bus, $stop_id, ?$agency
# returns: array of all predicted buses, or -1 if no prediction
sub get_bus_prediction {
	my $url = &make_bus_url; # see above note on the use of & for passing @_
	my $raw_content = get($url) 
		or carp "Something failed while getting predictions from NextBus."
		and return -1;
	if ($raw_content =~ /minutes/ && (my @results = 
			$raw_content =~ /<span [^>]*>&nbsp;(\d+)</g)) {
		return \@results;
	} else {
		return -1;
	}
}
# announce
# given: bus and time (in which bus will arrive)
# action: makes vocal announcements of bus arrivals
sub announce {
	return unless $mplayer;
	my ($bus, $time) = @_;
	$mplayer->load("$bus-$time.wav") or croak ("Audio file $bus-$time.wav not found!");
	#$mplayer->poll( 1 ) until $mplayer->state == 0;
}
# banner
# given: bus
# action: makes a banner showing that a bus is arriving soon
sub banner {
	my ($bus) = @_;
#	print $figlet->figify(-f => 'digital', -x => 'c', -w => -1, -m => 0, -W => '', -A => "$bus Arriving") . "\n";
	system("figlet -f digital -w $wchar -c -W $bus Arriving Soon");
}

# add stops like ['bus name', 'stop number after s= in the nextbus url', 'description']
my @stops = (
		['F', '0303140', 'F, Hearst and LeRoy'],
		['52', '0303140', '52, Hearst and LeRoy']
		#['', '','']
	    );

# main loop
my @announce_list;
my %announce_guard; # prevent from repeating announcements too soon
my $out_buf;
do {
	system('clear');
	print localtime() . "\n";
	$out_buf = "";

	# make figlet logo
#	print $figlet->figify(-w => -1, -m => -1, -A => "UC Berkeley   IEEE") . "\n";
	system("figlet -f small -w $wchar UC Berkeley IEEE");
	print "\n";
	print_status_col("{Bus Stop}", "Minutes until bus arrival");
	print "\n\n";

	foreach my $stop (@stops) {
		my $current_prediction = get_bus_prediction($stop->[0], $stop->[1]);
		if (($current_prediction != -1) && ($current_prediction->[0] <= 5)) {
			push(@announce_list, [$stop->[0], $current_prediction->[0]]);
		}
		$out_buf .= sprint_status_col($stop->[2], 
			($current_prediction == -1) ? "Don't Know" 
						    : join (', ', @$current_prediction));
	}
	$| = 1; # flush right away
	print $out_buf."\n\n\n";

	# make announcments
	while (@announce_list) {
		my ($bus, $time) = @{pop(@announce_list)};
		banner($bus);
		# make sure it doesn't repeat every iteration 
		unless (defined($announce_guard{$bus}) && (time - $announce_guard{$bus}) < 5500) {
			announce($bus, $time);
			$announce_guard{$bus} = time;
		}
	}
} while (sleep(30));
