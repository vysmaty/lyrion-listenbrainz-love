use strict;use warnings;use Test::More;use lib '.';
BEGIN {
 $INC{'Slim/Utils/Timers.pm'}=1;
 package Slim::Utils::Timers;
 our @timers;
 sub setTimer {push @timers,[@_]}
 sub killTimers {my($owner,$cb)=@_;@timers=grep {$_->[0] ne $owner || $_->[2] ne $cb} @timers}
}
use Plugins::ListenBrainzLove::Metadata;
use Plugins::ListenBrainzLove::Core;
my $now=1000;
{no warnings 'redefine';*Plugins::ListenBrainzLove::Metadata::_now=sub {$now}}
sub advance {
 my $until=shift;my $guard=0;
 while (@Slim::Utils::Timers::timers) {
  @Slim::Utils::Timers::timers=sort {$a->[1]<=>$b->[1]} @Slim::Utils::Timers::timers;
  last if $Slim::Utils::Timers::timers[0][1]>$until;
  die 'Unbounded timer loop' if ++$guard>100;
  my $timer=shift @Slim::Utils::Timers::timers;$now=$timer->[1];$timer->[2]->($timer->[0]);
 }
 $now=$until;
}
my ($reads,@results,$ready)=(0);
my $snapshot={artist=>'Selected Artist',title=>'Selected Song',url=>'tidal://73.flc'};
my $capture=sub {$reads++;return $ready?$snapshot:{url=>$snapshot->{url}}};
Plugins::ListenBrainzLove::Metadata::wait($capture,sub {push @results,shift});
is($reads,0,'cold preparation yields to the provider before reading again');
advance(1000.24);is($reads,0,'no busy loop while the provider is loading');
advance(1000.25);is($reads,1,'first recheck uses the LMS timer');
$ready=1;advance(1000.75);
is_deeply(\@results,[$snapshot],'ready metadata completes the original operation once');
is(scalar @Slim::Utils::Timers::timers,0,'success cancels its timer');

($reads,$ready)=(0,0);@results=();
Plugins::ListenBrainzLove::Metadata::wait($capture,sub {push @results,shift});
advance(1008.75);
is_deeply(\@results,[undef],'a provider that never fills its cache fails after eight seconds');
ok($reads<=7,'metadata polling backs off and remains bounded');
is(scalar @Slim::Utils::Timers::timers,0,'timeout leaves no timer');
$ready=1;advance(1010);is(scalar @results,1,'late provider completion cannot restart a timed-out operation');

@results=();$ready=0;
Plugins::ListenBrainzLove::Metadata::wait($capture,sub {push @results,shift});
my $late=$Slim::Utils::Timers::timers[0];
Plugins::ListenBrainzLove::Metadata::shutdown();
is_deeply(\@results,[undef],'shutdown settles pending metadata preparation');
is(scalar @Slim::Utils::Timers::timers,0,'shutdown removes metadata timers');
$ready=1;$late->[2]->($late->[0]);is(scalar @results,1,'a late timer cannot run after shutdown');

@results=();$reads=0;
Plugins::ListenBrainzLove::Metadata::wait(sub {$reads++;die 'Provider unavailable'},sub {push @results,shift});
advance(1011);
is_deeply(\@results,[undef],'provider errors settle without attempting feedback');
is($reads,1,'provider exceptions are not retried');

@results=();$ready=0;
Plugins::ListenBrainzLove::Metadata::wait($capture,sub {push @results,shift}) for 1..33;
is(scalar @Slim::Utils::Timers::timers,32,'waiting preparations have a global capacity bound');
is_deeply(\@results,[undef],'overflow fails without adding another timer');
Plugins::ListenBrainzLove::Metadata::shutdown();
is(scalar @results,33,'shutdown settles every pending callback exactly once');

my ($requests,$result,$options)=(0);
my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub {$now},deadline=>$now-1,transport=>sub {$requests++});
$core->love($snapshot,'fixture','tester',sub {$result=shift});
is($requests,0,'expired metadata preparation cannot start a later API operation');
like($result->{error},qr/expired/,'expiry is explicit before any write');
$core=Plugins::ListenBrainzLove::Core->new(clock=>sub {$now},deadline=>$now+22,transport=>sub {$requests++;$options=$_[5]});
$core->love($snapshot,'fixture','tester',sub {});
is($options->{deadline},$now+22,'provider waiting time remains part of the original 30-second operation budget');
done_testing;
