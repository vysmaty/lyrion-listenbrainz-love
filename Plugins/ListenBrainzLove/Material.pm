package Plugins::ListenBrainzLove::Material;
use strict;
use warnings;
use File::Spec;
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use Slim::Utils::Prefs;
my $begin='/* BEGIN ListenBrainzLove managed loader */';
my $end='/* END ListenBrainzLove managed loader */';
sub loader {
 my ($mode)=@_;
 my $call=$mode eq 'button' ? 'api.enableButton()' : 'api.love(pid,id)';
 # Material evaluates action scripts directly in doCustomAction(action, player,
 # item). Production builds rename its local parameters; arguments survives
 # minification and keeps selected IDs as values rather than script substitutions.
 my $args=$mode eq 'button' ? 'null,null' : "typeof arguments==='undefined'||!arguments[1]?null:arguments[1].id,typeof arguments==='undefined'||!arguments[2]?null:arguments[2].id";
 my $script=<<'JAVASCRIPT';
(function(pid,id){
 function ready(){var api=window.ListenBrainzLoveMaterial;return __LB_CALL__;}
 if(window.ListenBrainzLoveMaterial){ready();return;}
 if(!window.ListenBrainzLoveMaterialLoading){
  window.ListenBrainzLoveMaterialLoading=new Promise(function(resolve,reject){
   var script=document.createElement('script');
   script.src='/plugins/ListenBrainzLove/html/material-love.js?v=0.7.7';
   script.onload=resolve;
   script.onerror=function(){window.ListenBrainzLoveMaterialLoading=null;reject(new Error('ListenBrainz UI unavailable'));};
   document.head.appendChild(script);
  });
 }
 window.ListenBrainzLoveMaterialLoading.then(ready).catch(function(){
  if(typeof bus!=='undefined'){bus.$emit('showError',undefined,'ListenBrainz: UI unavailable. Refresh and try again.',10);}
 });
})(__LB_ARGS__);
JAVASCRIPT
 $script=~s/__LB_CALL__/$call/;
 $script=~s/__LB_ARGS__/$args/;
 return $script;
}
sub configure {
 my ($enabled)=@_;
 my $dir=File::Spec->catdir(Slim::Utils::Prefs::dir(),'material-skin');
 my $path=File::Spec->catfile($dir,'custom.js');
 die 'Custom JavaScript must be a regular file' if -l $dir || -l $path || (-e $path && !-f $path);
 my $old='';
 if (-e $path) {
  die 'Custom JavaScript is too large' if -s $path>1024*1024;
  open my $read,'<:raw',$path or die 'Cannot read custom JavaScript';local $/;$old=<$read>//'';close $read;
 }
 my $new=$old;
 my $blocks=($new=~s/\Q$begin\E.*?\Q$end\E\r?\n?//sg);
 die 'Incomplete managed JavaScript block; manual review required' if index($new,$begin)>=0 || index($new,$end)>=0;
 if ($enabled) {$new.="\n" if length($new) && $new!~/\n\z/;$new.="$begin\n;\n".loader('button')."\n$end\n"}
 return if $new eq $old || (!$enabled && !$blocks);
 make_path($dir) unless -d $dir;
 if (length($old) && !$blocks) {
  my $backup=File::Spec->catfile($dir,'custom.js.before-listenbrainzlove');
  die 'Backup must be a regular file' if -l $backup || (-e $backup && !-f $backup);
  unless (-e $backup) {open my $save,'>:raw',$backup or die 'Cannot back up custom JavaScript';print {$save} $old or die 'Cannot back up custom JavaScript';close $save or die 'Cannot finish backup'}
 }
 my ($write,$temp)=tempfile('listenbrainzlove-XXXX',DIR=>$dir,UNLINK=>1);
 binmode $write;
 print {$write} $new or die 'Cannot save custom JavaScript';close $write or die 'Cannot finish custom JavaScript';
 chmod((stat($path))[2]&0777,$temp) if -e $path;
 rename($temp,$path) or die 'Cannot replace custom JavaScript';
 return 1;
}
1;
