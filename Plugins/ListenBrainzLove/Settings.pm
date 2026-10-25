package Plugins::ListenBrainzLove::Settings;
use strict;
use warnings;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Plugins::ListenBrainzLove::Transport;
my $prefs=preferences('plugin.listenbrainzlove');
sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_LISTENBRAINZLOVE') }
sub page { Slim::Web::HTTP::CSRF->protectURI('plugins/ListenBrainzLove/settings/basic.html') }
sub handler {
 my ($class,$client,$params,$callback,@args)=@_;
 my $token=delete $params->{token};
 delete $params->{pref_token};
 my $render=sub {
  $params->{username}=$prefs->get('username')||'';
  $params->{material_button}=$prefs->get('material_button')||0;
  delete $params->{saveSettings};
  return $class->SUPER::handler($client,$params);
 };
 return $render->() unless $params->{saveSettings};
 my $user=$params->{username};
 $token=$prefs->get('token') unless defined($token) && length($token);
 my $finish=sub {
  my ($ok)=@_;
  $params->{warning}=$ok ? 'ListenBrainz credentials verified.' : 'ListenBrainz validation failed; settings unchanged.';
  my $body=$render->(); $callback->($client,$params,$body,@args);
 };
 unless (defined($token) && $token =~ /\A[^\s\x00-\x1f\x7f]{1,256}\z/ && defined($user) && $user =~ /\A[A-Za-z0-9_.-]{1,64}\z/) { $finish->(0); return }
 Plugins::ListenBrainzLove::Transport::request('GET','https://api.listenbrainz.org/1/validate-token',{Authorization=>'Token '.$token},undef,sub {
  my ($error,$data)=@_;
  my $ok=!$error && ref($data) eq 'HASH' && defined($data->{valid}) && "$data->{valid}" eq '1' && ($data->{user_name}||'') eq $user;
  if ($ok) {
   my $enabled=($params->{material_button}||'') eq '1'?1:0;
   my $installed=eval {require Plugins::ListenBrainzLove::Material;Plugins::ListenBrainzLove::Material::configure($enabled);1};
   unless ($installed) {$params->{warning}='Material button setup failed; settings unchanged.';$callback->($client,$params,$render->(),@args);return}
   $prefs->set('token',$token); $prefs->set('username',$user);$prefs->set('material_button',$enabled);
  }
  $finish->($ok);
 });
 return;
}
1;
