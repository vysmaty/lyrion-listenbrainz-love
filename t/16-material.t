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
 package MaterialHandler; sub getMetadataFor {{artist=>'Artist',title=>'Song',album=>'Album',tracknum=>11,isrc=>'CZAAA2600001'}}
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
 is_deeply([map {$_->[0]} @Plugins::MaterialSkin::Plugin::registered],['track','queue-track'],'register only direct Love once in each context; status remains in TrackInfo');
 for my $registration (@Plugins::MaterialSkin::Plugin::registered) {
  my $action=$registration->[1];
  if ($action->{title} eq 'ListenBrainz Love') {
   is($action->{icon},'favorite_border','native heart icon, separate from ratings');
   like($action->{script},qr/api\.love\(pid,id\)/,'native Love invokes the explicit action through its UI module');
   unlike($action->{script},qr/\$ITEMID|\$TRACKNAME|\$ARTISTNAME/,'track data is passed as values rather than interpolated into JavaScript');
   ok(!$action->{lmsbrowse} && !$action->{command},'direct Love does not navigate or run a shell');
  } else {
   is_deeply($action->{lmsbrowse},{command=>['listenbrainzlove','state'],params=>['selected_id:$ITEMID']},'separate status entry remains a read-only native browse');
   ok(!$action->{script} && !$action->{command},'status entry needs no custom script');
  }
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
  is($request->{result}{item_loop}[0]{type},'link','result displays its heart in a native image-capable row');
  is_deeply($request->{result}{item_loop}[0]{actions}{go},{cmd=>['listenbrainzlove','state'],params=>{selected_id=>'track_id:42'}},'clicking a result reads state rather than submitting again');
  $request=MaterialRequest->new('42'); $query->($request);
  is($calls,2,'now-playing numeric item ID is also accepted');
  $pending->({ok=>0,error=>'Provider request failed'});
  like($request->{result}{item_loop}[0]{text},qr/failed: Provider request failed/,'provider failure is visible');
  for my $selected ('track_id:99','','track_id:42x','artist_id:42') {
   $request=MaterialRequest->new($selected); $query->($request);
   is($calls,2,'wrong or missing selection never loves another track');
   like($request->{result}{item_loop}[0]{text},qr/selected track is unavailable/i,'selection failure explains the target');
  }
  local $MaterialClient::playing=0;
  $request=MaterialRequest->new('42'); $query->($request);
  is($calls,3,'stopped playback can Love its selected fixed recording');
  $pending->({ok=>1});
  like($request->{result}{item_loop}[0]{text},qr/Love verified/,'stopped selection has a verified result');
  $request=MaterialRequest->new('42'); $diagnostic->($request);
  is($calls,3,'diagnostic never invokes Love even while stopped');
  is($request->{result}{object_mbid},MaterialTrack->musicbrainz_id,'diagnostic identifies the AudioScrobbler object source');
  is($request->{result}{provider_mbid},'','diagnostic distinguishes absent provider MBID');
  is($request->{result}{mbid},MaterialTrack->musicbrainz_id,'diagnostic shows effective ID');
  is($request->{result}{duration},183,'diagnostic shows object duration');
  ok(!exists $request->{result}{token},'diagnostic does not expose credentials');
  ok(!exists $request->{result}{url},'diagnostic does not expose potentially credentialed source URLs');
  is($request->{result}{isrc},'CZAAA2600001','available provider ISRC is retained without inventing an MBID');
  {
   local $MaterialClient::playing=1;
   $request=MaterialRequest->new('track_id:4200'); $query->($request);
   is($calls,4,'library and playing-song IDs for the same URL are accepted');
   $pending->({ok=>1});
   is($request->{result}{item_loop}[0]{text},'ListenBrainz Love verified','alias reaches the common verified Love path');
   $request=MaterialRequest->new('track_id:99'); $query->($request);
   is($calls,4,'an invalid ID returned by the schema cannot love a different track');
  }
 }
}
my $state=Plugins::ListenBrainzLove::Plugin->can('stateQuery');
ok($state,'read-only native state command exists');
if ($state) {
 my ($reads,$writes,$callback)=(0,0);
 no warnings qw(redefine once);
 local *Plugins::ListenBrainzLove::Core::status=sub {my($core,$snapshot,$token,$user,$cb)=@_;$reads++;$callback=$cb};
 local *Plugins::ListenBrainzLove::Core::love=sub {$writes++};
 for my $case (
  [{ok=>1,score=>1,linked=>1},'filled',2],
  [{ok=>1,score=>0,linked=>1},'outline',3],
  [{ok=>0,error=>'Provider request failed'},'unknown',3],
  [{ok=>1,score=>1,linked=>0},'filled',2],
 ) {
  my ($result,$icon,$count)=@$case;
  my $request=MaterialRequest->new('track_id:42'); $state->($request);
  is($request->{status},'processing','native loading lasts until feedback read completes');
  $callback->($result);
  is($request->{status},'done','read completes the native list');
  is($request->{result}{count},$count,'state plus explicit action/refresh are bounded');
  like($request->{result}{item_loop}[0]{icon},qr/heart-$icon\.svg$/,'icon represents the verified state');
  is($request->{result}{item_loop}[0]{type},'link','state row supports its heart image');
  is_deeply($request->{result}{item_loop}[0]{actions}{go}{cmd},['listenbrainzlove','state'],'clicking a state row remains read-only');
  is($request->{result}{item_loop}[-1]{type},'link','refresh is an explicit browse link, not a text command without list arguments');
  if ($count==3) {
   is($request->{result}{item_loop}[1]{type},'link','Love also uses explicit browse link semantics');
   is_deeply($request->{result}{item_loop}[1]{actions}{go},{cmd=>['listenbrainzlove','love'],params=>{selected_id=>'track_id:42'}},'Love is a separate explicit action bound to selection');
  }
  is($writes,0,'viewing state never invokes Love');
 }
 {
  local $MaterialClient::playing=0;
  my $request=MaterialRequest->new('42'); $state->($request);$callback->({ok=>1,score=>0});
  is($request->{result}{count},3,'paused/stopped player can read state and explicitly Love its selected recording');
 }
 my $before=$reads;
 my $request=MaterialRequest->new('99'); $state->($request);
 is($reads,$before,'wrong selection never resolves another track');
 like(Plugins::ListenBrainzLove::Plugin::resultText({ok=>0,uncertain=>1}),qr/may already be stored/,'ambiguous POST outcome is not shown as definite failure');
}
{
 no warnings qw(redefine once);
 my ($writes,$reads,$done)=(0,0);
 local *Plugins::ListenBrainzLove::Core::love=sub {$writes++;$done=$_[4]};
 local *Plugins::ListenBrainzLove::Core::status=sub {$reads++;$_[4]->({ok=>1,score=>0,linked=>1})};
 my $request=MaterialRequest->new('42');
 Plugins::ListenBrainzLove::Plugin::actionQuery($request);
 is($request->{status},'processing','direct action stays pending until verified readback');
 $done->({ok=>1,score=>1,linked=>1});
 is($request->{result}{ok},1,'verified direct action returns explicit success');
 is($request->{result}{score},1,'direct action exposes only the verified score');
 ok(!exists $request->{result}{item_loop},'direct action does not navigate to a result list');
 $request=MaterialRequest->new('42');Plugins::ListenBrainzLove::Plugin::statusJsonQuery($request);
 is($reads,1,'JSON status uses the read-only core');
 is($writes,1,'status does not resubmit Love');
 is($request->{result}{score},0,'known unloved state remains distinct from a failed read');
 $request=MaterialRequest->new('42');Plugins::ListenBrainzLove::Plugin::actionQuery($request);
 $done->({ok=>0,uncertain=>1,error=>'Readback failed'});
 is($request->{result}{uncertain},1,'uncertain write propagates to the popup response');
 like($request->{result}{message},qr/may already be stored/,'uncertain response instructs status refresh');
 $request=MaterialRequest->new('bad');Plugins::ListenBrainzLove::Plugin::actionQuery($request);
 is($writes,2,'invalid direct selection never writes the current track');
 is($request->{result}{ok},0,'invalid direct selection produces an explicit error');
}
{
 no warnings qw(redefine once);
 my ($snapshot,$done,$options);
 local *Plugins::ListenBrainzLove::Core::unlove=sub {$snapshot=$_[1];$done=$_[4]};
 local *Plugins::ListenBrainzLove::Core::status=sub {$options=$_[5];$_[4]->({ok=>1,score=>0})};
 my $request=MaterialRequest->new('42');
 Plugins::ListenBrainzLove::Plugin::unloveQuery($request);
 is($request->{status},'processing','JSON removal waits for verified feedback');
 is($snapshot->{title},'Song','JSON removal targets the selected recording metadata');
 $done->({ok=>1,score=>0});
 is($request->{result}{score},0,'JSON removal returns verified zero');
 like($request->{result}{message},qr/Love removed/,'popup distinguishes removal from adding Love');
 $request=MaterialRequest->new('42');$request->{params}{refresh}=1;
 Plugins::ListenBrainzLove::Plugin::statusJsonQuery($request);
 is_deeply($options,{refresh=>1},'explicit JSON refresh bypasses only the short feedback cache');
 my $info=Plugins::ListenBrainzLove::Plugin::trackInfo($request->client,MaterialTrack->url);
 is(scalar @$info,2,'track details retain both Love and status entries');
 like($info->[1]{name},qr/Love status/,'status remains available in the song detail');
 is_deeply($info->[0]{jive}{actions}{go},{cmd=>['listenbrainzlove','love',0,1],params=>{selected_id=>'track_id:42',popup=>1},nextWindow=>'refresh'},'native text command includes list positions before tagged selection/popup parameters');
 ok(!exists($info->[0]{type}) && !exists($info->[0]{icon}) && !exists($info->[0]{style}),'Material can infer a text action; an explicit link would bypass its popup handler');
 $request=MaterialRequest->new('42');$request->{params}{popup}=1;
 my $popup_result={ok=>1,score=>1};
 local *Plugins::ListenBrainzLove::Core::love=sub {$_[4]->($popup_result)};
 Plugins::ListenBrainzLove::Plugin::loveQuery($request);
 is($request->{result}{item_loop}[0]{type},'text','popup result is a single text row so Material uses the verified message');
 is_deeply($request->{result}{item_loop}[0]{actions}{go},{cmd=>['listenbrainzlove','state',0,1],params=>{selected_id=>'track_id:42'}},'popup result can only read status and supplies its own list positions');
 require JSON::PP;
 my $node=$ENV{NODE_BIN}||'node';
 my %client_item=map {$_=>$info->[0]{$_}} grep {exists $info->[0]{$_}} qw(name type icon style jive);
 my $language='EN';
 local *MaterialPrefs::get=sub {$_[1] eq 'language'?$language:$_[1] eq 'token'?'fixture':'tester'};
 for my $case (
  ['EN','42',{ok=>1,score=>1}],
  ['EN','42',{ok=>0,error=>'Provider request failed'}],
  ['EN','42',{ok=>0,uncertain=>1,error=>'Readback failed'}],
  ['CS','42',{ok=>1,score=>1}],
  ['CS','bad',{ok=>0}],
 ) {
  ($language,my $selected,$popup_result)=@$case;
  $request=MaterialRequest->new($selected);$request->{params}{popup}=1;
  Plugins::ListenBrainzLove::Plugin::loveQuery($request);
  open my $popup_test,'|-',$node,'t/27-material-popup.cjs' or die "Cannot start Node: $!";
  print {$popup_test} JSON::PP::encode_json({item=>\%client_item,result=>$request->{result}});
  ok(close($popup_test),'complete installed Material parser and handlers display the operation result without leaving details');
 }
}
done_testing;
