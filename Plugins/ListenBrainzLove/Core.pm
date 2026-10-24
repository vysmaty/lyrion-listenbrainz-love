package Plugins::ListenBrainzLove::Core;
use strict;
use warnings;
sub new { my ($class,%args)=@_; bless \%args,$class }
sub uuid { defined $_[0] && !ref($_[0]) && $_[0] =~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i }
sub love {
 my ($self,$input,$token,$user,$done)=@_;
 my $clock=$self->{clock}||sub{time};
 my $now=$clock->();
 my $finished=0;
 my $finish=sub { return if $finished++; $done->(shift) };
 my $fail=sub { $finish->({ok=>0,error=>shift}) };
 return $fail->('Missing artist or title') unless ref($input) eq 'HASH' && !grep { !defined($input->{$_}) || ref($input->{$_}) || $input->{$_} !~ /\S/ } qw(artist title);
 return $fail->('Invalid credentials') unless defined($token) && $token =~ /\A[^\s\x00-\x1f\x7f]{1,256}\z/ && defined($user) && $user =~ /\A[A-Za-z0-9_.-]{1,64}\z/;
 my $track={map {$_=>defined($input->{$_}) ? "$input->{$_}" : ''} qw(artist title version mbid release duration tracknumber)};
 my $request=sub {
  my ($method,$path,$auth,$body,$cb)=@_;
  return $fail->('Click expired; click Love again') if $clock->()-$now>30;
  my $called=0;
  my $ok=eval {
   $self->{transport}->($method,'https://api.listenbrainz.org'.$path,$auth?{Authorization=>'Token '.$token}:{},$body,sub {
    return if $called++ || $finished;
    my ($error,$data)=@_;
    return $fail->('Provider request failed') if $error;
    return $fail->('Invalid provider payload') unless ref($data) eq 'HASH';
    return $fail->('Click expired; click Love again') if $clock->()-$now>30;
    my $valid=eval {$cb->($data);1};
    $fail->('Invalid provider payload') unless $valid;
   }); 1;
  };
  $fail->('Provider request failed') unless $ok;
 };
 my $send=sub {
  my ($key,$id)=@_;
  $request->('POST','/1/feedback/recording-feedback',1,{$key=>$id,score=>1},sub {
   my ($post)=@_; return $fail->('Feedback rejected') unless ($post->{status}||'') eq 'ok';
   $request->('GET',"/1/feedback/user/$user/get-feedback?score=1&metadata=true&count=100&offset=0",0,undef,sub {
    my ($data)=@_;
    return $fail->('Invalid readback payload') unless ref($data->{feedback}) eq 'ARRAY';
    for my $row (@{$data->{feedback}}) {
     return $fail->('Invalid readback row') unless ref($row) eq 'HASH';
     if (($row->{$key}||'') eq $id && defined($row->{score}) && $row->{score} eq '1') {
      return $finish->({ok=>1,identity=>{$key=>$id},track=>$track});
     }
    }
    $fail->('Love not verified; do not assume success');
   });
  });
 };
 my $obtain_identity=sub {
  return $fail->('Recording identity is not available yet; retry after a completed listen') unless $self->{allow_playing_now};
  my $current=eval {ref($self->{is_current}) eq 'CODE' && $self->{is_current}->($track)};
  return $fail->('Playback changed or stopped; click Love again') unless $current;
  my $info={media_player=>'Lyrion Music Server',submission_client=>'ListenBrainzLove'};
  if(length $track->{duration}) {
   return $fail->('Invalid current track duration') unless $track->{duration}=~/\A\d+(?:\.\d+)?\z/ && $track->{duration}<=24*24*60*60;
   $info->{duration}=int($track->{duration}) if $track->{duration}>0;
  }
  if(length $track->{tracknumber}) {
   return $fail->('Invalid current track number') unless $track->{tracknumber}=~/\A\d{1,4}\z/;
   $info->{tracknumber}=sprintf('%d',$track->{tracknumber}) if $track->{tracknumber}>0;
  }
  $info->{version}=$track->{version} if length $track->{version};
  my $metadata={artist_name=>$track->{artist},track_name=>$track->{title},additional_info=>$info};
  $metadata->{release_name}=$track->{release} if length $track->{release};
  $request->('POST','/1/submit-listens?return_msid=true',1,{listen_type=>'playing_now',payload=>[{track_metadata=>$metadata}]},sub {
   my ($reply)=@_;
   return $fail->('Playing-now did not return a valid recording identity') unless ($reply->{status}||'') eq 'ok' && uuid($reply->{recording_msid});
   $send->('recording_msid',$reply->{recording_msid});
  });
 };
 $request->('GET','/1/validate-token',1,undef,sub {
  my ($valid)=@_;
  return $fail->('Invalid token or username') unless defined($valid->{valid}) && "$valid->{valid}" eq '1' && ($valid->{user_name}||'') eq $user;
  return $send->('recording_mbid',$track->{mbid}) if uuid($track->{mbid});
  return $fail->('Invalid recording MBID') if length $track->{mbid};
  my $lookup; $lookup=sub {
   my ($recent)=@_;
   my $path=$recent ? '/listens?count=100&min_ts='.($now-300) : '/playing-now';
   $request->('GET',"/1/user/$user$path",0,undef,sub {
    my ($data)=@_;
    return $fail->('Invalid listen payload') unless ref($data->{payload}) eq 'HASH' && ref($data->{payload}{listens}) eq 'ARRAY';
    my $rows=$data->{payload}{listens};
    return $fail->('Listen result exceeds safe bound') if ($recent && @$rows>=100) || (!$recent && @$rows>1);
    my %ids;
    for my $row (@$rows) {
     return $fail->('Invalid listen row') unless ref($row) eq 'HASH' && ref($row->{track_metadata}) eq 'HASH';
     my $m=$row->{track_metadata};
     next unless ($m->{artist_name}||'') eq $track->{artist} && ($m->{track_name}||'') eq $track->{title};
     next if $track->{version} && (($m->{additional_info}||{})->{version}||'') ne $track->{version};
     next if $recent && (!defined($row->{listened_at}) || $row->{listened_at}!~/\A\d+\z/ || $row->{listened_at}<$now-300 || $row->{listened_at}>$now);
     if (uuid(($m->{mbid_mapping}||{})->{recording_mbid})) { $ids{'recording_mbid:'.$m->{mbid_mapping}{recording_mbid}}=1 }
     elsif (uuid($row->{recording_msid})) { $ids{'recording_msid:'.$row->{recording_msid}}=1 }
     elsif (uuid(($m->{additional_info}||{})->{recording_msid})) { $ids{'recording_msid:'.$m->{additional_info}{recording_msid}}=1 }
     else {
      # A normal playing-now response may contain only metadata. Continue to
      # completed listens, while rejecting any explicitly malformed identity.
      next if !$recent && !length(($m->{mbid_mapping}||{})->{recording_mbid}||'') && !length($row->{recording_msid}||'') && !length(($m->{additional_info}||{})->{recording_msid}||'');
      return $fail->('Matching listen has no valid recording identity');
     }
    }
    return $lookup->(1) if !keys(%ids) && !$recent;
    return $obtain_identity->() unless keys %ids;
    return $fail->('More than one recording identity matches') unless keys(%ids)==1;
    my ($key,$id)=split /:/,(keys %ids)[0]; $send->($key,$id);
   });
  };
  $lookup->(0);
 });
}
1;
