use strict; use warnings; use Test::More; use JSON::PP qw(encode_json); use lib '.';
use Plugins::ListenBrainzLove::Core;
my $id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
sub run_case {
 my (%cfg)=@_; my (@calls,$result);
 my $input={artist=>'Artist',title=>'Song',release=>'Album',duration=>'193',tracknumber=>'9'};
 my %args=(clock=>sub{1000},allow_playing_now=>1,transport=>sub {
  my ($method,$url,$headers,$body,$cb)=@_; push @calls,[$method,$url,$headers,$body];
  if($url=~/validate-token/) {
   $input->{release}='Changed caller data' if $cfg{mutate_input};
   return $cb->(undef,{valid=>1,user_name=>'tester'});
  }
  return $cb->(undef,{payload=>{listens=>[$cfg{playing}||{playing_now=>1,track_metadata=>{artist_name=>'Artist',track_name=>'Song'}}]}}) if $url=~/playing-now$/;
  return $cb->(undef,{payload=>{listens=>$cfg{recent}||[]}}) if $url=~/\/listens\?/;
  return $cb->($cfg{now_error},exists($cfg{now_reply})?$cfg{now_reply}:{status=>'ok',recording_msid=>$id}) if $url=~/submit-listens/;
  return $cb->(undef,{status=>'ok'}) if $url=~/recording-feedback$/;
  return $cb->(undef,{feedback=>[{recording_msid=>$id,score=>1}]}) if $url=~/get-feedback/;
  die 'Unexpected endpoint';
 });
 $args{is_current}=sub { die 'fixture guard error' if $cfg{guard_error}; return !$cfg{changed} } unless $cfg{no_guard};
 my $core=Plugins::ListenBrainzLove::Core->new(%args);
 $core->love($input,'fixture-token','tester',sub{$result=shift});
 return ($result,\@calls);
}
my ($result,$calls)=run_case(mutate_input=>1);
ok($result->{ok},'manual Love can obtain an MSID from real playing-now');
my @now=grep {$_->[1]=~/submit-listens/} @$calls;
my @feedback=grep {$_->[1]=~/recording-feedback$/} @$calls;
is(scalar @now,1,'one on-demand playing-now request');
is($now[0][1],'https://api.listenbrainz.org/1/submit-listens?return_msid=true','documented MSID response requested');
is($now[0][2]{Authorization},'Token fixture-token','playing-now authenticates only in a header');
is($now[0][3]{listen_type},'playing_now','request is a temporary now-playing notification');
is(scalar @{$now[0][3]{payload}},1,'only the clicked track is submitted');
ok(!exists $now[0][3]{payload}[0]{listened_at},'playing-now has no completed-listen timestamp');
my $meta=$now[0][3]{payload}[0]{track_metadata};
is($meta->{artist_name},'Artist','captured artist preserved');
is($meta->{track_name},'Song','captured title preserved');
is($meta->{release_name},'Album','captured album is immutable');
is($meta->{additional_info}{duration},193,'track duration preserved');
is($meta->{additional_info}{tracknumber},9,'track number preserved');
like(encode_json($meta),qr/"tracknumber":"9"/,'track number uses the documented string type');
is(scalar @feedback,1,'one explicit feedback write follows');
is($feedback[0][3]{recording_msid},$id,'feedback uses exactly the returned MSID');
ok(!grep({($_->[3]||{})->{listen_type} && $_->[3]{listen_type} ne 'playing_now'} @$calls),'no single or import request exists');
for my $case (
 ['missing ID',now_reply=>{status=>'ok'}],
 ['invalid ID',now_reply=>{status=>'ok',recording_msid=>'not-a-uuid'}],
 ['rejected playing-now',now_reply=>{status=>'error',recording_msid=>$id}],
 ['network error',now_error=>'fixture network failure'],
 ['changed playback',changed=>1],
 ['missing playback guard',no_guard=>1],
 ['failed playback guard',guard_error=>1],
) {
 my ($label,@cfg)=@$case; my ($r,$requests)=run_case(@cfg);
 ok(!$r->{ok},"$label cannot report success");
 is(scalar(grep {$_->[1]=~/recording-feedback$/} @$requests),0,"$label sends no Love");
 is(scalar(grep {$_->[1]=~/submit-listens/} @$requests),0,"$label sends no playing-now") if $label=~/playback guard|changed playback/;
}
($result,$calls)=run_case(recent=>[{listened_at=>990,recording_msid=>$id,track_metadata=>{artist_name=>'Artist',track_name=>'Song'}}]);
ok($result->{ok},'an existing exact identity retains priority');
is(scalar(grep {$_->[1]=~/submit-listens/} @$calls),0,'known identity needs no additional playing-now');
($result,$calls)=run_case(playing=>{playing_now=>1,track_metadata=>{artist_name=>'Artist',track_name=>'Song',additional_info=>{recording_msid=>$id}}});
ok($result->{ok},'playing-now can reuse the MSID stored in additional_info');
is(scalar(grep {$_->[1]=~/submit-listens/} @$calls),0,'reused playing-now identity creates no extra notification');
done_testing;
