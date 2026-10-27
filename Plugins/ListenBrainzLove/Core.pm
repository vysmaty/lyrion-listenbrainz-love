package Plugins::ListenBrainzLove::Core;
use strict;
use warnings;
use Plugins::ListenBrainzLove::Identity;
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
sub new { my ($class,%args)=@_; bless \%args,$class }
sub uuid { Plugins::ListenBrainzLove::Identity::uuid($_[0]) }
sub love { my ($self,@args)=@_; $self->_run('love',@args) }
sub unlove { my ($self,@args)=@_; $self->_run('unlove',@args) }
sub status { my ($self,@args)=@_; $self->_run('status',@args) }
sub _copy {
 my ($result)=@_;return {%$result,map {$_=>{%{$result->{$_}}}} grep {ref($result->{$_}) eq 'HASH'} qw(identity track)};
}
sub _store {
 my ($cache,$key,$entry,$now)=@_;
 delete $cache->{$_} for grep {$cache->{$_}{expires}<=$now} keys %$cache;
 if (!exists($cache->{$key}) && keys(%$cache)>=128) {my ($oldest)=sort {$cache->{$a}{expires}<=>$cache->{$b}{expires}} keys %$cache;delete $cache->{$oldest}}
 $cache->{$key}=$entry;
}
sub _run {
 my ($self,$mode,$input,$token,$user,$done,$options)=@_;
 my $clock=$self->{clock}||sub{time};
 my $now=$clock->();
 my $deadline=defined($self->{deadline}) && $self->{deadline}<$now+30 ? $self->{deadline} : $now+30;
 my ($finished,$write_started)=(0,0);
 my ($lookup,$metadata_lookup,$fallback);
 my ($state,$credential_key,$status_key,$pending_key,$generation);
 my $invalidate=sub {
  return unless $state && defined($credential_key);
  $state->{generation}=1+($state->{generation}||0);
  delete $state->{status}{$_} for grep {$state->{status}{$_}{credential} eq $credential_key} keys %{$state->{status}||{}};
 };
 my $finish=sub {
  return if $finished++;my $result=shift;
  $lookup=$metadata_lookup=$fallback=undef;
  if ($state && defined($status_key)) {
   if ($mode ne 'status') {$invalidate->();$generation=$state->{generation};$result->{action}=$mode}
   _store($state->{status}||={},$status_key,{result=>_copy($result),credential=>$credential_key,expires=>$clock->()+30},$clock->())
    if $result->{ok} && $generation==($state->{generation}||0);
  }
  my $waiters=defined($pending_key) ? delete $state->{pending}{$pending_key} : undef;
  if ($waiters) {eval {$_->(_copy($result))} for @$waiters} else {$done->($result)}
 };
 my $fail=sub { $finish->({ok=>0,error=>shift,uncertain=>$write_started?1:0}) };
 return $fail->('Missing artist or title') unless ref($input) eq 'HASH' && !grep { !Plugins::ListenBrainzLove::Identity::text($input->{$_}) } qw(artist title);
 return $fail->('Invalid credentials') unless defined($token) && $token =~ /\A[^\s\x00-\x1f\x7f]{1,256}\z/ && defined($user) && $user =~ /\A[A-Za-z0-9_.-]{1,64}\z/;
 my @fields=qw(artist title version mbid release duration tracknumber url isrc);
 return $fail->('Invalid track metadata') if grep {defined($input->{$_}) && (ref($input->{$_}) || $input->{$_}=~/[\x00-\x1f\x7f]/ || length($input->{$_})>2048)} @fields;
 my $track={map {$_=>defined($input->{$_}) ? "$input->{$_}" : ''} @fields};
 return $fail->('Invalid current track duration') if length($track->{duration}) && ($track->{duration}!~/\A\d+(?:\.\d+)?\z/ || $track->{duration}>24*24*60*60);
 my $cache=$self->{cache}||={};
 my $cache_key=Plugins::ListenBrainzLove::Identity::cache_key($track,$user);
 $state=$self->{state}||={};
 $credential_key=sha256_hex(encode_utf8($user."\0".$token));
 $status_key=sha256_hex($credential_key."\0".$cache_key);
 $generation=$state->{generation}||0;
 my $previous=($state->{status}||{})->{$status_key};
 if ($mode eq 'status') {
  return $done->(_copy($previous->{result})) if !(ref($options) eq 'HASH' && $options->{refresh}) && ref($previous) eq 'HASH' && $previous->{expires}>$now;
  $pending_key=$status_key.':'.$generation;
  if ($state->{pending}{$pending_key}) {push @{$state->{pending}{$pending_key}},$done;return}
  $state->{pending}{$pending_key}=[$done];
 } else {$invalidate->();$generation=$state->{generation}}
 my $wanted=$mode eq 'unlove'?0:1;
 my $request=sub {
  my ($method,$path,$auth,$body,$cb)=@_;
  return $fail->('Click expired; click Love again') if $clock->()>=$deadline;
  my $called=0;
  my $ok=eval {
   $self->{transport}->($method,'https://api.listenbrainz.org'.$path,$auth?{Authorization=>'Token '.$token}:{},$body,sub {
    return if $called++ || $finished;
    my ($error,$data)=@_;
    if (defined($error) && $error eq 'Provider authentication failed') {delete $state->{auth}{$credential_key};$invalidate->()}
    return $fail->('Playback changed or stopped; click Love again') if defined($error) && $error eq 'Provider snapshot changed';
    return $fail->('ListenBrainz rate limit; wait briefly and refresh the status') if defined($error) && $error eq 'Provider rate limit; retry shortly';
    return $fail->($write_started?'Feedback could not be verified; write may have succeeded':'Provider request failed') if $error;
    return $fail->('Invalid provider payload') unless ref($data) eq 'HASH';
    return $fail->('Click expired; click Love again') if $clock->()>=$deadline;
    my $valid=eval {$cb->($data);1};
    $fail->('Invalid provider payload') unless $valid;
   },{deadline=>$deadline,$path eq '/1/submit-listens?return_msid=true'?(before_send=>sub {ref($self->{is_current}) eq 'CODE' && $self->{is_current}->($track)}):()}); 1;
  };
  $fail->('Provider request failed') unless $ok;
 };
 my $read=sub {
  my ($identity,$source,$written)=@_;
  my @keys=sort keys %$identity;
  my $path="/1/feedback/user/$user/get-feedback-for-recordings?".join('&',map {$_.'s='.lc($identity->{$_})} @keys);
  $request->('GET',$path,1,undef,sub {
   my ($data)=@_;
   return $fail->('Invalid readback payload') unless ref($data->{feedback}) eq 'ARRAY' && @{$data->{feedback}}<=4;
   my (%scores,$paired);
   for my $row (@{$data->{feedback}}) {
    return $fail->('Invalid readback row') unless ref($row) eq 'HASH' && defined($row->{score}) && !ref($row->{score}) && $row->{score}=~/\A(?:-1|0|1)\z/;
    my $matches=0;
    for my $key (@keys) {
     next unless defined($row->{$key}) && uuid($row->{$key}) && lc($row->{$key}) eq lc($identity->{$key});
     return $fail->('Conflicting feedback states') if exists($scores{$key}) && $scores{$key} ne $row->{score};
     $scores{$key}=$row->{score}; $matches++;
    }
    $paired=1 if $matches==@keys && $row->{score}==$wanted;
   }
   return $fail->('Feedback not verified; do not assume success') if grep {!exists($scores{$_})} @keys;
   return $fail->('Feedback not verified; write may have succeeded') if $written && ((grep {$scores{$_}!=$wanted} @keys) || ($wanted==1 && !$paired));
   my $primary=exists($identity->{recording_mbid})?'recording_mbid':'recording_msid';
   $finish->({ok=>1,identity=>$identity,track=>$track,score=>0+$scores{$primary},linked=>exists($identity->{recording_mbid})?1:0,source=>$source,
    exists($scores{recording_msid})?(msid_score=>0+$scores{recording_msid}):()});
  });
 };
 my $send=sub {
  my ($identity,$source)=@_;
  return $read->($identity,$source,0) if $mode eq 'status';
  $write_started=1;
  $request->('POST','/1/feedback/recording-feedback',1,{%$identity,score=>$wanted},sub {
   my ($post)=@_; return $fail->('Feedback rejected') unless ($post->{status}||'') eq 'ok';
   $read->($identity,$source,1);
  });
 };
 my (%mbids,%msids,%pairs);
 $fallback=sub {
  return $send->({recording_msid=>(keys %msids)[0]},'existing_msid') if keys(%msids)==1;
  return $fail->('Recording identity is not available yet; no safe metadata match') if $mode ne 'love' || !$self->{allow_playing_now};
  my $current=eval {ref($self->{is_current}) eq 'CODE' && $self->{is_current}->($track)};
  return $fail->('Playback changed or stopped; click Love again') unless $current;
  my $info={media_player=>'Lyrion Music Server',submission_client=>'ListenBrainzLove'};
  $info->{duration}=int($track->{duration}) if length($track->{duration}) && $track->{duration}>0;
  if(length $track->{tracknumber}) {
   return $fail->('Invalid current track number') unless $track->{tracknumber}=~/\A\d{1,4}\z/;
   $info->{tracknumber}=sprintf('%d',$track->{tracknumber}) if $track->{tracknumber}>0;
  }
  $info->{version}=$track->{version} if length $track->{version};
  my $meta={artist_name=>$track->{artist},track_name=>$track->{title},additional_info=>$info};
  $meta->{release_name}=$track->{release} if length $track->{release};
  $request->('POST','/1/submit-listens?return_msid=true',1,{listen_type=>'playing_now',payload=>[{track_metadata=>$meta}]},sub {
   my ($reply)=@_;
   return $fail->('Playing-now did not return a valid recording identity') unless ($reply->{status}||'') eq 'ok' && uuid($reply->{recording_msid});
   $send->({recording_msid=>lc($reply->{recording_msid})},'playing_now');
  });
 };
 $metadata_lookup=sub {
  return $fail->('More than one recording identity matches') if keys(%msids)>1;
  my $title=Plugins::ListenBrainzLove::Identity::title($track);
  return $fail->('Metadata lookup exceeds 250-character limit') if length($track->{artist})+length($title)+length($track->{release})>250;
  my $path='/1/metadata/lookup/?artist_name='.Plugins::ListenBrainzLove::Identity::escape($track->{artist}).'&recording_name='.Plugins::ListenBrainzLove::Identity::escape($title);
  $path.='&release_name='.Plugins::ListenBrainzLove::Identity::escape($track->{release}) if length($track->{release});
  $request->('GET',$path,1,undef,sub {
   my ($data)=@_;
   return $fallback->() unless keys %$data;
   return $fail->('Invalid metadata lookup response') unless uuid($data->{recording_mbid}) && Plugins::ListenBrainzLove::Identity::text($data->{recording_name}) && Plugins::ListenBrainzLove::Identity::text($data->{artist_credit_name});
   return $fail->('Metadata lookup returned a different artist or recording version') unless Plugins::ListenBrainzLove::Identity::same_recording($track,$data->{artist_credit_name},$data->{recording_name});
   delete $cache->{$_} for grep {$cache->{$_}{expires}<=$now} keys %$cache;
   if (keys(%$cache)>=128) {my ($oldest)=sort {$cache->{$a}{expires}<=>$cache->{$b}{expires}} keys %$cache; delete $cache->{$oldest}}
   $cache->{$cache_key}={mbid=>lc($data->{recording_mbid}),expires=>$now+3600};
   $send->({recording_mbid=>lc($data->{recording_mbid})},'metadata_lookup');
  });
 };
 $lookup=sub {
  my ($recent)=@_;
  my $path=$recent ? '/listens?count=100&min_ts='.int($now-300) : '/playing-now';
  $request->('GET',"/1/user/$user$path",1,undef,sub {
   my ($data)=@_;
   return $fail->('Invalid listen payload') unless ref($data->{payload}) eq 'HASH' && ref($data->{payload}{listens}) eq 'ARRAY';
   my $rows=$data->{payload}{listens};
   return $fail->('Listen result exceeds safe bound') if ($recent && @$rows>=100) || (!$recent && @$rows>1);
   for my $row (@$rows) {
    return $fail->('Invalid listen row') unless ref($row) eq 'HASH' && ref($row->{track_metadata}) eq 'HASH';
    my $m=$row->{track_metadata};
    return $fail->('Invalid listen metadata') if (exists($m->{additional_info}) && ref($m->{additional_info}) ne 'HASH') || (exists($m->{mbid_mapping}) && ref($m->{mbid_mapping}) ne 'HASH');
    next unless Plugins::ListenBrainzLove::Identity::same_listen($track,$m);
    next if $recent && (!defined($row->{listened_at}) || $row->{listened_at}!~/\A\d+\z/ || $row->{listened_at}<$now-300 || $row->{listened_at}>$now);
    my $mapping=($m->{mbid_mapping}||{})->{recording_mbid}||'';
    my $direct=($m->{additional_info}||{})->{recording_mbid}||'';
    my $msid=$row->{recording_msid}||($m->{additional_info}||{})->{recording_msid}||'';
    return $fail->('Invalid matching recording identity') if grep {length($_) && !uuid($_)} ($mapping,$direct,$msid);
    return $fail->('Conflicting recording MBIDs') if $mapping && $direct && lc($mapping) ne lc($direct);
    my $mbid=lc($mapping||$direct); $msid=lc($msid);
    $mbids{$mbid}=1 if $mbid; $msids{$msid}=1 if $msid;
    $pairs{$mbid}{$msid}=1 if $mbid && $msid;
    return $fail->('Matching listen has no valid recording identity') if $recent && !$mbid && !$msid;
   }
   return $fail->('More than one recording identity matches') if keys(%mbids)>1;
   if (keys %mbids) {
    my ($id)=keys %mbids; my $identity={recording_mbid=>$id};
    my @paired=keys %{$pairs{$id}||{}};
    $identity->{recording_msid}=$paired[0] if @paired==1;
    return $send->($identity,'existing_mapping');
   }
   return $lookup->(1) unless $recent;
   $metadata_lookup->();
  });
 };
 my $validated=sub {
  # Reuse the exact previously verified pair for removal. Zero feedback rows
  # after deletion are independent; they no longer need a common DB row.
  return $send->({%{$previous->{result}{identity}}},'verified_status') if $mode eq 'unlove' && ref($previous) eq 'HASH' && $previous->{expires}>$now && ref($previous->{result}{identity}) eq 'HASH';
  return $send->({recording_mbid=>lc($track->{mbid})},'source') if uuid($track->{mbid});
  return $fail->('Invalid recording MBID') if length $track->{mbid};
  my $cached=$cache->{$cache_key};
  return $send->({recording_mbid=>$cached->{mbid}},'cache') if ref($cached) eq 'HASH' && $cached->{expires}>$now && uuid($cached->{mbid});
  $lookup->(0);
 };
 my $auth=($state->{auth}||{})->{$credential_key};
 return $validated->() if ref($auth) eq 'HASH' && $auth->{expires}>$now;
 $request->('GET','/1/validate-token',1,undef,sub {
  my ($valid)=@_;
  return $fail->('Invalid token or username') unless defined($valid->{valid}) && "$valid->{valid}" eq '1' && ($valid->{user_name}||'') eq $user;
  _store($state->{auth}||={},$credential_key,{expires=>$clock->()+300},$clock->());
  $validated->();
 });
}
1;
