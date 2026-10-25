package Plugins::ListenBrainzLove::Identity;
use strict;
use warnings;
use Unicode::Normalize qw(NFKC);
use Encode qw(encode_utf8);
use JSON::PP;
use Digest::SHA qw(sha256_hex);
sub uuid { defined $_[0] && !ref($_[0]) && $_[0] =~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i }
sub text { defined $_[0] && !ref($_[0]) && $_[0] =~ /\S/ && $_[0] !~ /[\x00-\x1f\x7f]/ && length($_[0])<=2048 }
sub normal {
 my ($value)=@_; return '' unless defined($value) && !ref($value);
 $value=lc NFKC($value); $value=~s/[^\p{L}\p{N}]+/ /g; $value=~s/^ +| +$//g;
 return $value;
}
sub title {
 my ($track)=@_; my $title=$track->{title}; my $version=$track->{version}||'';
 my $v=normal($version);
 $title.=' ('.$version.')' if length($v) && normal($title)!~/(?:^| )\Q$v\E(?: |$)/;
 return $title;
}
sub parts {
 my ($artist,$name)=@_;
 while ($name=~s/(?:\s*[\(\[]\s*|\s+)(?:feat(?:uring)?\.?|ft\.?)\s+([^\)\]]+)(?:[\)\]]|$)/ /i) {
  my $guest=normal($1);
  $artist.=' '.$guest if length($guest) && normal($artist)!~/(?:^| )\Q$guest\E(?: |$)/;
 }
 $artist=~s/\b(?:feat(?:uring)?\.?|ft\.?)\s+/ /ig;
 return (normal($artist),$name);
}
sub same_recording {
 my ($track,$artist,$name,$version)=@_;
 return 0 unless text($artist) && text($name);
 my ($wanted_artist,$wanted_name)=parts($track->{artist},$track->{title});
 my ($found_artist,$found_name)=parts($artist,$name);
 return $wanted_artist eq $found_artist
  && normal(title({title=>$wanted_name,version=>$track->{version}||''})) eq normal(title({title=>$found_name,version=>$version||''}));
}
sub same_listen {
 my ($track,$meta)=@_; my $info=$meta->{additional_info}||{};
 return 0 unless ref($info) eq 'HASH';
 return 0 unless same_recording($track,$meta->{artist_name},$meta->{track_name},$info->{version});
 return 0 if $track->{release} && $meta->{release_name} && normal($track->{release}) ne normal($meta->{release_name});
 my $duration=$info->{duration};
 if (defined($info->{duration_ms})) {
  return 0 if ref($info->{duration_ms}) || $info->{duration_ms}!~/\A\d+(?:\.\d+)?\z/;
  $duration=$info->{duration_ms}/1000;
 }
 if ($track->{duration} && defined($duration)) {
  return 0 if ref($duration) || $duration!~/\A\d+(?:\.\d+)?\z/ || abs($track->{duration}-$duration)>3;
 }
 return 1;
}
sub escape {
 my $value=encode_utf8($_[0]);
 $value=~s/([^A-Za-z0-9._~-])/sprintf('%%%02X',ord($1))/ge;
 return $value;
}
sub cache_key {
 my ($track,$user)=@_;
 return sha256_hex(JSON::PP->new->canonical->utf8->encode({algorithm=>1,user=>$user,track=>$track}));
}
1;
