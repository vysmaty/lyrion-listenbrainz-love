use strict;use warnings;use Test::More;use lib '.';use Plugins::ListenBrainzLove::Core;
for my $valid ('false','yes',[],{}) {
 my($result,@calls);
 my $core=Plugins::ListenBrainzLove::Core->new(transport=>sub {
  my($m,$u,$h,$b,$cb)=@_;push @calls,$m;
  $cb->(undef,$u=~/validate-token/?{valid=>$valid,user_name=>'tester'}:$m eq 'POST'?{status=>'ok'}:{feedback=>[{recording_mbid=>'12345678-1234-4234-8234-123456789abc',score=>1}]});
 });
 $core->love({artist=>'A',title=>'T',mbid=>'12345678-1234-4234-8234-123456789abc'},'fixture','tester',sub{$result=shift});
 ok(!$result->{ok},'non-boolean token valid rejected');is(scalar(grep {$_ eq 'POST'} @calls),0,'no write on malformed token validity');
}
done_testing;
