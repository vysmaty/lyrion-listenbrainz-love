use strict; use warnings; use Test::More; use lib '.';
use Plugins::ListenBrainzLove::Core;
my $id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $track={artist=>'Artist',title=>'Song (Live)',version=>'Live'};
my (@calls,@pending,$result);
my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub{1000},transport=>sub {
 my ($m,$u,$h,$b,$cb)=@_; push @calls,[$m,$u,$b]; push @pending,[$u,$cb];
});
$core->love($track,'fixture','tester',sub{$result=shift});
$track->{title}='Next radio song';
while (my $p=shift @pending) {
 my ($u,$cb)=@$p;
 $cb->(undef,$u=~/validate-token/?{valid=>1,user_name=>'tester'}:$u=~/playing-now/?{payload=>{listens=>[{recording_msid=>$id,track_metadata=>{artist_name=>'Artist',track_name=>'Song (Live)',additional_info=>{version=>'Live'}}}]}}:$u=~/\/listens\?/?{payload=>{listens=>[]}}:$u=~/metadata\/lookup/?{}:$u=~/get-feedback/?{feedback=>[{recording_msid=>$id,score=>1}]}:{status=>'ok'});
}
ok($result->{ok},'radio MSID resolved and verified despite metadata mutation after click');
my @post=grep {$_->[0] eq 'POST'} @calls;
is($post[0][2]{recording_msid},$id,'exact captured version identity');
is(scalar @post,1,'only explicit feedback write');
done_testing;
