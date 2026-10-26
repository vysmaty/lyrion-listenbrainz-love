use strict; use warnings; use Test::More; use JSON::PP qw(decode_json); use lib '.';
BEGIN {
 $INC{'Slim/Utils/Timers.pm'}=1;
 package Slim::Utils::Timers;sub killTimers {} sub setTimer {die 'Unexpected timer in immediate-response fixture'}
 package main;
 $INC{'Slim/Networking/SimpleAsyncHTTP.pm'}=1;
 package Slim::Networking::SimpleAsyncHTTP;
 our ($calls,$request); $calls=0;
 sub hasSSL {1}
 sub new {my($class,$cb,$ecb,$params)=@_;bless {cb=>$cb},$class}
 sub post {my($self,@args)=@_;$calls++;$request=\@args;$self->{cb}->($self)}
 sub code {200} sub content {'{"status":"ok","recording_msid":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"}'}
}
use Plugins::ListenBrainzLove::Transport;
{no warnings 'redefine';my $tick=0;*Plugins::ListenBrainzLove::Transport::_now=sub {$tick+=2}}
my $url='https://api.listenbrainz.org/1/submit-listens?return_msid=true';
my $listen={track_metadata=>{artist_name=>'Artist',track_name=>'Song'}};
my ($error,$data);
Plugins::ListenBrainzLove::Transport::request('POST',$url,{Authorization=>'Token fixture'},{listen_type=>'playing_now',payload=>[$listen]},sub{($error,$data)=@_});
ok(!$error && $data->{recording_msid},'transport allows the exact temporary notification');
is($Slim::Networking::SimpleAsyncHTTP::calls,1,'one HTTP request was made');
my $sent=decode_json($Slim::Networking::SimpleAsyncHTTP::request ? $Slim::Networking::SimpleAsyncHTTP::request->[-1] : '{}');
is($sent->{listen_type},'playing_now','serialized payload keeps the temporary type');
for my $case (
 ['single',{listen_type=>'single',payload=>[{%$listen,listened_at=>1000}]}],
 ['import',{listen_type=>'import',payload=>[{%$listen,listened_at=>1000}]}],
 ['timestamp',{listen_type=>'playing_now',payload=>[{%$listen,listened_at=>1000}]}],
 ['multiple tracks',{listen_type=>'playing_now',payload=>[$listen,$listen]}],
 ['empty track',{listen_type=>'playing_now',payload=>[{track_metadata=>{}}]}],
 ['extra root fields',{listen_type=>'playing_now',payload=>[$listen],listened_at=>1000}],
) {
 my ($label,$body)=@$case; my $before=$Slim::Networking::SimpleAsyncHTTP::calls;
 Plugins::ListenBrainzLove::Transport::request('POST',$url,{},$body,sub{($error,$data)=@_});
 ok($error,"$label rejected");
 is($Slim::Networking::SimpleAsyncHTTP::calls,$before,"$label never reaches HTTP");
}
done_testing;
