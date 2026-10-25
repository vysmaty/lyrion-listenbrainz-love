use strict; use warnings; use utf8; use Test::More; use lib '.';
use Plugins::ListenBrainzLove::Core;
my $mbid='11111111-2222-4333-8444-555555555555';
my $msid='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $meta={artist_name=>'Artist',track_name=>'Song',release_name=>'Album'};
sub exercise {
 my (%cfg)=@_; my (@calls,$result,$posted);
 my $input=$cfg{track}||{artist=>'Artist',title=>'Song',release=>'Album',url=>'tidal://123.flc'};
 my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub{1000},cache=>$cfg{cache}||{},allow_playing_now=>1,is_current=>sub{1},transport=>sub {
  my ($method,$url,$headers,$body,$cb)=@_; push @calls,[$method,$url,$headers,$body];
  return $cb->(undef,{valid=>1,user_name=>'tester'}) if $url=~/validate-token/;
  return $cb->(undef,{payload=>{listens=>$cfg{playing}||[]}}) if $url=~/playing-now$/;
  return $cb->(undef,{payload=>{listens=>$cfg{recent}||[]}}) if $url=~/\/listens\?/;
  return $cb->($cfg{lookup_error},exists($cfg{lookup})?$cfg{lookup}:{recording_mbid=>$mbid,recording_name=>'Song',artist_credit_name=>'Artist'}) if $url=~/metadata\/lookup/;
  return $cb->(undef,{status=>'ok',recording_msid=>$msid}) if $url=~/submit-listens/;
  if ($method eq 'POST') {$posted=$body;return $cb->(undef,{status=>'ok'})}
  return $cb->(undef,$cfg{readback}||{feedback=>[{$posted ? %$posted : (recording_mbid=>$mbid,score=>0)}]});
 });
 my $method=$cfg{status}?'status':'love';
 $core->$method($input,'fixture-only','tester',sub{$result=shift});
 return ($result,\@calls,$posted);
}
my ($r,$calls,$posted)=exercise(playing=>[{recording_msid=>$msid,track_metadata=>$meta}],recent=>[{listened_at=>990,recording_msid=>$msid,track_metadata=>{%$meta,mbid_mapping=>{recording_mbid=>$mbid}}}]);
ok($r->{ok},'mapped recent listen can upgrade playing-now MSID');
is($posted->{recording_mbid},$mbid,'available recording MBID wins');
is($posted->{recording_msid},$msid,'only the MSID paired in the same listen is attached');
ok(grep($_->[1]=~/\/listens\?/,@$calls),'MSID does not short-circuit recent lookup');
ok(!grep($_->[1]=~/metadata\/lookup|submit-listens/,@$calls),'known mapped identity needs neither lookup nor notification');
like($calls->[-1][1],qr{/get-feedback-for-recordings\?},'targeted readback replaces first-100 favorites');

($r,$calls,$posted)=exercise;
ok($r->{ok},'lookup can love before any scrobble');
is($posted->{recording_mbid},$mbid,'lookup resolves a recording MBID');
my ($lookup)=grep($_->[1]=~/metadata\/lookup/,@$calls);
is($lookup->[0],'GET','documented GET metadata lookup');
is($lookup->[1],'https://api.listenbrainz.org/1/metadata/lookup/?artist_name=Artist&recording_name=Song&release_name=Album','documented fields and trailing slash');
is($lookup->[2]{Authorization},'Token fixture-only','lookup authenticates via header');
ok(!grep($_->[1]=~/submit-listens/,@$calls),'successful MBID lookup never submits a listen');

for my $bad (
 {recording_mbid=>$mbid,recording_name=>'Song (Live)',artist_credit_name=>'Artist'},
 {recording_mbid=>$mbid,recording_name=>'Song',artist_credit_name=>'Other'},
 {recording_mbid=>'invalid',recording_name=>'Song',artist_credit_name=>'Artist'},
 {recording_mbid=>$mbid}, {error=>'bad response'},
) {
 ($r,$calls,$posted)=exercise(lookup=>$bad);
 ok(!$r->{ok},'conflicting or malformed candidate rejected');
 ok(!grep($_->[0] eq 'POST',@$calls),'invalid candidate causes no write');
}
($r,$calls,$posted)=exercise(lookup_error=>'temporary failure');
ok(!$r->{ok},'network failure is not treated as no-match');
ok(!grep($_->[0] eq 'POST',@$calls),'network failure cannot silently change identity');
($r,$calls,$posted)=exercise(lookup=>{},playing=>[{recording_msid=>$msid,track_metadata=>$meta}]);
ok($r->{ok},'confirmed no-match can use existing exact MSID');
is($posted->{recording_msid},$msid,'fallback preserves the MSID');
ok(!grep($_->[1]=~/submit-listens/,@$calls),'reused MSID needs no new notification');
ok(!$r->{linked},'MSID success is not presented as MusicBrainz linkage');

my %cache;
exercise(cache=>\%cache);
($r,$calls)=exercise(cache=>\%cache);
ok(!grep($_->[1]=~/metadata\/lookup/,@$calls),'accepted lookup cached for this exact source and metadata');
($r,$calls)=exercise(cache=>\%cache,track=>{artist=>'Artist',title=>'Song',release=>'Album',duration=>200,url=>'tidal://123.flc'});
ok(grep($_->[1]=~/metadata\/lookup/,@$calls),'metadata change invalidates cache identity');
ok(Plugins::ListenBrainzLove::Core->can('status'),'read-only status operation exists');
SKIP: {
 skip 'status is not implemented yet',4 unless Plugins::ListenBrainzLove::Core->can('status');
 ($r,$calls)=exercise(status=>1);
 ok($r->{ok} && $r->{score}==0,'targeted zero feedback is a known not-loved state');
 ok(!grep($_->[0] eq 'POST',@$calls),'opening status never writes');
 ($r,$calls)=exercise(status=>1,lookup=>{});
 ok(!$r->{ok},'missing identity has unknown status');
 ok(!grep($_->[0] eq 'POST',@$calls),'read-only mode cannot obtain an MSID by playing-now');
}
done_testing;
