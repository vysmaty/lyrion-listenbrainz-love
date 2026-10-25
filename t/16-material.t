use strict; use warnings; use utf8; use Test::More; use lib '.';
BEGIN {
 sub WEBUI {0}
 for my $pkg (qw(Slim::Plugin::Base Slim::Utils::Prefs Slim::Menu::TrackInfo Slim::Player::ProtocolHandlers Slim::Control::Request Slim::Schema)) { (my $file="$pkg.pm")=~s{::}{/}g; $INC{$file}=1 }
 package Slim::Schema; sub objectForUrl {bless {},'MaterialTrack'} sub find {$_[2]==4200 ? bless({},'MaterialLibraryTrack') : bless({},'MaterialOtherTrack')}
 package Slim::Plugin::Base; sub initPlugin {};
 package Slim::Utils::Prefs; sub import {no strict 'refs'; *{caller().'::preferences'}=sub{bless {},'MaterialPrefs'}};
 package MaterialPrefs; sub init {} sub get {$_[1] eq 'token' ? 'fixture' : 'tester'}
 package Slim::Menu::TrackInfo; sub registerInfoProvider {} sub deregisterInfoProvider {}
 package Slim::Player::ProtocolHandlers; sub handlerForURL {'MaterialHandler'}
 package Slim::Control::Request; our @dispatch; sub addDispatch {push @dispatch,[@_]}
 package MaterialHandler; sub getMetadataFor {{artist=>'Artist',title=>'Song',album=>'Album',tracknum=>11}}
 package MaterialTrack; our $id=42; sub id {$id} sub url {'tidal://123.flc'} sub remote {1} sub musicbrainz_id {'11111111-2222-4333-8444-555555555555'} sub secs {183}
 package MaterialLibraryTrack; our @ISA=('MaterialTrack'); sub id {4200}
 package MaterialOtherTrack; our @ISA=('MaterialTrack'); sub url {'tidal://999.flc'}
 package MaterialSong; sub currentTrack {bless {},'MaterialTrack'}
 package MaterialClient; our $playing=1; sub isPlaying {$playing} sub playingSong {bless {},'MaterialSong'}
 package MaterialRequest;
 sub new {my($class,$selected)=@_;bless {params=>{selected_id=>$selected},client=>bless({},'MaterialClient')},$class}
 sub client {$_[0]{client}} sub getParam {$_[0]{params}{$_[1]}}
 sub addResult {$_[0]{result}{$_[1]}=$_[2]}
 sub addResultLoop {$_[0]{result}{$_[1]}[$_[2]]{$_[3]}=$_[4]}
 sub setStatusProcessing {$_[0]{status}='processing'} sub setStatusDone {$_[0]{status}='done'} sub setStatusBadParams {$_[0]{status}='badparams'}
}
require Plugins::ListenBrainzLove::Plugin;
Plugins::ListenBrainzLove::Plugin->initPlugin;
ok(grep($_->[0][1] eq 'love',@Slim::Control::Request::dispatch),'Love command registered');
ok(grep($_->[0][1] eq 'metadata',@Slim::Control::Request::dispatch),'read-only metadata command registered');
my $postinit=Plugins::ListenBrainzLove::Plugin->can('postinitPlugin');
ok($postinit,'post-init integration exists');
my $query=Plugins::ListenBrainzLove::Plugin->can('loveQuery');
ok($query,'Material Love query exists');
my $diagnostic=Plugins::ListenBrainzLove::Plugin->can('metadataQuery');
ok($diagnostic,'metadata diagnostic exists');
if ($postinit && $query && $diagnostic) {
 ok(eval {$postinit->();1},'Material is an optional dependency');
 {
  package Plugins::MaterialSkin::Plugin;
  our @registered;
  sub registerCustomAction {push @registered,[@_]}
 }
 local $INC{'Plugins/MaterialSkin/Plugin.pm'}=__FILE__;
 $postinit->(); $postinit->();
 is_deeply([map {$_->[0]} @Plugins::MaterialSkin::Plugin::registered],['track','queue-track'],'register each native context once');
 for my $registration (@Plugins::MaterialSkin::Plugin::registered) {
  my $action=$registration->[1];
  is($action->{icon},'favorite_border','native heart icon, separate from ratings');
  is($action->{'title-cs'},'ListenBrainz: Označit právě hrající jako Love','Czech action names its target');
  ok(utf8::is_utf8($action->{'title-cs'}),'Czech title is Unicode for the Material JSON encoder');
  is_deeply($action->{lmsbrowse},{command=>['listenbrainzlove','love'],params=>['selected_id:$ITEMID']},'action carries selected track to the server and opens readable results');
  ok(!$action->{script} && !$action->{command},'no injected script or shell command');
 }
 my ($calls,$captured,$pending)=(0);
 {
  no warnings qw(redefine once);
  local *Plugins::ListenBrainzLove::Core::love=sub {my($core,$snapshot,$token,$username,$cb)=@_;$calls++;$captured=$snapshot;$pending=$cb};
  my $request=MaterialRequest->new('track_id:42');
  $query->($request);
  is($calls,1,'queue menu invokes the same explicit Love operation');
  is($request->{status},'processing','request stays pending until feedback is verified');
  is($captured->{mbid},MaterialTrack->musicbrainz_id,'Material Love receives the object MBID');
  $pending->({ok=>1});
  is($request->{status},'done','verified callback completes the request');
  is($request->{result}{item_loop}[0]{text},'ListenBrainz Love verified','result is a visible native list item');
  is($request->{result}{count},1,'single result is bounded');
  is($request->{result}{item_loop}[0]{type},'text','result cannot submit again as an action');
  $request=MaterialRequest->new('42'); $query->($request);
  is($calls,2,'now-playing numeric item ID is also accepted');
  $pending->({ok=>0,error=>'Provider request failed'});
  like($request->{result}{item_loop}[0]{text},qr/failed: Provider request failed/,'provider failure is visible');
  for my $selected ('track_id:99','','track_id:42x','artist_id:42') {
   $request=MaterialRequest->new($selected); $query->($request);
   is($calls,2,'wrong or missing selection never loves another track');
   like($request->{result}{item_loop}[0]{text},qr/selected track is not currently playing/i,'selection failure explains the target');
  }
  local $MaterialClient::playing=0;
  $request=MaterialRequest->new('42'); $query->($request);
  is($calls,2,'stopped playback cannot submit from Material');
  like($request->{result}{item_loop}[0]{text},qr/failed/,'stopped playback has a readable error');
  $request=MaterialRequest->new('42'); $diagnostic->($request);
  is($calls,2,'diagnostic never invokes Love even while stopped');
  is($request->{result}{object_mbid},MaterialTrack->musicbrainz_id,'diagnostic identifies the AudioScrobbler object source');
  is($request->{result}{provider_mbid},'','diagnostic distinguishes absent provider MBID');
  is($request->{result}{mbid},MaterialTrack->musicbrainz_id,'diagnostic shows effective ID');
  is($request->{result}{duration},183,'diagnostic shows object duration');
  ok(!exists $request->{result}{token},'diagnostic does not expose credentials');
  {
   local $MaterialClient::playing=1;
   $request=MaterialRequest->new('track_id:4200'); $query->($request);
   is($calls,3,'library and playing-song IDs for the same URL are accepted');
   $pending->({ok=>1});
   is($request->{result}{item_loop}[0]{text},'ListenBrainz Love verified','alias reaches the common verified Love path');
   $request=MaterialRequest->new('track_id:99'); $query->($request);
   is($calls,3,'a resolved different URL still cannot love the current track');
  }
 }
}
done_testing;
