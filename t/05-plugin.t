use strict; use warnings; use Test::More; use lib '.', 't/lib';
BEGIN {
 sub WEBUI {0}
 for my $pkg (qw(Slim::Plugin::Base Slim::Utils::Prefs Slim::Menu::TrackInfo Slim::Player::ProtocolHandlers Slim::Networking::SimpleAsyncHTTP)) { (my $file="$pkg.pm")=~s{::}{/}g; $INC{$file}=1 }
 package Slim::Plugin::Base; sub initPlugin {};
 package Slim::Utils::Prefs; sub import {no strict 'refs'; *{caller().'::preferences'}=sub{bless {},'FixturePrefs'}};
 package FixturePrefs; our %values=(token=>'fixture',username=>'tester'); sub init{} sub get{$values{$_[1]}} sub set{$values{$_[1]}=$_[2]}
 package Slim::Menu::TrackInfo; our %provider; sub registerInfoProvider {my($c,$id,%p)=@_;$provider{$id}=\%p} sub deregisterInfoProvider{delete $provider{$_[1]}}
 package Slim::Player::ProtocolHandlers; sub handlerForURL {'FixtureHandler'};
 package FixtureHandler; our $meta={artist=>'Artist',title=>'Before',version=>'Live',musicbrainz_id=>'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'}; sub getMetadataFor { $meta }
 package FixtureTrack; sub url {'https://station.invalid/stream'} sub remote {1}
 package FixtureSong; sub currentTrack {bless {},'FixtureTrack'}
 package FixtureClient; sub isPlaying {1} sub playingSong {bless {},'FixtureSong'}
}
my $loaded=eval {require Plugins::ListenBrainzLove::Plugin;1};
ok($loaded,'plugin adapter loads') or diag($@);
if ($loaded) {
 Plugins::ListenBrainzLove::Plugin->initPlugin;
 ok($Slim::Menu::TrackInfo::provider{listenbrainzLove},'independent TrackInfo provider');
 my $client=bless {},'FixtureClient';
 my $menu=Plugins::ListenBrainzLove::Plugin::trackInfo($client,'https://station.invalid/stream');
 my ($captured,$returned);
 { no warnings qw(redefine once); local *Plugins::ListenBrainzLove::Core::love=sub { my($self,$track,$token,$user,$cb)=@_; $captured=$track; $FixtureHandler::meta->{title}='After async'; $cb->({ok=>1}) };
 $FixtureHandler::meta->{title}='At click';
 $menu->[0]{url}->($client,sub{$returned=shift},{});
 }
 is($captured->{title},'At click','capture click not menu render');
 is($captured->{artist},'Artist','capture radio artist from protocol handler');
 is($captured->{version},'Live','capture version');
 is($captured->{mbid},'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee','capture radio MBID');
 like($returned->{items}[0]{name},qr/verified/i,'success only explicit verified response');
 Plugins::ListenBrainzLove::Plugin->shutdownPlugin;
 ok(!$Slim::Menu::TrackInfo::provider{listenbrainzLove},'provider cleanup');
}
done_testing;
