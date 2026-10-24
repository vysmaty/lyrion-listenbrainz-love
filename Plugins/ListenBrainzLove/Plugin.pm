package Plugins::ListenBrainzLove::Plugin;
use strict;
use warnings;
use base qw(Slim::Plugin::Base);
use Slim::Utils::Prefs;
use Slim::Menu::TrackInfo;
use Slim::Player::ProtocolHandlers;
use Plugins::ListenBrainzLove::Core;
my $prefs=preferences('plugin.listenbrainzlove');
sub getDisplayName { 'PLUGIN_LISTENBRAINZLOVE' }
sub initPlugin {
 my ($class)=@_; $class->SUPER::initPlugin(@_);
 $prefs->init({username=>'',token=>''});
 Slim::Menu::TrackInfo->registerInfoProvider(listenbrainzLove => (after=>'top',func=>\&trackInfo));
 if (main::WEBUI()) { require Plugins::ListenBrainzLove::Settings; Plugins::ListenBrainzLove::Settings->new }
}
sub shutdownPlugin { Slim::Menu::TrackInfo->deregisterInfoProvider('listenbrainzLove') }
sub capture {
 my ($client)=@_;
 die 'Not playing' unless $client && $client->isPlaying;
 my $song=$client->playingSong or die 'No song';
 my $track=$song->currentTrack or die 'No track';
 my %meta;
 if ($track->remote) {
  my $handler=Slim::Player::ProtocolHandlers->handlerForURL($track->url);
  die 'No live metadata provider' unless $handler && $handler->can('getMetadataFor');
  my $remote=$handler->getMetadataFor($client,$track->url);
  die 'No live track metadata' unless ref($remote) eq 'HASH';
  %meta=(artist=>$remote->{artist},title=>$remote->{title},version=>$remote->{version},mbid=>$remote->{recording_mbid}||$remote->{musicbrainz_id});
 } else {
  %meta=(artist=>$track->artist ? $track->artist->name : '',title=>$track->title,mbid=>$track->musicbrainz_id,version=>'');
 }
 return {map {$_=>defined($meta{$_}) ? "$meta{$_}" : ''} qw(artist title version mbid)};
}
sub trackInfo {
 my ($client,$url)=@_;
 return unless $client && $client->isPlaying && $client->playingSong && $client->playingSong->currentTrack->url eq $url;
 return [{name=>'ListenBrainz: Love currently playing',type=>'link',url=>sub {
  my ($c,$cb)=@_;
  my $reply=sub { my($result)=@_; $cb->({items=>[{name=>$result->{ok}?'ListenBrainz Love verified':('ListenBrainz Love failed: '.($result->{error}||'Unknown error')),showBriefly=>1}]}) };
  my $snapshot=eval {capture($c)};
  return $reply->({ok=>0,error=>'No reliable current artist/title metadata'}) unless $snapshot;
  my $core=Plugins::ListenBrainzLove::Core->new(transport=>sub { require Plugins::ListenBrainzLove::Transport; Plugins::ListenBrainzLove::Transport::request(@_) });
  $core->love($snapshot,$prefs->get('token'),$prefs->get('username'),$reply);
 }}];
}
1;
