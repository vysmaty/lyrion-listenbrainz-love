use strict; use warnings; use Test::More; use JSON::PP qw(decode_json); use lib '.';
use lib 't/fixtures';
use TransportFixture;
use Plugins::ListenBrainzLove::Transport;
TransportFixture::use_advancing_clock();
$TransportFixture::body='{"status":"ok","recording_msid":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"}';
my $url='https://api.listenbrainz.org/1/submit-listens?return_msid=true';
my $listen={track_metadata=>{artist_name=>'Artist',track_name=>'Song'}};
my ($error,$data);
Plugins::ListenBrainzLove::Transport::request('POST',$url,{Authorization=>'Token fixture'},{listen_type=>'playing_now',payload=>[$listen]},sub{($error,$data)=@_});
ok(!$error && $data->{recording_msid},'transport allows the exact temporary notification');
is(scalar @TransportFixture::requests,1,'one HTTP request was made');
my $request=$TransportFixture::requests[0];
my $sent=decode_json($request ? $request->[-1] : '{}');
is($sent->{listen_type},'playing_now','serialized payload keeps the temporary type');
for my $case (
 ['single',{listen_type=>'single',payload=>[{%$listen,listened_at=>1000}]}],
 ['import',{listen_type=>'import',payload=>[{%$listen,listened_at=>1000}]}],
 ['timestamp',{listen_type=>'playing_now',payload=>[{%$listen,listened_at=>1000}]}],
 ['multiple tracks',{listen_type=>'playing_now',payload=>[$listen,$listen]}],
 ['empty track',{listen_type=>'playing_now',payload=>[{track_metadata=>{}}]}],
 ['extra root fields',{listen_type=>'playing_now',payload=>[$listen],listened_at=>1000}],
) {
 my ($label,$body)=@$case; my $before=@TransportFixture::requests;
 Plugins::ListenBrainzLove::Transport::request('POST',$url,{},$body,sub{($error,$data)=@_});
 ok($error,"$label rejected");
 is(scalar @TransportFixture::requests,$before,"$label never reaches HTTP");
}
done_testing;
