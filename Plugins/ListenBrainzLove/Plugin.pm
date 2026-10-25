package Plugins::ListenBrainzLove::Plugin;
use strict;
use warnings;
use utf8;
use base qw(Slim::Plugin::Base);
use Slim::Utils::Prefs;
use Slim::Menu::TrackInfo;
use Slim::Player::ProtocolHandlers;
use Slim::Control::Request;
use Slim::Schema;
use Plugins::ListenBrainzLove::Core;
my $prefs=preferences('plugin.listenbrainzlove');
my $material_registered;
my (%identity_cache,%pending);
sub getDisplayName { 'PLUGIN_LISTENBRAINZLOVE' }
sub initPlugin {
 my ($class)=@_; $class->SUPER::initPlugin(@_);
 $prefs->init({username=>'',token=>''});
 Slim::Menu::TrackInfo->registerInfoProvider(listenbrainzLove => (after=>'top',func=>\&trackInfo));
 Slim::Control::Request::addDispatch(['listenbrainzlove','love','_index','_quantity'],[1,1,1,\&loveQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','state','_index','_quantity'],[1,1,1,\&stateQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','metadata'],[1,1,0,\&metadataQuery]);
 if (main::WEBUI()) { require Plugins::ListenBrainzLove::Settings; Plugins::ListenBrainzLove::Settings->new }
}
sub postinitPlugin {
 return if $material_registered || !exists $INC{'Plugins/MaterialSkin/Plugin.pm'};
 return unless Plugins::MaterialSkin::Plugin->can('registerCustomAction');
 for my $section ('track','queue-track') {
  Plugins::MaterialSkin::Plugin::registerCustomAction($section,{
   title=>'ListenBrainz Love',
   'title-cs'=>'ListenBrainz Love',
   icon=>'favorite_border',
   lmsbrowse=>{command=>['listenbrainzlove','state'],params=>['selected_id:$ITEMID']},
  });
 }
 $material_registered=1;
}
sub shutdownPlugin { Slim::Menu::TrackInfo->deregisterInfoProvider('listenbrainzLove'); %identity_cache=(); %pending=() }
sub capture {
 my ($client)=@_;
 die 'Not playing' unless $client && $client->isPlaying;
 return _metadata($client);
}
sub _metadata {
 my ($client,$sources)=@_;
 die 'No player' unless $client;
 my $song=$client->playingSong or die 'No song';
 my $playing_track=$song->currentTrack or die 'No track';
 # AudioScrobbler resolves the canonical schema object by URL. A playing
 # Song can hold a different RemoteTrack with a different ID and metadata.
 my $track=Slim::Schema->objectForUrl({url=>$playing_track->url}) || $playing_track;
 my $object_mbid=$track->musicbrainz_id || '';
 my $playing_mbid=$playing_track->musicbrainz_id || '';
 if ($sources) {
  $sources->{object_mbid}=$object_mbid;
  $sources->{playing_mbid}=$playing_mbid;
  $sources->{object_track_id}=''.$track->id;
  $sources->{playing_track_id}=''.$playing_track->id;
 }
 my %meta;
 if ($track->remote) {
  my $handler=Slim::Player::ProtocolHandlers->handlerForURL($track->url);
  die 'No live metadata provider' unless $handler && $handler->can('getMetadataFor');
  my $remote=$handler->getMetadataFor($client,$track->url,'forceCurrent');
  die 'No live track metadata' unless ref($remote) eq 'HASH';
  my $provider_mbid=$remote->{recording_mbid}||$remote->{musicbrainz_id}||'';
  $sources->{provider_mbid}=$provider_mbid if $sources;
  # AudioScrobbler reads the object's MBID even for remote tracks, and uses
  # its duration when the protocol handler does not supply one.
  %meta=(artist=>$remote->{artist},title=>$remote->{title},version=>$remote->{version},mbid=>$provider_mbid||$object_mbid||$playing_mbid,release=>$remote->{album},duration=>$remote->{duration}||$track->secs||$playing_track->secs,tracknumber=>$remote->{tracknum},isrc=>$remote->{isrc});
 } else {
  $sources->{provider_mbid}='' if $sources;
  %meta=(artist=>$track->artist ? $track->artist->name : '',title=>$track->title,mbid=>$object_mbid,version=>'',release=>$track->album ? $track->album->title : '',duration=>$track->secs,tracknumber=>$track->tracknum,isrc=>($track->can('isrc')?$track->isrc:''));
 }
 $meta{url}=$track->url;
 return {map {$_=>defined($meta{$_}) && !ref($meta{$_}) ? "$meta{$_}" : ''} qw(artist title version mbid release duration tracknumber isrc url)};
}
sub metadataQuery {
 my ($request)=@_;
 my %sources;
 my $snapshot=eval {_metadata($request->client,\%sources)};
 return $request->setStatusBadParams unless $snapshot;
 # Stream URLs can carry credentials. Keep them inside the resolver/cache.
 $request->addResult($_,$snapshot->{$_}) for grep {$_ ne 'url'} sort keys %$snapshot;
 $request->addResult($_,$sources{$_}) for sort keys %sources;
 $request->setStatusDone;
}
sub resultText {
 my ($result)=@_;
 return 'ListenBrainz: Save not verified; the feedback may already be stored. Refresh its status.' if !$result->{ok} && $result->{uncertain};
 return 'ListenBrainz Love verified (MusicBrainz link not confirmed)' if $result->{ok} && $result->{identity} && !$result->{identity}{recording_mbid};
 return $result->{ok} ? 'ListenBrainz Love verified' : ('ListenBrainz Love failed: '.($result->{error}||'Unknown error'));
}
sub label {
 my ($en,$cs)=@_; my $language=eval {preferences('server')->get('language')}||'';
 return $language=~/\ACS\z/i ? $cs : $en;
}
sub iconFor {
 my ($result)=@_;
 my $state=!$result->{ok}?'unknown':((!exists($result->{score}) || $result->{score}==1 || ($result->{msid_score}||0)==1)?'filled':'outline');
 return '/plugins/ListenBrainzLove/html/images/heart-'.$state.'.svg';
}
sub stateText {
 my ($result)=@_;
 return label('ListenBrainz: State unknown. ','ListenBrainz: Stav není známý. ').($result->{error}||'Refresh to retry.') unless $result->{ok};
 return label('ListenBrainz: Loved (MusicBrainz linked)','ListenBrainz: Love potvrzeno (propojeno s MusicBrainz)') if $result->{score}==1 && $result->{linked};
 return label('ListenBrainz: Loved (MusicBrainz link not confirmed)','ListenBrainz: Love potvrzeno (propojení s MusicBrainz není potvrzené)') if $result->{score}==1 || ($result->{msid_score}||0)==1;
 return label('ListenBrainz: Not loved','ListenBrainz: Skladba není označená jako Love');
}
sub selectedTrack {
 my ($request)=@_;
 my $selected=$request->getParam('selected_id');
 my $id=defined($selected) && !ref($selected) && $selected=~/\A(?:track_id:)?(-?\d+)\z/ ? $1 : undef;
 my $track=eval {$request->client->playingSong->currentTrack};
 my $selected_track=defined($id) && $track ? eval {defined($track->id) && $id eq ''.$track->id ? $track : Slim::Schema->find('Track',$id)} : undef;
 return $selected_track && $selected_track->url eq $track->url ? $id : undef;
}
sub loveQuery {
 my ($request)=@_;
 my $reply=sub {
  $request->addResult('count',1);
  my $result=shift;
  $request->addResultLoop('item_loop',0,'text',resultText($result));
  $request->addResultLoop('item_loop',0,'icon',iconFor($result));
  $request->addResultLoop('item_loop',0,'type','text');
  $request->setStatusDone;
 };
 my $client=$request->client;
 return $reply->({ok=>0,error=>'The selected track is not currently playing'}) unless defined(selectedTrack($request));
 $request->setStatusProcessing;
 performLove($client,$reply);
}
sub coreFor {
 my ($client,$snapshot)=@_;
 my $clicked_url=$snapshot->{url};
 my $core=Plugins::ListenBrainzLove::Core->new(allow_playing_now=>1,is_current=>sub {
  my ($clicked)=@_; my $fresh=eval {capture($client)};
  return 0 unless $fresh && $client->playingSong->currentTrack->url eq $clicked_url;
  for my $field (qw(artist title version mbid release duration tracknumber isrc url)) { return 0 if ($fresh->{$field}||'') ne ($clicked->{$field}||'') }
  return 1;
 },cache=>\%identity_cache,transport=>sub { require Plugins::ListenBrainzLove::Transport; Plugins::ListenBrainzLove::Transport::request(@_) });
 return $core;
}
sub performLove {
 my ($client,$reply)=@_;
 my $snapshot=eval {capture($client)};
 return $reply->({ok=>0,error=>'No reliable current artist/title metadata'}) unless $snapshot;
 my $player=eval {$client->id} || "$client";
 return $reply->({ok=>0,error=>'Love is already being verified; wait for the result'}) if $pending{$player};
 $pending{$player}=1;
 coreFor($client,$snapshot)->love($snapshot,$prefs->get('token'),$prefs->get('username'),sub {delete $pending{$player}; $reply->(shift)});
}
sub performStatus {
 my ($client,$reply)=@_;
 my $snapshot=eval {_metadata($client)};
 return $reply->({ok=>0,error=>'No reliable current artist/title metadata'}) unless $snapshot;
 coreFor($client,$snapshot)->status($snapshot,$prefs->get('token'),$prefs->get('username'),$reply);
}
sub stateQuery {
 my ($request)=@_;
 my $id=selectedTrack($request);
 unless (defined $id) {
  $request->addResult('count',1);
  $request->addResultLoop('item_loop',0,'text','ListenBrainz: The selected track is not currently playing');
  $request->addResultLoop('item_loop',0,'type','text');
  return $request->setStatusDone;
 }
 $request->setStatusProcessing;
 performStatus($request->client,sub {
  my ($result)=@_;
  my @items=({text=>stateText($result),type=>'text',icon=>iconFor($result)});
  if ($request->client->isPlaying && (!$result->{ok} || $result->{score}!=1)) {
   push @items,{text=>label('Mark currently playing as Love','Označit právě hrající skladbu jako Love'),icon=>'/plugins/ListenBrainzLove/html/images/heart-outline.svg',actions=>{go=>{cmd=>['listenbrainzlove','love'],params=>{selected_id=>"track_id:$id"}}}};
  }
  push @items,{text=>label('Refresh Love status','Obnovit stav Love'),actions=>{go=>{cmd=>['listenbrainzlove','state'],params=>{selected_id=>"track_id:$id"}}}};
  $request->addResult('count',scalar @items);
  for my $index (0..$#items) {$request->addResultLoop('item_loop',$index,$_,$items[$index]{$_}) for sort keys %{$items[$index]}}
  $request->setStatusDone;
 });
}
sub trackInfo {
 my ($client,$url)=@_;
 return unless $client && $client->isPlaying && $client->playingSong && $client->playingSong->currentTrack->url eq $url;
 return [{name=>'ListenBrainz: Love currently playing',type=>'link',url=>sub {
  my ($c,$cb)=@_;
  performLove($c,sub {my $r=shift;$cb->({items=>[{name=>resultText($r),type=>'text',icon=>iconFor($r)}]})});
 }},{name=>'ListenBrainz: Love status',type=>'link',url=>sub {
  my ($c,$cb)=@_;
  performStatus($c,sub {my $r=shift;$cb->({items=>[{name=>stateText($r),type=>'text',icon=>iconFor($r)}]})});
 }}];
}
1;
