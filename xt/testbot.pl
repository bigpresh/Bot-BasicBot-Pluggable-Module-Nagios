#!/usr/bin/perl

# A quick bot script to aid with testing.
#
# In future, I'd like to write some decent tests which fire up a mock ircd
# (using PoCo::Server::IRC maybe), a client running the module and another
# testing client, and test the expected interactions, but, well, E_NO_TUITS

use strict;
use Bot::BasicBot::Pluggable;

use Getopt::Long;

my $server  = "irc.freenode.net";
my $port    = "6667";
my $channel = "##preshtest";
my $nick    = "bbpmnagtest";

GetOptions(
    "server=s"  => \$server,
    "port=i"    => \$port,
    "channel=s" => \$channel,
) or die "Invalid arguments";

my $bot = Bot::BasicBot::Pluggable->new(
    channels => [ $channel ],
    server   => $server,
    port     => $port,
    nick     => $nick,
);
#$bot->load('Auth');
$bot->load('Nagios');
$bot->run;
