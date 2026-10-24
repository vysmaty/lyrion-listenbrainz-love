use strict; use warnings; use Test::More; use lib '.'; use Plugins::ListenBrainzLove::Core;
my $id='12345678-1234-4234-8234-123456789abc';
sub exercise {
 my (%cfg)=@_; my ($r,@calls); my $now=1000;
 my $core=Plugins::ListenBrainzLove::Core->new(clock=>sub{$now},transport=>sub{
  my ($m,$u,$h,$b,$cb)=@_; push @calls,[$m,$u,$b];
  if ($u=~/validate-token/) { $now=1040 if $cfg{expired}; return $cb->($cfg{transport_error},$cfg{valid}||{valid=>1,user_name=>'tester'}) }
  return $cb->(undef,$cfg{lookup}) if $u=~/playing-now|\/listens\?/;
  return $cb->(undef,$cfg{post}||{status=>'ok'}) if $m eq 'POST';
  $cb->(undef,$cfg{readback}||{feedback=>[{recording_mbid=>$id,score=>1}]});
 });
 my $ok=eval {$core->love($cfg{track}||{artist=>'A',title=>'T',mbid=>$id},$cfg{token}||'fixture-token','tester',sub{$r=shift});1};
 return ($r,\@calls,$ok);
}
for my $case (
 ['invalid token',valid=>{valid=>0,message=>'fixture-token'}],
 ['wrong user',valid=>{valid=>1,user_name=>'other'}],
 ['HTML response',valid=>'<!doctype html>fixture-token'],
 ['transport error',transport_error=>'server echoed fixture-token'],
 ['expired click',expired=>1],
 ['missing metadata',track=>{mbid=>$id}],
 ['invalid MBID',track=>{artist=>'A',title=>'T',mbid=>'not-a-uuid'},lookup=>{payload=>{listens=>[]}}],
 ['invalid lookup shape',track=>{artist=>'A',title=>'T'},lookup=>{payload=>{listens=>'bad'}}],
 ['missing lookup payload',track=>{artist=>'A',title=>'T'},lookup=>{}],
 ['invalid header token',token=>"fixture-token\r\nInjected: yes"],
) {
 my ($name,@cfg)=@$case; my ($r,$calls,$ok)=exercise(@cfg);
 ok($ok,"$name does not throw"); ok($r && !$r->{ok},"$name fails closed");
 is(scalar(grep {$_->[0] eq 'POST'} @$calls),0,"$name no write");
 unlike(($r||{})->{error}||'',qr/fixture-token/,"$name secret redacted");
}
for my $rb ({feedback=>[]},{feedback=>[{recording_mbid=>$id,score=>0}]},{feedback=>[{recording_mbid=>'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',score=>1}]},{feedback=>'HTML'},{}) {
 my ($r,$calls,$ok)=exercise(readback=>$rb);
 ok($ok,'malformed/negative readback does not throw'); ok($r && !$r->{ok},'POST never implies success');
}
my ($r)=exercise(post=>{status=>'error'}); ok(!$r->{ok},'application-level POST error');
done_testing;
