use strict; use warnings; use Test::More; use lib '.'; use Plugins::ListenBrainzLove::Core;
my $id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $listen={listened_at=>990,recording_msid=>$id,track_metadata=>{artist_name=>'Artist',track_name=>'Song',additional_info=>{version=>'Live'}}};
sub run_case {
 my ($list,$version)=@_; my (@calls,$result);
 my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub{1000},transport=>sub {
  my ($m,$u,$h,$b,$cb)=@_; push @calls,[$m,$u,$b];
  $cb->(undef,$u=~/validate-token/?{valid=>1,user_name=>'tester'}:$u=~/playing-now/?{payload=>{listens=>[]}}:$u=~/\/listens\?/?{payload=>{listens=>$list}}:$u=~/metadata\/lookup/?{}:$u=~/get-feedback/?{feedback=>[{recording_msid=>$id,score=>1}]}:{status=>'ok'});
 });
 $core->love({artist=>'Artist',title=>'Song',version=>$version||'Live'},'fixture','tester',sub{$result=shift});
 return ($result,\@calls);
}
my ($r,$calls)=run_case([$listen]);
ok($r->{ok},'recent exact listen fallback');
like(join(' ',map {$_->[1]} @$calls),qr{/listens\?count=100&min_ts=700},'bounded to 100 and 300 seconds');
for my $case (
 ['stale',{%$listen,listened_at=>699}],
 ['future',{%$listen,listened_at=>1010}],
 ['mismatched artist',{%$listen,track_metadata=>{artist_name=>'Other',track_name=>'Song'}}],
 ['wrong version',{%$listen,track_metadata=>{artist_name=>'Artist',track_name=>'Song',additional_info=>{version=>'Studio'}}}],
 ['ambiguous',$listen,{%$listen,recording_msid=>'bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee'}],
) {
 my ($label,@rows)=@$case; my ($result,$req)=run_case(\@rows);
 ok(!$result->{ok},"$label rejected");
 is(scalar(grep {$_->[0] eq 'POST'} @$req),0,"$label no write");
}
done_testing;
