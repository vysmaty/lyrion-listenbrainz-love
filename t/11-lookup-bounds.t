use strict;use warnings;use Test::More;use lib '.';use Plugins::ListenBrainzLove::Core;
my $id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $row={listened_at=>990,recording_msid=>$id,track_metadata=>{artist_name=>'A',track_name=>'T'}};
for my $case ('saturated recent','multiple playing-now') {
 my($result,@calls);
 my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub{1000},transport=>sub{
  my($method,$url,$headers,$body,$cb)=@_;push @calls,$method;
  my $data=$url=~/validate-token/?{valid=>1,user_name=>'tester'}:$url=~/playing-now/?{payload=>{listens=>$case eq 'multiple playing-now'?[$row,$row]:[]}}:$url=~/listens\?/?{payload=>{listens=>[map {{%$row}} 1..100]}}:$method eq 'POST'?{status=>'ok'}:{feedback=>[{recording_msid=>$id,score=>1}]};
  $cb->(undef,$data);
 });
 $core->love({artist=>'A',title=>'T'},'fixture','tester',sub{$result=shift});
 ok(!$result->{ok},"$case fails closed");is(scalar(grep{$_ eq 'POST'}@calls),0,"$case no write");
}
done_testing;
