use strict; use warnings; use Test::More; use IO::Socket::INET; use HTTP::Tiny; use JSON::PP qw(encode_json decode_json); use lib '.'; use Plugins::ListenBrainzLove::Core;
# Real TCP/HTTP fake provider. Only the injected test transport maps fixed HTTPS
# request paths to loopback; no production configuration can change the host.
my $server=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>0,Listen=>5,ReuseAddr=>1) or die $!;
my $port=$server->sockport; my $id='12345678-1234-4234-8234-123456789abc';
my $pid=fork(); die $! unless defined $pid;
if(!$pid) {
 $SIG{ALRM}=sub{exit 2}; alarm 10; my $posted;
 for (1..3) {
  my $s=$server->accept or exit 3; $s->autoflush(1);
  my $line=<$s>; my %headers;
  while(my $h=<$s>) {last if $h=~/^\r?\n$/; $headers{lc $1}=$2 if $h=~/^([^:]+):\s*(.*?)\r?\n$/}
  my $body=''; my $len=$headers{'content-length'}||0;
  while(length($body)<$len) {my $n=read($s,my $chunk,$len-length($body)); last unless $n; $body.=$chunk}
  my $response;
  if($line=~m{GET /1/validate-token }) {$response={valid=>1,user_name=>'tester'}}
  elsif($line=~m{POST /1/feedback/recording-feedback } && ($headers{authorization}||'') eq 'Token loopback-fixture') {$posted=decode_json($body);$response={status=>'ok'}}
  elsif($line=~m{GET /1/feedback/user/tester/get-feedback\?} && $posted && $posted->{recording_mbid} eq $id && $posted->{score}==1) {$response={feedback=>[{%$posted}]}}
  else {exit 4}
  my $json=encode_json($response); print $s "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ".length($json)."\r\nConnection: close\r\n\r\n$json";close $s;
 }
 exit 0;
}
close $server;
local %ENV=%ENV; delete @ENV{qw(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy)}; $ENV{no_proxy}='127.0.0.1';
my $r;my @calls;
my $core=Plugins::ListenBrainzLove::Core->new(transport=>sub {
 my($method,$url,$h,$body,$cb)=@_;push @calls,$url;
 $url=~s{\Ahttps://api\.listenbrainz\.org}{http://127.0.0.1:$port} or die 'Unsafe test URL';
 my $http=HTTP::Tiny->new(timeout=>3); my $res=$http->request($method,$url,{headers=>$h,defined($body)?(content=>encode_json($body)):()});
 diag("local HTTP status=$res->{status}: $res->{content}") unless $res->{success};
 $cb->($res->{success}?undef:'HTTP error',$res->{success}?decode_json($res->{content}):undef);
});
$core->love({artist=>'A',title=>'T',mbid=>$id},'loopback-fixture','tester',sub{$r=shift});
waitpid($pid,0);is($? >> 8,0,'real local HTTP fake accepted exact three calls');ok($r->{ok},'HTTP POST and exact readback succeeded');
is(scalar @calls,3,'no extra API traffic');ok(!grep(/submit-listens/,@calls),'no submit-listens over wire');
done_testing;
