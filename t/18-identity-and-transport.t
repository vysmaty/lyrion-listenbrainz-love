use strict; use warnings; use utf8; use Test::More; use lib '.';
use Plugins::ListenBrainzLove::Identity;
BEGIN {
 $INC{'Slim/Utils/Timers.pm'}=1;
 package Slim::Utils::Timers;sub killTimers {} sub setTimer {die 'Unexpected timer in immediate-response fixture'}
 package main;
 $INC{'Slim/Networking/SimpleAsyncHTTP.pm'}=1;
 package Slim::Networking::SimpleAsyncHTTP;
 our (@calls,$status);$status=200;
 sub hasSSL {1}
 sub new {my ($class,$ok,$err,$args)=@_;bless {ok=>$ok},$class}
 sub get {my ($self,@request)=@_;push @calls,\@request;$self->{ok}->($self)}
 sub post {shift->get(@_)} sub code {$status} sub content {'{"status":"ok"}'}
}
use Plugins::ListenBrainzLove::Transport;
{no warnings 'redefine';my $tick=0;*Plugins::ListenBrainzLove::Transport::_now=sub {$tick+=2}}
my $mbid='11111111-2222-4333-8444-555555555555';
my $msid='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $origin='https://api.listenbrainz.org';
for my $case (
 ['GET',"$origin/1/metadata/lookup/?artist_name=Radost&recording_name=Inspektor%20Drahota",undef,1],
 ['GET',"$origin/1/metadata/lookup/?artist_name=Karel%20Pl%C3%ADhal&recording_name=P%C5%99%C3%ADtel&release_name=Album",undef,1],
 ['GET',"$origin/1/metadata/lookup/?artist_name=A&recording_name=T&incs=artist",undef,0],
 ['GET',"$origin/1/metadata/lookup/?artist_name=A&recording_name=T&token=secret",undef,0],
 ['GET',"$origin/1/metadata/lookup/?artist_name=A&recording_name=%0AT",undef,0],
 ['GET',"$origin/1/metadata/lookup/?artist_name=A&recording_name=%FF",undef,0],
 ['GET',"$origin/1/metadata/lookup/?artist_name=A&recording_name=".('t'x250),undef,0],
 ['GET',"$origin/1/feedback/user/tester/get-feedback-for-recordings?recording_mbids=$mbid&recording_msids=$msid",undef,1],
 ['GET',"$origin/1/feedback/user/tester/get-feedback-for-recordings?recording_msids=$msid",undef,1],
 ['GET',"$origin/1/feedback/user/tester/get-feedback-for-recordings?recording_mbids=$mbid,$mbid",undef,0],
 ['POST',"$origin/1/feedback/recording-feedback",{recording_mbid=>$mbid,recording_msid=>$msid,score=>1},1],
 ['POST',"$origin/1/feedback/recording-feedback",{recording_mbid=>$mbid,score=>0},1],
 ['POST',"$origin/1/feedback/recording-feedback",{recording_mbid=>$mbid,score=>-1},0],
 ['POST',"$origin/1/feedback/recording-feedback",{recording_mbid=>'invalid',score=>1},0],
 ['POST',"$origin/1/metadata/submit_manual_mapping",{recording_mbid=>$mbid,recording_msid=>$msid},0],
) {
 my ($method,$url,$body,$allowed)=@$case;my $error;my $before=@Slim::Networking::SimpleAsyncHTTP::calls;
 Plugins::ListenBrainzLove::Transport::request($method,$url,{Authorization=>'Token fixture-only'},$body,sub {$error=shift});
 is($error?0:1,$allowed,"transport policy: $method $url");
 is(scalar(@Slim::Networking::SimpleAsyncHTTP::calls)-$before,$allowed,'rejected operation never reaches HTTP');
}
my $track={artist=>'Radost',title=>'Inspektor Drahota',version=>''};
ok(Plugins::ListenBrainzLove::Identity::same_recording($track,'RADOST','Inspektor Drahota'),'case normalization preserves the recording');
ok(!Plugins::ListenBrainzLove::Identity::same_recording($track,'Radost','Inspektor Drahota (Live)'),'live label cannot be stripped');
ok(!Plugins::ListenBrainzLove::Identity::same_recording($track,'Other','Inspektor Drahota'),'same title by another artist cannot match');
is(Plugins::ListenBrainzLove::Identity::title({title=>'Song - Live',version=>'Live'}),'Song - Live','existing version qualifier is not duplicated');
is(Plugins::ListenBrainzLove::Identity::title({title=>'Song',version=>'Acoustic'}),'Song (Acoustic)','separate version participates in lookup');
like(Plugins::ListenBrainzLove::Identity::escape('Příliš & žluťoučký'),qr/P%C5%99%C3%ADli%C5%A1%20%26%20/,'Unicode and reserved query characters use UTF-8 escaping');
my $meta={artist_name=>'Radost',track_name=>'Inspektor Drahota',additional_info=>{duration_ms=>180000}};
ok(Plugins::ListenBrainzLove::Identity::same_recording({artist=>'Artist',title=>'Song featuring Guest'},'Artist feat. Guest','Song'),'explicit guest credit can move between title and artist without changing identity');
ok(Plugins::ListenBrainzLove::Identity::same_recording({artist=>'Artist feat. Guest',title=>'Song'},'Artist & Guest','Song'),'explicit featured artist separators normalize consistently');
ok(!Plugins::ListenBrainzLove::Identity::same_recording({artist=>'Artist',title=>'Song featuring Guest'},'Artist','Song'),'guest credit is never simply discarded');
ok(!Plugins::ListenBrainzLove::Identity::same_recording({artist=>'Artist',title=>'Song (feat. Guest)',version=>'Live'},'Artist feat. Guest','Song'),'moving guest credits never removes a required live version');
ok(Plugins::ListenBrainzLove::Identity::same_listen({%$track,duration=>182},$meta),'three-second listen duration tolerance');
ok(!Plugins::ListenBrainzLove::Identity::same_listen({%$track,duration=>190},$meta),'different duration cannot silently reuse a listen');
{
 no warnings qw(redefine once);
 my $now=1000;
 local *Plugins::ListenBrainzLove::Transport::_now=sub {$now};
 local $Slim::Networking::SimpleAsyncHTTP::status=429;
 my $error;
 Plugins::ListenBrainzLove::Transport::request('GET',"$origin/1/validate-token",{},undef,sub {$error=shift});
 like($error,qr/rate limit/,'429 is classified without retrying the request');
 my $count=@Slim::Networking::SimpleAsyncHTTP::calls;
 $Slim::Networking::SimpleAsyncHTTP::status=200;
 Plugins::ListenBrainzLove::Transport::request('GET',"$origin/1/validate-token",{},undef,sub {$error=shift});
 is(scalar @Slim::Networking::SimpleAsyncHTTP::calls,$count,'cooldown protects the provider against repeated clicks');
 $now=1031;
 Plugins::ListenBrainzLove::Transport::request('GET',"$origin/1/validate-token",{},undef,sub {$error=shift});
 ok(!$error,'a manual request can succeed after the cooldown');
}
done_testing;
