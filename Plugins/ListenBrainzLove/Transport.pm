package Plugins::ListenBrainzLove::Transport;
use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);
use Slim::Networking::SimpleAsyncHTTP;
sub request {
 my ($method,$url,$headers,$body,$done)=@_;
 # Allowlist method + path: this plugin can never submit a listen.
 my $allowed=$method eq 'GET' && $url =~ m{\Ahttps://api\.listenbrainz\.org/1/(?:validate-token|user/[A-Za-z0-9_.-]+/(?:playing-now|listens\?count=100&min_ts=\d+)|feedback/user/[A-Za-z0-9_.-]+/get-feedback\?score=1&metadata=true&count=100&offset=0)\z};
 $allowed ||= $method eq 'POST' && $url eq 'https://api.listenbrainz.org/1/feedback/recording-feedback';
 return $done->('Unapproved provider request',undef) unless $allowed;
 return $done->('TLS unavailable',undef) unless Slim::Networking::SimpleAsyncHTTP->hasSSL;
 my $called=0;
 my $finish=sub {return if $called++; $done->(@_)};
 my $http=Slim::Networking::SimpleAsyncHTTP->new(sub {
  my ($response)=@_;
  return $finish->('Provider HTTP error',undef) unless $response->code==200;
  my $text=$response->content;
  return $finish->('Provider payload too large',undef) if !defined($text) || length($text)>1024*1024;
  my $data=eval {decode_json($text)};
  return $finish->('Invalid provider JSON',undef) if $@ || ref($data) ne 'HASH';
  $finish->(undef,$data);
 },sub {$finish->('Provider network error',undef)}, {
  timeout=>8,maxRedirect=>0,
  options=>{SSL_verify_mode=>1,SSL_verifycn_scheme=>'http',SSL_verifycn_name=>'api.listenbrainz.org',SSL_hostname=>'api.listenbrainz.org'},
 });
 my @h=map {($_,$headers->{$_})} sort keys %$headers;
 my $ok=eval {
  if ($method eq 'POST') {$http->post($url,@h,'Content-Type'=>'application/json',encode_json($body))}
  else {$http->get($url,@h)}
  1;
 };
 $finish->('Provider network error',undef) unless $ok;
}
1;
