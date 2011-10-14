package Bot::BasicBot::Pluggable::Module::Nagios;

use warnings;
use strict;

our $VERSION = '0.01';

use base 'Bot::BasicBot::Pluggable::Module';

use Nagios::Scrape;

=head1 NAME

Bot::BasicBot::Pluggable::Module::Nagios - report Nagios alerts to IRC

=head1 DESCRIPTION

A module for IRC bots powered by L<Bot::BasicBot::Pluggable> to monitor a Nagios
install and report alerts to IRC.


=head1 SYNOPSIS

Load the module as you would any other L<Bot::BasicBot::Pluggable> module, then
configure it to watch a Nagios install and report problems to the desired
channel(s) with the C<nagios add> command.

In a direct message to the bot:

    <user> nagios add http://nagios.example.com/cgi-bin/status.cgi username password #channel
    <bot> OK
    <user> nagios list
    <bot> I'm currently monitoring the following Nagios instances:
          .. 1 : http://example.com/cgi-bin/status.cgi as dave for #chan
    <user> nagios del 1
    <bot> OK, deleted instance 1

=cut


sub help {
    return <<USAGE;
A module to report Nagios alerts to IRC channels.

   nagios add http://example.com/cgi-bin/status.cgi username password #chan
   nagios list
   nagios del 1

Full help is available at http://p3rl.org/Bot::BasicBot::Pluggable::Module::Nagios
USAGE
}

sub told {
    my ($self, $mess) = @_;

    return unless $mess->{address} && $mess->{body} =~ s/^nagios\s+//i;
    my ($command, $params) = split /\s+/, $mess->{body}, 2;
    if (lc $command eq 'add') {
        my($url, $user, $pass, $channel_list) = split /\s+/, $params, 4;
        if ($url !~ /^http/i) {
            return "URL looks invalid!";
        }
        my @channels = split /\s+|,/, $channel_list;
        my $instances = $self->get('instances') || [];
        push @$instances, {
            url      => $url,
            user     => $user,
            pass     => $pass,
            channels => \@channels,
        };
        $self->set('instances' => $instances);
        return "OK, added Nagios instance to monitor";
    }
    if (lc $command eq 'list') {
        my $instances = $self->get('instances') || [];
        if (!@$instances) {
            return "I'm not currently monitoring any Nagios instances.";
        }
        my $response = "I'm currently monitoring the following instances:\n";
        my $num = 0;
        for my $instance (@$instances) {
            $response .= sprintf "%d : %s as %s for %s\n",
                $num++,
                $instance->{url},
                $instance->{user},
                join ',', @{ $instance->{channels} };
        }
        return $response;
    }
    if (lc $command eq 'del' || lc $command eq 'delete') {
        my $num = $params;
        if ($num !~ /^\d+$/) {
            return "Usage: nagios del instancenum (e.g. 'nagios del 1')";
        }
        my $instances = $self->get('instances') || [];
        if (!$instances->[$num]) {
            return "No such instance";
        }
        splice @$instances, $num;
        $self->set('instances', $instances);
        return "OK, deleted instance $num";
    }
}

my $last_polled = 0;
my %last_status;

sub tick {
    my ($self) = @_;

    # TODO: allow time between checks to be configurable 
    return if (time - $last_polled < 60 * 1);
    $last_polled = time;

    warn "Polling.";

    my $instances = $self->get('instances') || [];
    instance:
    for my $instance (@$instances) {
        my $ns = Nagios::Scrape->new(
            username => $instance->{user},
            password => $instance->{pass},
            url      => $instance->{url},
        );
        # Get services in all states except PENDING - we want OK ones, too, so
        # we can easily report problem -> OK transitions
        $ns->service_state(2);
    
        # TODO: get host statuses, too; report those, and don't report services
        # on hosts that are down (configurable option, perhaps)
        # TODO: allow filtering by status (Nagios::Scrape can do that for us)
        my @service_statuses = $ns->get_service_status;


        # Key to use for this instance in %last_status
        my $instance_key = join '_', $instance->{url}, $instance->{user};
        
        my $instance_statuses = $last_status{$instance_key};


        # Group problems by host, ignoring any which we've already reported 
        # recently
        my %service_by_host;
        service:
        for my $service (@service_statuses) {
            my $service_key = join '_', $service->{host}, $service->{service};
            if (my $last_status = $instance_statuses->{$service_key}) {
                # If it was OK before and still OK now, move on swiftly
                next if $last_status->{status} eq 'OK'
                    and $service->{status} eq 'OK';

                # TODO: make the delay between subsequent wibbles about the same
                # problem configurable by the user
                next service if $last_status->{status} eq $_->{status}
                    and time - $last_status->{timestamp} > 60 * 15;

            } else {
                # We've not seen this one before; if it's 'OK', just remember it
                # but don't announce it, otherwise we'd send a flood of OK
                # notifications on first run
                if ($service->{status} eq 'OK') {
                    $instance_statuses->{$service_key} =
                        { timestamp => time(), status => $service->{status} };
                    next service;
                }
            }

            # Note that we're about to bitch about this one, and add it to
            # %service_by_host ready for reporting
            $instance_statuses->{$service_key} = { 
                timestamp => time(), status => $service->{status},
            };
            push @{ $service_by_host{ $service->{host} } }, $service;
        }

        for my $host (sort keys %service_by_host) {
            my $msg = "NAGIOS: $host : "
                . join ', ',
                map { "$_->{service} is $_->{status} ($_->{information})" }
                @{ $service_by_host{$host} };
            for my $channel (@{$instance->{channels}}) {
                $self->tell($channel, $msg);
            }
        }
    }
}





=head1 AUTHOR

David Precious, C<< <davidp at preshweb.co.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-bot-basicbot-pluggable-module-nagios at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Bot-BasicBot-Pluggable-Module-Nagios>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Bot::BasicBot::Pluggable::Module::Nagios


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Bot-BasicBot-Pluggable-Module-Nagios>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Bot-BasicBot-Pluggable-Module-Nagios>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Bot-BasicBot-Pluggable-Module-Nagios>

=item * Search CPAN

L<http://search.cpan.org/dist/Bot-BasicBot-Pluggable-Module-Nagios/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Bot::BasicBot::Pluggable::Module::Nagios
