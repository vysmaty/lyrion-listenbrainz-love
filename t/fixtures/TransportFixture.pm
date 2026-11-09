package TransportFixture;
use strict;
use warnings;

our ($ssl,$status,$body)=(1,200,'{"status":"ok"}');
our ($params,@requests);

sub use_advancing_clock {
 no warnings qw(redefine once);
 my $tick=0;
 *Plugins::ListenBrainzLove::Transport::_now=sub {$tick+=2};
}

$INC{'Slim/Utils/Timers.pm'}=__FILE__;
package Slim::Utils::Timers;
sub killTimers {}
sub setTimer {die 'Unexpected timer in immediate-response fixture'}

$INC{'Slim/Networking/SimpleAsyncHTTP.pm'}=__FILE__;
package Slim::Networking::SimpleAsyncHTTP;
sub hasSSL {$TransportFixture::ssl}
sub new {
 my ($class,$callback,$error_callback,$params)=@_;
 $TransportFixture::params=$params;
 return bless {callback=>$callback},$class;
}
sub get {
 my ($self,@request)=@_;
 push @TransportFixture::requests,\@request;
 $self->{callback}->($self);
}
sub post {shift->get(@_)}
sub code {$TransportFixture::status}
sub content {$TransportFixture::body}
1;
