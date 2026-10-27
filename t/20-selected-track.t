use strict; use warnings; use Test::More; use lib '.';
BEGIN {
 sub WEBUI {0}
 for my $pkg (qw(Slim::Plugin::Base Slim::Utils::Prefs Slim::Menu::TrackInfo Slim::Player::ProtocolHandlers Slim::Control::Request Slim::Schema Slim::Utils::Timers Plugins::ListenBrainzLove::Transport)) { (my $file="$pkg.pm")=~s{::}{/}g; $INC{$file}=1 }
 package Slim::Utils::Timers;
 our @timers;
 sub setTimer {push @timers,[@_]}
 sub killTimers {my($owner,$cb)=@_;@timers=grep {$_->[0] ne $owner || $_->[2] ne $cb} @timers}
 package Slim::Plugin::Base; sub initPlugin {}
 package Slim::Utils::Prefs; sub import {no strict 'refs'; *{caller().'::preferences'}=sub {bless {},'SelectedPrefs'}}
 package SelectedPrefs; sub get {$_[1] eq 'token' ? 'fixture' : 'tester'}
 package Slim::Menu::TrackInfo; sub registerInfoProvider {} sub deregisterInfoProvider {}
 package Slim::Control::Request; sub addDispatch {}
 package Slim::Schema;
 sub find {$_[2]==42 || $_[2]==73 || $_[2]==74 ? bless({id=>0+$_[2]},'SelectedTrack') : undef}
 sub objectForUrl {my($class,$args)=@_;for my $id (42,73,74) {my $t=bless({id=>$id},'SelectedTrack');return $t if $t->url eq $args->{url}}return}
 package Slim::Player::ProtocolHandlers; sub handlerForURL {'SelectedHandler'}
 package SelectedHandler;
 our @calls;
 sub getMetadataFor {my($class,$client,$url,@flags)=@_;push @calls,[$url,@flags];return $url eq 'tidal://73.flc' ? {artist=>'Selected Artist',title=>'Selected Song',album=>'Selected Album',duration=>201} : {artist=>'Current Artist',title=>'Current Song',album=>'Current Album',duration=>183}}
 package SelectedTrack;
 our ($no_mbid,$stream)=(0,0);
 sub id {$_[0]{id}} sub url {'tidal://'.$_[0]{id}.'.flc'} sub remote {$_[0]{id}!=74}
 sub secs {$stream ? 0 : ($_[0]{id}==42 ? 183 : 201)} sub tracknum {7}
 sub musicbrainz_id {$no_mbid && $_[0]{id}!=42 ? '' : ($_[0]{id}==42 ? '11111111-2222-4333-8444-555555555555' : 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')}
 sub artist {bless {},'SelectedArtist'} sub album {bless {},'SelectedAlbum'} sub title {'Local selected song'}
 package SelectedArtist; sub name {'Local selected artist'}
 package SelectedAlbum; sub title {'Local selected album'}
 package SelectedSong; sub currentTrack {bless({id=>$SelectedClient::current},'SelectedTrack')}
 package SelectedClient;
 our ($current,$playing,$has_song)=(42,1,1);
 sub isPlaying {$playing} sub playingSong {$has_song ? bless({},'SelectedSong') : undef} sub id {'fixture-player'}
 package SelectedRequest;
 sub new {bless {params=>{selected_id=>$_[1]},client=>bless({},'SelectedClient')},$_[0]}
 sub client {$_[0]{client}} sub getParam {$_[0]{params}{$_[1]}}
 sub addResult {$_[0]{result}{$_[1]}=$_[2]} sub addResultLoop {$_[0]{result}{$_[1]}[$_[2]]{$_[3]}=$_[4]}
 sub setStatusProcessing {$_[0]{status}='processing'} sub setStatusDone {$_[0]{status}='done'}
 package Plugins::ListenBrainzLove::Transport;
 our (@calls,$lookup,$score);
 $lookup={recording_mbid=>'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',artist_credit_name=>'Selected Artist',recording_name=>'Selected Song'};
 $score=1;
 sub request {
  my($method,$url,$headers,$body,$cb)=@_;push @calls,[$method,$url,$body];
  return $cb->(undef,{valid=>1,user_name=>'tester'}) if $url=~/validate-token$/;
  return $cb->(undef,{payload=>{listens=>[]}}) if $url=~m{/playing-now$|/listens\?};
  return $cb->(undef,$lookup) if $url=~m{/metadata/lookup/};
  return $cb->(undef,{status=>'ok'}) if $url=~m{/recording-feedback$};
  if ($url=~/recording_mbids=([a-f0-9-]+)/) {return $cb->(undef,{feedback=>[{recording_mbid=>$1,score=>$score}]})}
  die 'Unexpected fixture request';
 }
}
require Plugins::ListenBrainzLove::Plugin;
my $target='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
my $love=Plugins::ListenBrainzLove::Plugin->can('loveQuery');
my $state=Plugins::ListenBrainzLove::Plugin->can('stateQuery');
my $request=SelectedRequest->new('track_id:73');
$love->($request);
is($request->{status},'done','non-playing selected track finishes its verified Love');
like($request->{result}{item_loop}[0]{text},qr/Love verified/,'non-playing selected track can be loved');
my @writes=grep {$_->[0] eq 'POST'} @Plugins::ListenBrainzLove::Transport::calls;
is_deeply([map {$_->[2]} @writes],[{recording_mbid=>$target,score=>1}],'only selected MBID is written, never the playing recording');
is_deeply($SelectedHandler::calls[0],['tidal://73.flc'],'remote metadata query uses selected URL without forceCurrent');

for my $case ([0,1,73,'stopped player'],[0,0,74,'player with an empty queue']) {
 local($SelectedClient::playing,$SelectedClient::has_song)=@$case[0,1];
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new('track_id:'.$case->[2]);$love->($request);
 like($request->{result}{item_loop}[0]{text},qr/Love verified/,"Love works with $case->[3]");
 @writes=grep {$_->[0] eq 'POST'} @Plugins::ListenBrainzLove::Transport::calls;
 is($writes[0][2]{recording_mbid},$target,'selection stays independent from playback');
}
{
 local $SelectedTrack::no_mbid=1;
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new('73');$love->($request);
 like($request->{result}{item_loop}[0]{text},qr/Love verified/,'non-playing track resolves through documented MBID lookup');
 my ($lookup)=grep {$_->[1]=~m{/metadata/lookup/}} @Plugins::ListenBrainzLove::Transport::calls;
 like($lookup->[1],qr/artist_name=Selected%20Artist&recording_name=Selected%20Song&release_name=Selected%20Album/,'lookup belongs to the selected track');
 ok(!grep($_->[1]=~/submit-listens/,@Plugins::ListenBrainzLove::Transport::calls),'lookup Love never announces fake playback');
 local $Plugins::ListenBrainzLove::Transport::lookup={};
 # A new source URL avoids the accepted positive cache.
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new('74');$love->($request);
 unlike($request->{result}{item_loop}[0]{text},qr/Love verified/,'unresolved non-playing track is not reported as saved');
 is(scalar(grep {$_->[0] eq 'POST'} @Plugins::ListenBrainzLove::Transport::calls),0,'unresolved selection cannot send playing_now, a listen or feedback');
}
{
 local $Plugins::ListenBrainzLove::Transport::score=0;
 local $SelectedClient::playing=0;
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new('73');$state->($request);
 is($request->{result}{count},3,'stopped selected track has explicit Love plus read-only state and refresh');
 my $rows=$request->{result}{item_loop};
 is_deeply($rows->[1]{actions}{go},{cmd=>['listenbrainzlove','love'],params=>{selected_id=>'track_id:73'}},'visible Love action keeps the selected ID');
 is($rows->[0]{type},'link','state uses image-capable native row rendering');
 is_deeply($rows->[0]{actions}{go},{cmd=>['listenbrainzlove','state'],params=>{selected_id=>'track_id:73'}},'clicking the state heart is read-only');
 ok($rows->[-1]{icon} && $rows->[-1]{icon} ne $rows->[0]{icon},'distinct refresh icon prevents Material from hiding all identical list images');
 is(scalar(grep {$_->[0] eq 'POST'} @Plugins::ListenBrainzLove::Transport::calls),0,'opening state remains read-only');
}
for my $selected ('track_id:999','','artist_id:73','73x') {
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new($selected);$love->($request);
 is(scalar @Plugins::ListenBrainzLove::Transport::calls,0,'invalid selection never falls back to the playing track');
}
{
 local $SelectedTrack::stream=1;
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new('73');$love->($request);
 is(scalar @Plugins::ListenBrainzLove::Transport::calls,0,'inactive indefinite stream cannot borrow metadata from current playback');
 like($request->{result}{item_loop}[0]{text},qr/No reliable selected-track metadata/,'unknown stream target has an explicit metadata error');
}
{
 @Plugins::ListenBrainzLove::Transport::calls=();
 my $menu=Plugins::ListenBrainzLove::Plugin::trackInfo(bless({},'SelectedClient'),'tidal://73.flc',bless({id=>73},'SelectedTrack'));
 ok($menu,'TrackInfo provides Love for a non-playing recording');
 if ($menu) {my $result;$menu->[0]{url}->(bless({},'SelectedClient'),sub {$result=shift});like($result->{items}[0]{name},qr/Love verified/,'TrackInfo loves its own selected track')}
}
{
 no warnings qw(redefine once);
 my ($ready,$calls)=(0,0);
 local *SelectedHandler::getMetadataFor=sub {
  my($class,$client,$url,@flags)=@_;push @SelectedHandler::calls,[$url,@flags];
  return {icon=>'tidal.png'} unless $ready;
  return {artist=>'Selected Artist',title=>'Selected Song',album=>'Selected Album',duration=>201};
 };
 @Plugins::ListenBrainzLove::Transport::calls=();
 $request=SelectedRequest->new('73');$love->($request);
 is($request->{status},'processing','cold remote selection waits for artist/title instead of failing the first click');
 is(scalar @Plugins::ListenBrainzLove::Transport::calls,0,'metadata preparation sends no ListenBrainz requests');
 my $duplicate=SelectedRequest->new('73');$love->($duplicate);
 like($duplicate->{result}{item_loop}[0]{text},qr/already being verified/,'write lock covers metadata preparation');
 $ready=1;
 # Provider completion can happen after playback has changed. Selection stays 73.
 local $SelectedClient::current=74;
 my $guard=0;
 while (@Slim::Utils::Timers::timers && ++$guard<20) {
  my $timer=shift @Slim::Utils::Timers::timers;$timer->[2]->($timer->[0]);
 }
 is($request->{status},'done','first click completes after the provider cache is populated');
 like($request->{result}{item_loop}[0]{text},qr/Love verified/,'cold selection receives the verified result');
 my @posts=grep {$_->[0] eq 'POST'} @Plugins::ListenBrainzLove::Transport::calls;
 is_deeply([map {$_->[2]} @posts],[{recording_mbid=>$target,score=>1}],'exactly one feedback write targets the originally selected recording');
 ok(!grep($_->[1]=~/submit-listens/,@Plugins::ListenBrainzLove::Transport::calls),'cold inactive selection cannot announce playback');
 is(scalar @Slim::Utils::Timers::timers,0,'completed metadata preparation leaves no timer');
}

done_testing;
