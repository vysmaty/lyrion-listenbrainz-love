use strict; use warnings; use Test::More; use lib '.';
use Plugins::ListenBrainzLove::Core;
my $id='11111111-2222-4333-8444-555555555555';
my $msid='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $track={artist=>'Artist',title=>'Song',mbid=>$id,url=>'tidal://123.flc'};
my ($now,$score)=(1000,1);my (%state,@calls,$r);
my $transport=sub {
 my ($method,$url,$h,$body,$cb)=@_;push @calls,[$method,$url,$body];
 return $cb->(undef,{valid=>1,user_name=>'tester'}) if $url=~/validate-token/;
 if ($method eq 'POST') {$score=$body->{score};return $cb->(undef,{status=>'ok'})}
 $cb->(undef,{feedback=>[{recording_mbid=>$id,score=>$score},{recording_msid=>$msid,score=>$score}]});
};
my $core=Plugins::ListenBrainzLove::Core->new(state=>\%state,clock=>sub {$now},transport=>$transport);
ok($core->can('unlove'),'Core supports explicit removal of Love');
if ($core->can('unlove')) {
 $core->status($track,'fixture','tester',sub {$r=shift});
 is($r->{score},1,'initial Love is verified');
 $core->unlove($track,'fixture','tester',sub {$r=shift});
 ok($r->{ok} && $r->{score}==0,'Unlove verifies score zero after the write');
 my @posts=grep {$_->[0] eq 'POST'} @calls;
 is(scalar @posts,1,'Unlove sends exactly one write');
 is($posts[0][2]{score},0,'removal is score 0, never dislike -1');
 is($posts[0][2]{recording_mbid},$id,'removal uses the exact selected recording');
 my $count=@calls;$core->status($track,'fixture','tester',sub {$r=shift});
 is($r->{score},0,'a subsequent status cannot resurrect cached Love');
 is(scalar @calls,$count,'verified removal also seeds the short status cache');
 ok(!grep($_->[1]=~/submit-listens/,@calls),'removal never posts a playing-now or scrobble');
 # Removal of a known paired identity returns two independent default-zero rows.
 my %paired;
 my $pair_core=Plugins::ListenBrainzLove::Core->new(state=>\%paired,clock=>sub {$now},transport=>sub {
  my ($method,$url,$h,$body,$cb)=@_;
  return $cb->(undef,{valid=>1,user_name=>'tester'}) if $url=~/validate-token/;
  return $cb->(undef,{payload=>{listens=>[{recording_msid=>$msid,track_metadata=>{artist_name=>'Artist',track_name=>'Song',mbid_mapping=>{recording_mbid=>$id}}}]}}) if $url=~/playing-now/;
  if ($method eq 'POST') {
   is_deeply($body,{recording_mbid=>$id,recording_msid=>$msid,score=>0},'Unlove preserves the exact MBID/MSID pair from the cached status');
   return $cb->(undef,{status=>'ok'});
  }
  $cb->(undef,{feedback=> $url=~/recording_msids/ ? [{recording_mbid=>$id,recording_msid=>$msid,score=>1}] : []});
 });
 my $remote={%$track,mbid=>''};$pair_core->status($remote,'fixture','tester',sub {$r=shift});
 ok($r->{ok},'paired identity is read before removal');
 $pair_core->{transport}=sub {
  my ($method,$url,$h,$body,$cb)=@_;
  if ($method eq 'POST') {is_deeply($body,{recording_mbid=>$id,recording_msid=>$msid,score=>0},'removal includes both previously verified identifiers');return $cb->(undef,{status=>'ok'})}
  $cb->(undef,{feedback=>[{recording_mbid=>$id,score=>0},{recording_msid=>$msid,score=>0}]});
 };
 $pair_core->unlove($remote,'fixture','tester',sub {$r=shift});
 ok($r->{ok} && $r->{score}==0 && $r->{msid_score}==0,'independent zero rows confirm removal of both identifiers');
 $core->{transport}=sub {my ($method,$url,$h,$body,$cb)=@_;return $cb->(undef,{status=>'ok'}) if $method eq 'POST';$cb->(undef,{feedback=>[{recording_mbid=>$id,score=>1}]})};
 $core->unlove($track,'fixture','tester',sub {$r=shift});
 ok(!$r->{ok} && $r->{uncertain},'unchanged Love after removal is uncertain, not a false success');
 my @unresolved;
 my $missing=Plugins::ListenBrainzLove::Core->new(allow_playing_now=>1,is_current=>sub {1},transport=>sub {
  my ($method,$url,$h,$body,$cb)=@_;push @unresolved,[$method,$url];
  return $cb->(undef,{valid=>1,user_name=>'tester'}) if $url=~/validate-token/;
  return $cb->(undef,{payload=>{listens=>[]}}) if $url=~/playing-now|listens\?/;
  $cb->(undef,{});
 });
 $missing->unlove({%$track,mbid=>''},'fixture','tester',sub {$r=shift});
 ok(!$r->{ok} && !$r->{uncertain},'Unlove without a known identity stops before writing');
 ok(!grep($_->[0] eq 'POST',@unresolved),'Unlove cannot create playing-now even for an active track');
}
done_testing;
