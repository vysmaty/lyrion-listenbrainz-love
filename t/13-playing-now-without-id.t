use strict; use warnings; use Test::More; use lib '.';
use Plugins::ListenBrainzLove::Core;
my $id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $metadata={artist_name=>'Artist',track_name=>'Song'};
sub run_case {
 my ($playing,$recent)=@_; my (@calls,$result);
 my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub{1000},transport=>sub {
  my ($method,$url,$headers,$body,$cb)=@_; push @calls,[$method,$url,$body];
  my $data=$url=~/validate-token/?{valid=>1,user_name=>'tester'}:
   $url=~/playing-now/?{payload=>{listens=>[$playing]}}:
   $url=~/\/listens\?/?{payload=>{listens=>$recent}}:
   $url=~/metadata\/lookup/?{}:
   $url=~/get-feedback/?{feedback=>[{recording_msid=>$id,score=>1}]}:{status=>'ok'};
  $cb->(undef,$data);
 });
 $core->love({artist=>'Artist',title=>'Song'},'fixture-token','tester',sub{$result=shift});
 return ($result,\@calls);
}
my ($result,$calls)=run_case({playing_now=>1,track_metadata=>$metadata},[
 {listened_at=>990,recording_msid=>$id,track_metadata=>$metadata}
]);
ok($result->{ok},'playing-now without an ID falls back to the exact completed listen');
my @feedback=grep {$_->[1]=~/recording-feedback$/} @$calls;
is(scalar @feedback,1,'fallback sends one explicit Love');
is($feedback[0][2]{recording_msid},$id,'fallback uses the completed listen identity');
ok(!grep({$_->[1]=~/submit-listens/} @$calls),'fallback never creates a listen or playing-now');
($result,$calls)=run_case({playing_now=>1,track_metadata=>$metadata},[]);
ok(!$result->{ok},'no completed identity cannot report success');
like($result->{error},qr/identity.*available yet/i,'missing identity explains that a completed listen is needed');
is(scalar(grep {$_->[0] eq 'POST'} @$calls),0,'no identity sends no writes');
($result,$calls)=run_case({recording_msid=>'malformed',track_metadata=>$metadata},[]);
ok(!$result->{ok},'malformed supplied identity still fails closed');
is(scalar(grep {$_->[0] eq 'POST'} @$calls),0,'malformed supplied identity sends no writes');
done_testing;
