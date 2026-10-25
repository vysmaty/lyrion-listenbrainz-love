package Plugins::ListenBrainzLove::Plugin;
use strict;
use warnings;
use utf8;
use base qw(Slim::Plugin::Base);
use Slim::Utils::Prefs;
use Slim::Menu::TrackInfo;
use Slim::Player::ProtocolHandlers;
use Slim::Control::Request;
use Plugins::ListenBrainzLove::Core;
my $prefs=preferences('plugin.listenbrainzlove');
my $material_registered;
sub getDisplayName { 'PLUGIN_LISTENBRAINZLOVE' }
sub initPlugin {
 my ($class)=@_; $class->SUPER::initPlugin(@_);
 $prefs->init({username=>'',token=>''});
 Slim::Menu::TrackInfo->registerInfoProvider(listenbrainzLove => (after=>'top',func=>\&trackInfo));
 Slim::Control::Request::addDispatch(['listenbrainzlove','love','_index','_quantity'],[1,1,1,\&loveQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','metadata'],[1,1,0,\&metadataQuery]);
 if (main::WEBUI()) { require Plugins::ListenBrainzLove::Settings; Plugins::ListenBrainzLove::Settings->new }
}
sub postinitPlugin {
 return if $material_registered || !exists $INC{'Plugins/MaterialSkin/Plugin.pm'};
 return unless Plugins::MaterialSkin::Plugin->can('registerCustomAction');
 for my $section ('track','queue-track') {
  Plugins::MaterialSkin::Plugin::registerCustomAction($section,{
   title=>'ListenBrainz: Love currently playing',
   'title-cs'=>'ListenBrainz: Označit právě hrající jako Love',
   icon=>'favorite_border',
   lmsbrowse=>{command=>['listenbrainzlove','love'],params=>['selected_id:$ITEMID']},
  });
 }
 $material_registered=1;
}
sub shutdownPlugin { Slim::Menu::TrackInfo->deregisterInfoProvider('listenbrainzLove') }
sub capture {
 my ($client)=@_;
 die 'Not playing' unless $client && $client->isPlaying;
 return _metadata($client);
}
sub _metadata {
 my ($client,$sources)=@_;
 die 'No player' unless $client;
 my $song=$client->playingSong or die 'No song';
 my $track=$song->currentTrack or die 'No track';
 my $object_mbid=$track->musicbrainz_id || '';
 $sources->{object_mbid}=$object_mbid if $sources;
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
  %meta=(artist=>$remote->{artist},title=>$remote->{title},version=>$remote->{version},mbid=>$provider_mbid||$object_mbid,release=>$remote->{album},duration=>$remote->{duration}||$track->secs,tracknumber=>$remote->{tracknum});
 } else {
  $sources->{provider_mbid}='' if $sources;
  %meta=(artist=>$track->artist ? $track->artist->name : '',title=>$track->title,mbid=>$object_mbid,version=>'',release=>$track->album ? $track->album->title : '',duration=>$track->secs,tracknumber=>$track->tracknum);
 }
 return {map {$_=>defined($meta{$_}) ? "$meta{$_}" : ''} qw(artist title version mbid release duration tracknumber)};
}
sub metadataQuery {
 my ($request)=@_;
 my %sources;
 my $snapshot=eval {_metadata($request->client,\%sources)};
 return $request->setStatusBadParams unless $snapshot;
 $request->addResult($_,$snapshot->{$_}) for sort keys %$snapshot;
 $request->addResult($_,$sources{$_}) for sort keys %sources;
 $request->setStatusDone;
}
sub resultText {
 my ($result)=@_;
 return $result->{ok} ? 'ListenBrainz Love verified' : ('ListenBrainz Love failed: '.($result->{error}||'Unknown error'));
}
sub loveQuery {
 my ($request)=@_;
 my $reply=sub {
  $request->addResult('count',1);
  $request->addResultLoop('item_loop',0,'text',resultText(shift));
  $request->addResultLoop('item_loop',0,'type','text');
  $request->setStatusDone;
 };
 my $client=$request->client;
 my $selected=$request->getParam('selected_id');
 my $id=defined($selected) && !ref($selected) && $selected=~/\A(?:track_id:)?(-?\d+)\z/ ? $1 : undef;
 my $track=eval {$client->playingSong->currentTrack};
 return $reply->({ok=>0,error=>'The selected track is not currently playing'}) unless defined($id) && $track && defined($track->id) && $id eq ''.$track->id;
 $request->setStatusProcessing;
 performLove($client,$reply);
}
sub performLove {
 my ($client,$reply)=@_;
 my $snapshot=eval {capture($client)};
 return $reply->({ok=>0,error=>'No reliable current artist/title metadata'}) unless $snapshot;
 my $clicked_url=$client->playingSong->currentTrack->url;
 my $core=Plugins::ListenBrainzLove::Core->new(allow_playing_now=>1,is_current=>sub {
  my ($clicked)=@_; my $fresh=eval {capture($client)};
  return 0 unless $fresh && $client->playingSong->currentTrack->url eq $clicked_url;
  for my $field (qw(artist title version mbid release duration tracknumber)) { return 0 if ($fresh->{$field}||'') ne ($clicked->{$field}||'') }
  return 1;
 },transport=>sub { require Plugins::ListenBrainzLove::Transport; Plugins::ListenBrainzLove::Transport::request(@_) });
 $core->love($snapshot,$prefs->get('token'),$prefs->get('username'),$reply);
}
sub trackInfo {
 my ($client,$url)=@_;
 return unless $client && $client->isPlaying && $client->playingSong && $client->playingSong->currentTrack->url eq $url;
 return [{name=>'ListenBrainz: Love currently playing',type=>'link',url=>sub {
  my ($c,$cb)=@_;
  performLove($c,sub {$cb->({items=>[{name=>resultText(shift),type=>'text'}]})});
 }}];
}
1;
