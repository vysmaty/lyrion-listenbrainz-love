package Plugins::ListenBrainzLove::Transport;
use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);
use Plugins::ListenBrainzLove::Identity;
use Encode qw(decode FB_CROAK);
use Slim::Networking::SimpleAsyncHTTP;
my $blocked_until=0;
sub _now {time}
sub _header {my ($response,$name)=@_; return eval {$response->headers->header($name)}}
sub _delay {
 my ($response,$default)=@_;
 for my $name ('Retry-After','X-RateLimit-Reset-In') {
  my $value=_header($response,$name);
  return $value>0 ? 0+$value : 1 if defined($value) && $value=~/\A\d{1,9}\z/;
 }
 return $default;
}
sub request {
 my ($method,$url,$headers,$body,$done)=@_;
 # Only feedback and a single timestamp-free playing_now are writable.
 my $uuid='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
 my $allowed=$method eq 'GET' && $url =~ m{\Ahttps://api\.listenbrainz\.org/1/(?:validate-token|user/[A-Za-z0-9_.-]+/(?:playing-now|listens\?count=100&min_ts=\d+)|feedback/user/[A-Za-z0-9_.-]+/get-feedback-for-recordings\?(?:recording_mbids=$uuid(?:&recording_msids=$uuid)?|recording_msids=$uuid))\z};
 my $value='(?:[A-Za-z0-9._~-]|%[A-F0-9]{2})+';
 if ($method eq 'GET' && length($url)<=3000 && $url =~ m{\Ahttps://api\.listenbrainz\.org/1/metadata/lookup/\?artist_name=($value)&recording_name=($value)(?:&release_name=($value))?\z}) {
  my @values=grep {defined} ($1,$2,$3);
  $allowed=eval {
   my $length=0;
   for my $value (@values) {
    $value=~s/%([A-F0-9]{2})/chr(hex($1))/ge;
    my $decoded=decode('UTF-8',$value,FB_CROAK);
    die 'Invalid lookup text' unless Plugins::ListenBrainzLove::Identity::text($decoded);
    $length+=length($decoded);
   }
   $length<=250;
  } || 0;
 }
 if ($method eq 'POST' && $url eq 'https://api.listenbrainz.org/1/feedback/recording-feedback') {
  $allowed=ref($body) eq 'HASH' && defined($body->{score}) && !ref($body->{score}) && $body->{score} eq '1'
   && (exists($body->{recording_mbid}) || exists($body->{recording_msid}))
   && !grep {$_ ne 'score' && (($_ ne 'recording_mbid' && $_ ne 'recording_msid') || !Plugins::ListenBrainzLove::Identity::uuid($body->{$_}))} keys %$body;
 }
 if($method eq 'POST' && $url eq 'https://api.listenbrainz.org/1/submit-listens?return_msid=true') {
  $allowed=ref($body) eq 'HASH' && scalar(keys %$body)==2 && ($body->{listen_type}||'') eq 'playing_now'
   && ref($body->{payload}) eq 'ARRAY' && @{$body->{payload}}==1
   && ref($body->{payload}[0]) eq 'HASH' && scalar(keys %{$body->{payload}[0]})==1
   && ref($body->{payload}[0]{track_metadata}) eq 'HASH';
  if($allowed) {
   my $metadata=$body->{payload}[0]{track_metadata};
   $allowed=!grep { !defined($metadata->{$_}) || ref($metadata->{$_}) || $metadata->{$_}!~/\S/ || $metadata->{$_}=~/[\x00-\x1f\x7f]/ } qw(artist_name track_name);
  }
 }
 return $done->('Unapproved provider request',undef) unless $allowed;
 return $done->('Provider rate limit; retry shortly',undef) if _now()<$blocked_until;
 return $done->('TLS unavailable',undef) unless Slim::Networking::SimpleAsyncHTTP->hasSSL;
 my $called=0;
 my $finish=sub {return if $called++; $done->(@_)};
 my $http=Slim::Networking::SimpleAsyncHTTP->new(sub {
  my ($response)=@_;
  if ($response->code==429) {
   $blocked_until=_now()+_delay($response,30);
   return $finish->('Provider rate limit; retry shortly',undef);
  }
  my $remaining=_header($response,'X-RateLimit-Remaining');
  $blocked_until=_now()+_delay($response,1) if defined($remaining) && $remaining eq '0';
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
 my %headers=(%$headers,Accept=>'application/json','User-Agent'=>'ListenBrainzLove/0.5.1 (+https://github.com/vysmaty/lyrion-listenbrainz-love)');
 my @h=map {($_,$headers{$_})} sort keys %headers;
 my $ok=eval {
  if ($method eq 'POST') {$http->post($url,@h,'Content-Type'=>'application/json',encode_json($body))}
  else {$http->get($url,@h)}
  1;
 };
 $finish->('Provider network error',undef) unless $ok;
}
1;
