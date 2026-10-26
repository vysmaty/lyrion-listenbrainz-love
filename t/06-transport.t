use strict; use warnings; use Test::More; use lib '.';
BEGIN {
 $INC{'Slim/Utils/Timers.pm'}=1;
 package Slim::Utils::Timers;sub killTimers {} sub setTimer {die 'Unexpected timer in immediate-response fixture'}
 package main;
 $INC{'Slim/Networking/SimpleAsyncHTTP.pm'}=1;
 package Slim::Networking::SimpleAsyncHTTP;
 our ($instance,$ssl,$body,$status); $ssl=1; $body='{"valid":true,"user_name":"tester"}'; $status=200;
 sub hasSSL {$ssl} sub new {my($class,$cb,$ecb,$params)=@_; $instance=bless {cb=>$cb,ecb=>$ecb,params=>$params},$class}
 sub get {my($self,@req)=@_;$self->{req}=\@req;$self->{cb}->($self)} sub post {shift->get(@_)}
 sub content {$body} sub code {$status}
}
my $loaded=eval{require Plugins::ListenBrainzLove::Transport;1}; ok($loaded,'transport loads') or diag($@);
if($loaded) {
 {no warnings 'redefine';my $tick=0;*Plugins::ListenBrainzLove::Transport::_now=sub {$tick+=2}}
 my ($err,$data); my $cb=sub{($err,$data)=@_};
 Plugins::ListenBrainzLove::Transport::request('GET','https://api.listenbrainz.org/1/validate-token',{Authorization=>'Token fixture'},undef,$cb);
 ok(!$err && $data->{valid},'JSON decoded');
 my $i=$Slim::Networking::SimpleAsyncHTTP::instance;
 is($i->{params}{timeout},8,'8 second timeout'); is($i->{params}{maxRedirect},0,'no redirects');
 is($i->{params}{options}{SSL_verify_mode},1,'force TLS verification');
 is($i->{params}{options}{SSL_verifycn_name},'api.listenbrainz.org','force hostname check');
 for my $body ('<html>fixture</html>','[]','{bad json') {
  $Slim::Networking::SimpleAsyncHTTP::body=$body;
  Plugins::ListenBrainzLove::Transport::request('GET','https://api.listenbrainz.org/1/validate-token',{},undef,$cb);
  ok($err && !$data,'invalid JSON/shape safe failure'); unlike($err,qr/fixture/,'no server payload in errors');
 }
 $Slim::Networking::SimpleAsyncHTTP::ssl=0;
 Plugins::ListenBrainzLove::Transport::request('GET','https://api.listenbrainz.org/1/validate-token',{},undef,$cb);
 ok($err,'no TLS support refuses downgrade');
 $Slim::Networking::SimpleAsyncHTTP::ssl=1;
 for my $url ('http://api.listenbrainz.org/1/validate-token','https://evil.invalid/1/validate-token','https://api.listenbrainz.org.evil/1/validate-token','https://api.listenbrainz.org/1/submit-listens') {
  Plugins::ListenBrainzLove::Transport::request('POST',$url,{},undef,$cb); ok($err,'unsafe origin or unapproved endpoint refused');
 }
}
done_testing;
