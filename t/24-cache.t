use strict; use warnings; use Test::More; use lib '.';
use Plugins::ListenBrainzLove::Core;
my ($now,$score)=(1000,0);my (@calls,%state);
my $id='11111111-2222-4333-8444-555555555555';
my $track={artist=>'Artist',title=>'Song',mbid=>$id,url=>'tidal://123.flc'};
my $transport=sub {
 my ($method,$url,$headers,$body,$cb)=@_;push @calls,[$method,$url];
 return $cb->(undef,{valid=>1,user_name=>'tester'}) if $url=~/validate-token/;
 $cb->(undef,{feedback=>[{recording_mbid=>$id,score=>$score}]});
};
sub core {Plugins::ListenBrainzLove::Core->new(state=>\%state,clock=>sub {$now},transport=>$transport)}
my $r;
core()->status($track,'fixture','tester',sub {$r=shift});
is(scalar @calls,2,'first direct status validates credentials and reads feedback');
core()->status($track,'fixture','tester',sub {$r=shift});
is(scalar @calls,2,'fresh status is shared between Core instances and browser pages');
$r->{score}=1;
core()->status($track,'fixture','tester',sub {$r=shift});
is($r->{score},0,'callers cannot mutate the cached result');
$now=1031;core()->status($track,'fixture','tester',sub {$r=shift});
is(scalar @calls,3,'expired 30-second feedback cache keeps the five-minute token validation');
$score=1;core()->status($track,'fixture','tester',sub {$r=shift},{refresh=>1});
is($r->{score},1,'explicit refresh bypasses feedback cache');
is(scalar @calls,4,'explicit refresh still reuses valid authentication');
$now=1301;core()->status($track,'fixture','tester',sub {$r=shift});
is(scalar @calls,6,'token validation expires after five minutes');
core()->status($track,'different-fixture','tester',sub {$r=shift});
is(scalar @calls,8,'a changed token cannot reuse either cache');
my (@waiting,@async_calls,%async_state,@replies);
my $async=sub {my @request=@_;push @async_calls,\@request;push @waiting,$request[4]};
my $a=Plugins::ListenBrainzLove::Core->new(state=>\%async_state,clock=>sub {1000},transport=>$async);
my $b=Plugins::ListenBrainzLove::Core->new(state=>\%async_state,clock=>sub {1000},transport=>$async);
$a->status($track,'fixture','tester',sub {push @replies,shift});
$b->status($track,'fixture','tester',sub {push @replies,shift});
is(scalar @async_calls,1,'simultaneous reads of the same track share one identity/feedback operation');
shift(@waiting)->(undef,{valid=>1,user_name=>'tester'});
is(scalar @async_calls,2,'coalesced read sends only one feedback GET');
while (@waiting) {shift(@waiting)->(undef,{feedback=>[{recording_mbid=>$id,score=>0}]})}
is(scalar @replies,2,'all waiting pages receive the verified result');
ok(!grep(!$_->{ok},@replies),'coalescing preserves success for each waiter');
my (%errors,$n);$n=0;
my $bad=Plugins::ListenBrainzLove::Core->new(state=>\%errors,transport=>sub {$n++;$_[4]->('network error',undef)});
$bad->status($track,'fixture','tester',sub {});$bad->status($track,'fixture','tester',sub {});
is($n,2,'errors are never stored as a successful status or token validation');
{
 my (%race,@requests,$old,$saved,$current);
 my $make=sub {Plugins::ListenBrainzLove::Core->new(state=>\%race,clock=>sub {1000},transport=>sub {push @requests,[@_]})};
 $make->()->status($track,'fixture','tester',sub {$old=shift});
 $requests[0][4]->(undef,{valid=>1,user_name=>'tester'});
 my $stale=$requests[1][4];
 $make->()->love($track,'fixture','tester',sub {$saved=shift});
 $requests[2][4]->(undef,{status=>'ok'});
 $requests[3][4]->(undef,{feedback=>[{recording_mbid=>$id,score=>1}]});
 $stale->(undef,{feedback=>[{recording_mbid=>$id,score=>0}]});
 $make->()->status($track,'fixture','tester',sub {$current=shift});
 ok($saved->{ok} && $current->{score}==1,'a pre-write status reply cannot replace the verified write cache');
 is(scalar @requests,4,'post-write status uses the fresh verified write, not a stale in-flight read');
}
{
 require JSON::PP;
 unlike(JSON::PP::encode_json(\%state),qr/different-fixture|"fixture"/,'shared caches do not retain plaintext tokens');
}
done_testing;
