use strict; use warnings; use Test::More; use lib '.', 't/lib';
BEGIN {
 sub WEBUI {0}
 for my $pkg (qw(Slim::Plugin::Base Slim::Utils::Prefs Slim::Menu::TrackInfo Slim::Player::ProtocolHandlers Slim::Networking::SimpleAsyncHTTP Slim::Control::Request Slim::Schema)) { (my $file="$pkg.pm")=~s{::}{/}g; $INC{$file}=1 }
 package Slim::Schema; our $canonical; sub objectForUrl {$canonical || bless {},'FixtureTrack'}
 package Slim::Control::Request; sub addDispatch {}
 package Slim::Plugin::Base; sub initPlugin {};
 package Slim::Utils::Prefs; sub import {no strict 'refs'; *{caller().'::preferences'}=sub{bless {},'FixturePrefs'}};
 package FixturePrefs; our %values=(token=>'fixture',username=>'tester'); sub init{} sub get{$values{$_[1]}} sub set{$values{$_[1]}=$_[2]}
 package Slim::Menu::TrackInfo; our %provider; sub registerInfoProvider {my($c,$id,%p)=@_;$provider{$id}=\%p} sub deregisterInfoProvider{delete $provider{$_[1]}}
 package Slim::Player::ProtocolHandlers; sub handlerForURL {'FixtureHandler'};
 package FixtureHandler; our $meta={artist=>'Artist',title=>'Before',version=>'Live',album=>'Album',duration=>193,tracknum=>9,musicbrainz_id=>'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'}; sub getMetadataFor { $meta }
 package FixtureTrack; our $mbid=''; sub url {'https://station.invalid/stream'} sub remote {1} sub musicbrainz_id {$mbid} sub secs {183} sub id {42}
 package FixtureCanonicalTrack; our @ISA=('FixtureTrack'); sub musicbrainz_id {'22222222-3333-4444-8555-666666666666'} sub secs {198}
 package FixtureArtist; sub new {bless {name=>$_[1]},$_[0]} sub name {$_[0]{name}}
 package FixtureAlbum; sub title {'LUX'}
 package FixtureLocalTrack; our @ISA=('FixtureTrack'); sub remote {0} sub title {'Memória'} sub artist {FixtureArtist->new('ROSALÍA')} sub album {bless {},'FixtureAlbum'} sub tracknum {14}
 sub artists {map {FixtureArtist->new($_)} ('Carminho','ROSALÍA')}
 package FixtureSong; sub currentTrack {bless {},'FixtureTrack'}
 package FixtureClient; our $playing=1; sub isPlaying {$playing} sub playingSong {bless {},'FixtureSong'}
}
my $loaded=eval {require Plugins::ListenBrainzLove::Plugin;1};
ok($loaded,'plugin adapter loads') or diag($@);
if ($loaded) {
 Plugins::ListenBrainzLove::Plugin->initPlugin;
 ok($Slim::Menu::TrackInfo::provider{listenbrainzLove},'independent TrackInfo provider');
 my $client=bless {},'FixtureClient';
 {
  local $FixtureHandler::meta={artist=>'ROSALÍA',title=>'Memória',album=>'LUX',artists=>[
   {name=>'ROSALÍA',type=>'MAIN'},{name=>'Carminho',type=>'FEATURED'},
   {name=>'ROSALÍA',type=>'MAIN'},{name=>'Other Composer',type=>'COMPOSER'},
  ]};
  my $snapshot=Plugins::ListenBrainzLove::Plugin::capture($client);
  is($snapshot->{artist},'ROSALÍA & Carminho','TIDAL capture retains all credited performers, deduplicating and excluding composers');
  ok(Plugins::ListenBrainzLove::Identity::same_recording($snapshot,'ROSALÍA & Carminho','Memória'),'real Memória lookup credit matches the complete captured artist credit');
  ok(!Plugins::ListenBrainzLove::Identity::same_recording($snapshot,'ROSALÍA','Memória'),'guest identity is not dropped to make a lookup pass');
  ok(!Plugins::ListenBrainzLove::Identity::same_recording($snapshot,'ROSALÍA & Carminho','Memória (Live)'),'complete credits do not weaken version checks');
  local $Slim::Schema::canonical=bless {},'FixtureLocalTrack';
  $snapshot=Plugins::ListenBrainzLove::Plugin::capture($client);
  is($snapshot->{artist},'ROSALÍA & Carminho','imported/local track includes ARTIST and TRACKARTIST with primary artist first');
 }
 {
  local $Slim::Schema::canonical=bless {},'FixtureCanonicalTrack';
  local $FixtureHandler::meta={artist=>'Artist',title=>'Song'};
  my $snapshot=Plugins::ListenBrainzLove::Plugin::capture($client);
  is($snapshot->{mbid},FixtureCanonicalTrack->musicbrainz_id,'read the canonical URL object used by AudioScrobbler, not only the playing-song object');
  is($snapshot->{duration},198,'canonical object supplies the AudioScrobbler duration');
 }
 {
  local $FixtureTrack::mbid='11111111-2222-4333-8444-555555555555';
  local $FixtureHandler::meta={artist=>'Artist',title=>'Song',album=>'Album',tracknum=>11};
  my $snapshot=Plugins::ListenBrainzLove::Plugin::capture($client);
  is($snapshot->{mbid},$FixtureTrack::mbid,'remote track retains the object MBID used by AudioScrobbler');
  is($snapshot->{duration},183,'remote track uses object duration when the provider omits it, like AudioScrobbler');
  local $FixtureHandler::meta={%{$FixtureHandler::meta},recording_mbid=>'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',duration=>193};
  $snapshot=Plugins::ListenBrainzLove::Plugin::capture($client);
  is($snapshot->{mbid},$FixtureHandler::meta->{recording_mbid},'fresh provider MBID retains priority');
  is($snapshot->{duration},193,'fresh provider duration retains priority');
 }
 my $menu=Plugins::ListenBrainzLove::Plugin::trackInfo($client,'https://station.invalid/stream');
 my ($captured,$returned,$playing_now_enabled,$guard,$initially_current);
 { no warnings qw(redefine once); local *Plugins::ListenBrainzLove::Core::love=sub { my($self,$track,$token,$user,$cb)=@_; $captured=$track; $playing_now_enabled=$self->{allow_playing_now}; $guard=$self->{is_current}; $initially_current=$guard->($track); $FixtureHandler::meta->{title}='After async'; $cb->({ok=>1}) };
 $FixtureHandler::meta->{title}='At click';
 $menu->[0]{url}->($client,sub{$returned=shift},{});
 }
 is($captured->{title},'At click','capture click not menu render');
 is($captured->{artist},'Artist','capture radio artist from protocol handler');
 is($captured->{version},'Live','capture version');
 is($captured->{mbid},'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee','capture radio MBID');
 is($captured->{release},'Album','capture the release used by MessyBrainz');
 is($captured->{duration},193,'capture current track duration');
 is($captured->{tracknumber},9,'capture current track number');
 ok($playing_now_enabled,'only the explicit Love action enables the playing-now fallback');
 ok($initially_current,'unchanged playing track passes the playback guard');
 ok(!$guard->($captured),'changed metadata prevents a stale playing-now notification');
 like($returned->{items}[0]{name},qr/verified/i,'success only explicit verified response');
 is($returned->{items}[0]{type},'text','success remains a visible, non-actionable menu item');
 ok(!$returned->{items}[0]{showBriefly},'XMLBrowser must not consume the success as a transient popup');
 { no warnings qw(redefine once); local *Plugins::ListenBrainzLove::Core::love=sub { $_[4]->({ok=>0,error=>'No unique recording identity'}) };
 $menu->[0]{url}->($client,sub{$returned=shift},{});
 }
 is($returned->{items}[0]{name},'ListenBrainz Love failed: No unique recording identity','failure reason remains readable');
 is($returned->{items}[0]{type},'text','failure remains a visible, non-actionable menu item');
 ok(!$returned->{items}[0]{showBriefly},'XMLBrowser must not consume the failure as a transient popup');
 my $love_calls=0;
 { no warnings qw(redefine once); local *Plugins::ListenBrainzLove::Core::love=sub { $love_calls++; $_[4]->({ok=>1}) };
 local $FixtureClient::playing=0;
 ok(!$guard->($captured),'stopped playback fails the notification guard');
 $menu->[0]{url}->($client,sub{$returned=shift},{});
 }
 is($love_calls,1,'selected recording may be loved while playback is stopped');
 like($returned->{items}[0]{name},qr/Love verified/,'stopped selection uses its own metadata');
 is($returned->{items}[0]{type},'text','TrackInfo result remains visible');
 Plugins::ListenBrainzLove::Plugin->shutdownPlugin;
 ok(!$Slim::Menu::TrackInfo::provider{listenbrainzLove},'provider cleanup');
}
done_testing;
