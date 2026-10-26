use strict; use warnings; use Test::More; use lib '.';
BEGIN {
 $INC{'Slim/Networking/SimpleAsyncHTTP.pm'}=1;
 $INC{'Slim/Utils/Timers.pm'}=1;
 package Slim::Utils::Timers;
 our $timer;
 sub setTimer { $timer=[@_] }
 sub killTimers { $timer=undef }
 package Slim::Networking::SimpleAsyncHTTP;
 our @calls;
 sub hasSSL {1}
 sub new {my ($class,$ok,$error)=@_;bless {ok=>$ok,error=>$error,code=>200,headers=>{}},$class}
 sub get {my ($self,@args)=@_;push @calls,[$main::now,$self,\@args]}
 sub post {shift->get(@_)}
 sub code {$_[0]{code}} sub content {'{"status":"ok"}'}
 sub headers {$_[0]} sub header {$_[0]{headers}{$_[1]}}
}
use Plugins::ListenBrainzLove::Transport;
our $now=1000.25;
{ no warnings 'redefine'; *Plugins::ListenBrainzLove::Transport::_now=sub {$now} }
my @results;
my $url='https://api.listenbrainz.org/1/validate-token';
sub request {Plugins::ListenBrainzLove::Transport::request('GET',$url,{},undef,sub {push @results,[@_]})}
sub respond {
 my ($code,$headers)=@_;my $http=$Slim::Networking::SimpleAsyncHTTP::calls[-1][1];
 $http->{code}=$code||200;$http->{headers}=$headers||{};$http->{ok}->($http);
}
sub advance {
 $now=shift;my $guard=0;
 while ($Slim::Utils::Timers::timer && $Slim::Utils::Timers::timer->[1]<=$now) {
  die 'Timer loop' if ++$guard>50;
  my $timer=$Slim::Utils::Timers::timer;$Slim::Utils::Timers::timer=undef;$timer->[2]->($timer->[0]);
 }
}
request();request();
is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,1,'parallel callers share a single active HTTP request');
respond();
is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,1,'completing HTTP does not immediately send the queued request');
advance(1001.29);
is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,1,'sub-second burst is prevented');
advance(1001.31);
is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,2,'LMS timer releases the next request after the minimum interval');
cmp_ok($Slim::Networking::SimpleAsyncHTTP::calls[1][0]-$Slim::Networking::SimpleAsyncHTTP::calls[0][0],'>=',1,'starts are at least one second apart');
respond();request();request();advance(1002.4);
respond(429,{'Retry-After'=>5});
my $count=@Slim::Networking::SimpleAsyncHTTP::calls;
is(scalar @results,4,'429 fails the current and waiting operations without replay');
like($results[-1][0],qr/rate limit/,'waiting callers receive the cooldown reason');
request();is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,$count,'new calls are blocked during Retry-After');
advance(1008);request();request();
respond(200,{'X-RateLimit-Remaining'=>0,'X-RateLimit-Reset-In'=>3});
is($results[-2][0],undef,'the final permitted response still succeeds');
like($results[-1][0],qr/rate limit/,'remaining zero also blocks the queue');
advance(1012);request();
my $mbid='11111111-2222-4333-8444-555555555555';
my $expired;
Plugins::ListenBrainzLove::Transport::request('POST','https://api.listenbrainz.org/1/feedback/recording-feedback',{},
 {recording_mbid=>$mbid,score=>0},sub {$expired=shift},{deadline=>1012.2});
respond();advance(1013.2);
like($expired||'',qr/expired/,'a queued write expires before dispatch');
is($Slim::Networking::SimpleAsyncHTTP::calls[-1][2][0],$url,'expired write never reaches the provider');
{
 request();my $still_current=1;my $changed;
 Plugins::ListenBrainzLove::Transport::request('POST','https://api.listenbrainz.org/1/submit-listens?return_msid=true',{},
  {listen_type=>'playing_now',payload=>[{track_metadata=>{artist_name=>'Artist',track_name=>'Song'}}]},sub {$changed=shift},
  {deadline=>1020,before_send=>sub {$still_current}});
 $still_current=0;respond();my $before=@Slim::Networking::SimpleAsyncHTTP::calls;advance(1014.3);
 like($changed||'',qr/snapshot changed/,'a queued playing-now rechecks actual playback at dispatch');
 is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,$before,'changed playback never submits a stale notification');
}
if (Plugins::ListenBrainzLove::Transport->can('shutdown')) {
 request();request();Plugins::ListenBrainzLove::Transport::shutdown();
 $count=@Slim::Networking::SimpleAsyncHTTP::calls;advance(1020);
 is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,$count,'shutdown cancels queued requests and timers');
} else {fail('transport has queue shutdown cleanup')}
if (Plugins::ListenBrainzLove::Transport->can('start')) {
 Plugins::ListenBrainzLove::Transport::start();advance(1022);
 request();request() for 1..33;
 like($results[-1][0],qr/queue full/,'the shared queue has a strict memory bound');
 my $active=$Slim::Networking::SimpleAsyncHTTP::calls[-1][1];
 Plugins::ListenBrainzLove::Transport::shutdown();
 $count=@Slim::Networking::SimpleAsyncHTTP::calls;$active->{error}->($active);
 advance(1030);
 is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,$count,'a late network callback cannot restart a stopped queue');
}
done_testing;
