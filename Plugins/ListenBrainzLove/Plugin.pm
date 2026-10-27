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
use Time::HiRes ();
my $prefs=preferences('plugin.listenbrainzlove');
my $material_registered;
my (%identity_cache,%pending,%runtime_cache);
sub getDisplayName { 'PLUGIN_LISTENBRAINZLOVE' }
sub initPlugin {
 my ($class)=@_; $class->SUPER::initPlugin(@_);
 Plugins::ListenBrainzLove::Transport::start() if $INC{'Plugins/ListenBrainzLove/Transport.pm'} && Plugins::ListenBrainzLove::Transport->can('start');
 $prefs->init({username=>'',token=>'',material_button=>0});
 Slim::Menu::TrackInfo->registerInfoProvider(listenbrainzLove => (after=>'top',func=>\&trackInfo));
 Slim::Control::Request::addDispatch(['listenbrainzlove','love','_index','_quantity'],[1,1,1,\&loveQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','state','_index','_quantity'],[1,1,1,\&stateQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','metadata'],[1,1,0,\&metadataQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','action'],[1,1,1,\&actionQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','unlove'],[1,1,1,\&unloveQuery]);
 Slim::Control::Request::addDispatch(['listenbrainzlove','status'],[1,1,1,\&statusJsonQuery]);
 if (main::WEBUI()) { require Plugins::ListenBrainzLove::Settings; Plugins::ListenBrainzLove::Settings->new }
}
sub postinitPlugin {
 return if $material_registered || !exists $INC{'Plugins/MaterialSkin/Plugin.pm'};
 return unless Plugins::MaterialSkin::Plugin->can('registerCustomAction');
 require Plugins::ListenBrainzLove::Material;
 for my $section ('track','queue-track') {
  Plugins::MaterialSkin::Plugin::registerCustomAction($section,{
   title=>'ListenBrainz Love',
   'title-cs'=>'ListenBrainz Love',
   icon=>'favorite_border',
   script=>Plugins::ListenBrainzLove::Material::loader('love'),
  });
 }
 if (($prefs->get('material_button')||'') eq '1') {eval {Plugins::ListenBrainzLove::Material::configure(1)};warn 'ListenBrainzLove: Material button loader could not be installed' if $@}
 $material_registered=1;
}
sub shutdownPlugin {
 Slim::Menu::TrackInfo->deregisterInfoProvider('listenbrainzLove');
 Plugins::ListenBrainzLove::Transport::shutdown() if $INC{'Plugins/ListenBrainzLove/Transport.pm'} && Plugins::ListenBrainzLove::Transport->can('shutdown');
 Plugins::ListenBrainzLove::Metadata::shutdown() if $INC{'Plugins/ListenBrainzLove/Metadata.pm'};
 %identity_cache=();%pending=();%runtime_cache=();
}
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
 return _trackMetadata($client,$playing_track,$sources);
}
sub artistCredit {
 my ($primary,@performers)=@_;
 return $primary unless Plugins::ListenBrainzLove::Identity::text($primary);
 my (%seen,@credit);
 for my $name ($primary,@performers) {
  next unless Plugins::ListenBrainzLove::Identity::text($name);
  my $key=Plugins::ListenBrainzLove::Identity::normal($name);
  push @credit,$name unless $seen{$key}++;
 }
 return join(' & ',@credit);
}
sub _trackMetadata {
 my ($client,$selected,$sources)=@_;
 die 'No selected track' unless $client && $selected && $selected->url;
 my $playing_track=eval {$client->playingSong->currentTrack};
 my $same_current=$playing_track && $playing_track->url eq $selected->url;
 # AudioScrobbler resolves the canonical schema object by URL. A playing
 # Song can hold a different RemoteTrack with a different ID and metadata.
 my $canonical=Slim::Schema->objectForUrl({url=>$selected->url});
 my $track=$canonical && $canonical->url eq $selected->url ? $canonical : $selected;
 my $object_mbid=$track->musicbrainz_id || '';
 my $playing_mbid=$same_current ? ($playing_track->musicbrainz_id || '') : '';
 if ($sources) {
  $sources->{object_mbid}=$object_mbid;
  $sources->{playing_mbid}=$playing_mbid;
  $sources->{object_track_id}=''.$track->id;
  $sources->{playing_track_id}=$same_current ? ''.$playing_track->id : '';
 }
 my %meta;
 if ($track->remote) {
  my $handler=Slim::Player::ProtocolHandlers->handlerForURL($track->url);
  die 'No live metadata provider' unless $handler && $handler->can('getMetadataFor');
  # forceCurrent can make a provider return the active stream's metadata.
  # An inactive selection must be queried by its own URL instead.
  my $remote=$same_current && $client->isPlaying ? $handler->getMetadataFor($client,$track->url,'forceCurrent') : $handler->getMetadataFor($client,$track->url);
  die 'No live track metadata' unless ref($remote) eq 'HASH';
  die 'Selected stream has no reliable fixed-track metadata' unless ($same_current && $client->isPlaying) || ($track->secs || 0)>0;
  my $provider_mbid=$remote->{recording_mbid}||$remote->{musicbrainz_id}||'';
  # TIDAL's scalar artist contains only the primary artist. Its artists
  # collection retains MAIN/FEATURED performers, including guests that
  # MusicBrainz includes in artist_credit_name. Do not add other roles.
  my @performers=ref($remote->{artists}) eq 'ARRAY' ? map {$_->{name}} grep {
   ref($_) eq 'HASH' && (($_->{type}||'')=~/\A(?:MAIN|FEATURED)\z/ || (!$_->{type} && $_->{main}))
  } @{$remote->{artists}} : ();
  $sources->{provider_mbid}=$provider_mbid if $sources;
  # AudioScrobbler reads the object's MBID even for remote tracks, and uses
  # its duration when the protocol handler does not supply one.
  %meta=(artist=>artistCredit($remote->{artist},@performers),title=>$remote->{title},version=>$remote->{version},mbid=>$provider_mbid||$object_mbid||$playing_mbid,release=>$remote->{album},duration=>$remote->{duration}||$track->secs||($same_current?$playing_track->secs:0),tracknumber=>$remote->{tracknum},isrc=>$remote->{isrc});
 } else {
  $sources->{provider_mbid}='' if $sources;
  my @performers=$track->can('artists') ? map {$_->name} $track->artists : ();
  %meta=(artist=>artistCredit($track->artist ? $track->artist->name : '',@performers),title=>$track->title,mbid=>$object_mbid,version=>'',release=>$track->album ? $track->album->title : '',duration=>$track->secs,tracknumber=>$track->tracknum,isrc=>($track->can('isrc')?$track->isrc:''));
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
 if (($result->{action}||'') eq 'unlove') {
  return label('ListenBrainz: Love removed','ListenBrainz: Love zrušeno') if $result->{ok};
  return label('ListenBrainz: Removal not verified. Refresh the Love status.','ListenBrainz: Zrušení není ověřené. Obnovte stav Love.') if $result->{uncertain};
  return label('ListenBrainz: Could not remove Love: ','ListenBrainz: Love se nepodařilo zrušit: ').($result->{error}||'Unknown error');
 }
 return label('ListenBrainz: Save not verified; the feedback may already be stored. Refresh its status.','ListenBrainz: Uložení není ověřené; Love už může být uložené. Obnovte stav.') if !$result->{ok} && $result->{uncertain};
 return label('ListenBrainz Love verified (MusicBrainz link not confirmed)','ListenBrainz: Love potvrzeno (propojení s MusicBrainz není potvrzené)') if $result->{ok} && $result->{identity} && !$result->{identity}{recording_mbid};
 return $result->{ok} ? label('ListenBrainz Love verified','ListenBrainz: Love potvrzeno') : (label('ListenBrainz Love failed: ','ListenBrainz: Love se nepodařilo uložit: ').($result->{error}||'Unknown error'));
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
 return unless defined($id);
 my $playing_track=eval {$request->client->playingSong->currentTrack};
 my $selected_track=eval {$playing_track && defined($playing_track->id) && $id eq ''.$playing_track->id ? $playing_track : Slim::Schema->find('Track',$id)};
 return $selected_track && defined($selected_track->id) && $id eq ''.$selected_track->id && $selected_track->url ? $selected_track : undef;
}
sub jsonQuery {
 my ($request,$write)=@_;
 my $selected=selectedTrack($request);
 my $reply=sub {
  my ($result)=@_;
  $result->{action}='unlove' if $write eq 'unlove';
  $request->addResult('ok',$result->{ok}?1:0);
  $request->addResult('uncertain',$result->{uncertain}?1:0);
  $request->addResult('message',$write?resultText($result):stateText($result));
  $request->addResult('error',$result->{error}) unless $result->{ok};
  $request->addResult('score',($result->{msid_score}||0)==1?1:$result->{score}) if exists $result->{score};
  $request->addResult('linked',$result->{linked} && ($result->{score}||0)==1?1:0);
  $request->setStatusDone;
 };
 return $reply->({ok=>0,error=>'The selected track is unavailable; open its menu again'}) unless $selected;
 $request->setStatusProcessing;
 return $write ? performLove($request->client,$reply,$selected,$write eq 'unlove'?'unlove':'love') : performStatus($request->client,$reply,$selected,($request->getParam('refresh')||'') eq '1');
}
sub actionQuery {jsonQuery($_[0],1)}
sub unloveQuery {
 return ($_[0]->getParam('popup')||'') eq '1' ? trackFeedbackQuery($_[0],'unlove') : jsonQuery($_[0],'unlove');
}
sub statusJsonQuery {jsonQuery($_[0],0)}
sub loveQuery {trackFeedbackQuery($_[0],'love')}
sub trackFeedbackQuery {
 my ($request,$mode)=@_;
 my $selected=selectedTrack($request);
 my $popup=($request->getParam('popup')||'') eq '1';
 my $reply=sub {
  $request->addResult('count',1);
  my $result=shift;
  $result->{action}=$mode;
  $request->addResultLoop('item_loop',0,'text',resultText($result));
  # Material converts text with an image to type=other, which makes its
  # nextWindow popup fall back to the action title instead of this result.
  $request->addResultLoop('item_loop',0,'icon',iconFor($result)) unless $popup;
  $request->addResultLoop('item_loop',0,'type',$selected && !$popup?'link':'text');
  # Material wraps a lone non-actionable text row in an HTML div before
  # forwarding it to its plain-text snackbar. A genuine read-only status
  # action keeps the result plain, without permitting another Love write.
  $request->addResultLoop('item_loop',0,'actions',stateAction($selected?$selected->id:undef,$popup)) if $selected || $popup;
  $request->setStatusDone;
 };
 my $client=$request->client;
 return $reply->({ok=>0,error=>'The selected track is unavailable; open its menu again'}) unless $selected;
 $request->setStatusProcessing;
 performLove($client,$reply,$selected,$mode);
}
sub stateAction {
 my ($id,$direct)=@_;
 return {go=>{cmd=>['listenbrainzlove','state',($direct?(0,1):())],defined($id)?(params=>{selected_id=>'track_id:'.$id}):()}};
}
sub coreFor {
 my ($client,$snapshot,$deadline)=@_;
 my $clicked_url=$snapshot->{url};
 my $is_current=sub {
  my ($clicked)=@_; my $fresh=eval {capture($client)};
  return 0 unless $fresh && $client->playingSong->currentTrack->url eq $clicked_url;
  for my $field (qw(artist title version mbid release duration tracknumber isrc url)) { return 0 if ($fresh->{$field}||'') ne ($clicked->{$field}||'') }
  return 1;
 };
 my $core=Plugins::ListenBrainzLove::Core->new(deadline=>$deadline,clock=>sub {Time::HiRes::time()},allow_playing_now=>$is_current->($snapshot)?1:0,is_current=>$is_current,cache=>\%identity_cache,state=>\%runtime_cache,transport=>sub { require Plugins::ListenBrainzLove::Transport; Plugins::ListenBrainzLove::Transport::request(@_) });
 return $core;
}
sub prepareMetadata {
 my ($client,$selected,$reply)=@_;
 # Freeze the selected source before yielding to the provider. Never capture
 # a replacement now-playing track when its asynchronous metadata arrives.
 $selected ||= eval {$client->isPlaying && $client->playingSong->currentTrack};
 my $url=eval {$selected->url};
 return $reply->(undef) unless $url;
 my $capture=sub {die 'Selection changed' unless $selected->url eq $url;_trackMetadata($client,$selected)};
 my $snapshot=eval {$capture->()};
 return $reply->($snapshot) if $snapshot && !grep {!Plugins::ListenBrainzLove::Identity::text($snapshot->{$_})} qw(artist title);
 return $reply->(undef) unless $snapshot && $selected->remote;
 require Plugins::ListenBrainzLove::Metadata;
 Plugins::ListenBrainzLove::Metadata::wait($capture,$reply);
}
sub performLove {
 my ($client,$reply,$selected,$mode)=@_;$mode||='love';
 my $deadline=Time::HiRes::time()+30;
 my $player=eval {$client->id} || "$client";
 return $reply->({ok=>0,error=>'Love is already being verified; wait for the result'}) if $pending{$player};
 $pending{$player}=1;
 my $finished=0;
 my $finish=sub {return if $finished++;delete $pending{$player};$reply->(shift)};
 prepareMetadata($client,$selected,sub {
  my $snapshot=shift;
  return $finish->({ok=>0,error=>'No reliable selected-track metadata; refresh after the provider loads it'}) unless $snapshot;
  coreFor($client,$snapshot,$deadline)->$mode($snapshot,$prefs->get('token'),$prefs->get('username'),$finish);
 });
}
sub performStatus {
 my ($client,$reply,$selected,$refresh)=@_;
 my $deadline=Time::HiRes::time()+30;
 prepareMetadata($client,$selected,sub {
  my $snapshot=shift;
  return $reply->({ok=>0,error=>'No reliable selected-track metadata; refresh after the provider loads it'}) unless $snapshot;
  coreFor($client,$snapshot,$deadline)->status($snapshot,$prefs->get('token'),$prefs->get('username'),$reply,{refresh=>$refresh?1:0});
 });
}
sub stateQuery {
 my ($request)=@_;
 my $selected=selectedTrack($request);
 unless ($selected) {
  $request->addResult('count',1);
  $request->addResultLoop('item_loop',0,'text','ListenBrainz: The selected track is unavailable; open its menu again');
  $request->addResultLoop('item_loop',0,'type','text');
  return $request->setStatusDone;
 }
 $request->setStatusProcessing;
 my $id=$selected->id;
 performStatus($request->client,sub {
  my ($result)=@_;
  my @items=({text=>stateText($result),type=>'link',icon=>iconFor($result),actions=>stateAction($id)});
  if (!$result->{ok} || $result->{score}!=1) {
   push @items,{text=>label('Mark selected track as Love','Označit vybranou skladbu jako Love'),type=>'link',icon=>'/plugins/ListenBrainzLove/html/images/heart-outline.svg',actions=>{go=>{cmd=>['listenbrainzlove','love'],params=>{selected_id=>"track_id:$id"}}}};
  }
  # Material hides all images when a short list has only one distinct image.
  # A real refresh icon keeps the state heart visible in every state.
  push @items,{text=>label('Refresh Love status','Obnovit stav Love'),type=>'link',icon=>'/plugins/ListenBrainzLove/html/images/refresh.svg',actions=>stateAction($id)};
  $request->addResult('count',scalar @items);
  for my $index (0..$#items) {$request->addResultLoop('item_loop',$index,$_,$items[$index]{$_}) for sort keys %{$items[$index]}}
  $request->setStatusDone;
 },$selected,1);
}
sub trackInfo {
 my ($client,$url,$selected)=@_;
 return unless $client && $url;
 $selected ||= Slim::Schema->objectForUrl({url=>$url});
 return unless $selected && $selected->url eq $url;
 return [trackInfoAction($selected,'love'),trackInfoAction($selected,'unlove'),{name=>'ListenBrainz: Love status',type=>'link',url=>sub {
  my ($c,$cb)=@_;
  performStatus($c,sub {my $r=shift;$cb->({items=>[{name=>stateText($r),type=>'text',icon=>iconFor($r)}]})},$selected,1);
 }}];
}
sub trackInfoAction {
 my ($selected,$mode)=@_;
 my $verb=$mode eq 'unlove'?'Unlove':'Love';
 # Leave type unset so Material infers a text action and handles its popup.
 # Only the Love browse command takes positional index/count arguments;
 # Unlove retains its existing tag-only JSON command contract.
 return {name=>"ListenBrainz: $verb track",jive=>{actions=>{go=>{
  cmd=>['listenbrainzlove',$mode,($mode eq 'love'?(0,1):())],params=>{selected_id=>'track_id:'.$selected->id,popup=>1},nextWindow=>'refresh',
 }}},url=>sub {
  my ($c,$cb)=@_;
  performLove($c,sub {my $r=shift;$r->{action}=$mode;$cb->({items=>[{name=>resultText($r),type=>'text',icon=>iconFor($r)}]})},$selected,$mode);
 }};
}
1;
