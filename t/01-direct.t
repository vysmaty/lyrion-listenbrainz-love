use strict;
use warnings;
use Test::More;
use lib '.';
my $loaded = eval { require Plugins::ListenBrainzLove::Core; 1 };
ok($loaded, 'core loads for direct-MBID Love') or diag($@);
if ($loaded) {
 my @requests;
 my $id='12345678-1234-4234-8234-123456789abc';
 my $core=Plugins::ListenBrainzLove::Core->new(transport=>sub {
  my ($method,$url,$headers,$body,$cb)=@_; push @requests,[$method,$url,$headers,$body];
  $cb->(undef, $url =~ /validate-token/ ? {valid=>1,user_name=>'tester'} : $method eq 'POST' ? {status=>'ok'} : {feedback=>[{recording_mbid=>$id,score=>1}]});
 }, clock=>sub {1000});
 my $result;
 $core->love({artist=>'Artist',title=>'Song',version=>'Live',mbid=>$id},'fixture-only-token','tester',sub {$result=shift});
 ok($result->{ok},'direct MBID Love verified');
 is(scalar @requests,3,'validate, feedback, readback only');
 is($requests[1][3]{score},1,'explicit score 1');
 is($requests[1][3]{recording_mbid},$id,'exact MBID');
 like($requests[0][1],qr{^https://api\.listenbrainz\.org/1/validate-token$},'fixed HTTPS origin');
 is($requests[0][2]{Authorization},'Token fixture-only-token','token header only');
 ok(!grep({$_->[1]=~/submit-listens|fixture-only-token/} @requests),'no scrobbling or token URL');
}
done_testing;
