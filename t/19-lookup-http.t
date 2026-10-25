use strict; use warnings; use utf8; use Test::More;
use IO::Socket::INET; use HTTP::Tiny; use JSON::PP qw(encode_json decode_json); use lib '.';
use Plugins::ListenBrainzLove::Core;
my $server=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>0,Listen=>8,ReuseAddr=>1) or die $!;
my $port=$server->sockport;my $id='11111111-2222-4333-8444-555555555555';
my $pid=fork();die $! unless defined $pid;
if (!$pid) {
 $SIG{ALRM}=sub{exit 2};alarm 10;my $posted;
 for (1..6) {
  my $socket=$server->accept or exit 3;$socket->autoflush(1);
  my $request=<$socket>;my %headers;
  while (my $line=<$socket>) {last if $line=~/^\r?\n$/;$headers{lc $1}=$2 if $line=~/^([^:]+):\s*(.*?)\r?\n$/}
  my $body='';my $length=$headers{'content-length'}||0;
  while (length($body)<$length) {my $n=read($socket,my $part,$length-length($body));last unless $n;$body.=$part}
  exit 4 unless ($headers{authorization}||'') eq 'Token loopback-fixture';
  my $response;
  if ($request=~m{GET /1/validate-token }) {$response={valid=>1,user_name=>'tester'}}
  elsif ($request=~m{GET /1/user/tester/(?:playing-now|listens\?count=100&min_ts=\d+) }) {$response={payload=>{listens=>[]}}}
  elsif ($request=~m{GET /1/metadata/lookup/\?artist_name=Karel%20Pl%C3%ADhal&recording_name=P%C5%99%C3%ADtel&release_name=Album }) {$response={recording_mbid=>$id,recording_name=>'Přítel',artist_credit_name=>'Karel Plíhal'}}
  elsif ($request=~m{POST /1/feedback/recording-feedback }) {
   $posted=decode_json($body);exit 5 unless $posted->{recording_mbid} eq $id && $posted->{score}==1 && keys(%$posted)==2;
   $response={status=>'ok'};
  }
  elsif ($request=~m{GET /1/feedback/user/tester/get-feedback-for-recordings\?recording_mbids=$id } && $posted) {$response={feedback=>[ $posted ]}}
  else {exit 6}
  my $json=encode_json($response);
  print $socket "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ".length($json)."\r\nConnection: close\r\n\r\n$json";
  close $socket;
 }
 exit 0;
}
close $server;
local %ENV=%ENV;delete @ENV{qw(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy)};$ENV{no_proxy}='127.0.0.1';
my ($result,@calls);
my $core=Plugins::ListenBrainzLove::Core->new(transport=>sub {
 my ($method,$url,$headers,$body,$cb)=@_;push @calls,[$method,$url];
 $url=~s{\Ahttps://api\.listenbrainz\.org}{http://127.0.0.1:$port} or die 'Unsafe test URL';
 my $response=HTTP::Tiny->new(timeout=>3)->request($method,$url,{headers=>$headers,defined($body)?(content=>encode_json($body)):()});
 $cb->($response->{success}?undef:'HTTP failure',$response->{success}?decode_json($response->{content}):undef);
});
$core->love({artist=>'Karel Plíhal',title=>'Přítel',release=>'Album'},'loopback-fixture','tester',sub{$result=shift});
waitpid($pid,0);
is($? >> 8,0,'real local HTTP verified lookup, auth, Unicode, exact feedback and targeted readback');
ok($result->{ok} && $result->{linked},'lookup-before-first-scrobble completes with an MBID');
is(scalar @calls,6,'only the bounded documented requests are made');
is(scalar(grep {$_->[0] eq 'POST'} @calls),1,'only the explicit feedback writes');
ok(!grep($_->[1]=~/submit-listens|manual_mapping/,@calls),'no notification, scrobble or manual mapping over the wire');
done_testing;
