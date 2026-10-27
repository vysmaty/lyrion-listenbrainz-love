package Plugins::ListenBrainzLove::Metadata;
use strict;
use warnings;
use Slim::Utils::Timers;
use Time::HiRes ();
use Plugins::ListenBrainzLove::Identity;
my %waiting;
sub _now {Time::HiRes::time()}
sub complete {
 my ($snapshot)=@_;
 return ref($snapshot) eq 'HASH' && !grep {!Plugins::ListenBrainzLove::Identity::text($snapshot->{$_})} qw(artist title);
}
sub wait {
 my ($capture,$reply)=@_;
 return $reply->(undef) if keys(%waiting)>=32;
 my $entry={capture=>$capture,reply=>$reply,deadline=>_now()+8,attempt=>0};
 $waiting{$entry}=$entry;
 Slim::Utils::Timers::setTimer($entry,_now()+0.25,\&_poll);
}
sub _finish {
 my ($entry,$snapshot)=@_;
 return unless delete $waiting{$entry};
 Slim::Utils::Timers::killTimers($entry,\&_poll);
 my $reply=delete $entry->{reply};delete $entry->{capture};
 $reply->($snapshot);
}
sub _poll {
 my ($entry)=@_;
 return unless exists $waiting{$entry};
 return _finish($entry,undef) if _now()>=$entry->{deadline};
 my $snapshot=eval {$entry->{capture}->()};
 return _finish($entry,$snapshot) if complete($snapshot);
 return _finish($entry,undef) unless $snapshot;
 # Re-read the protocol handler's cache; never repeat a feedback operation.
 my @delays=(0.5,1,2);
 my $delay=$delays[$entry->{attempt}<2?$entry->{attempt}:2];$entry->{attempt}++;
 my $next=_now()+$delay;
 $next=$entry->{deadline} if $next>$entry->{deadline};
 Slim::Utils::Timers::setTimer($entry,$next,\&_poll);
}
sub shutdown {
 eval {_finish($_,undef)} for values %waiting;
}
1;
