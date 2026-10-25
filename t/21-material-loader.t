use strict; use warnings; use Test::More; use File::Temp qw(tempdir); use File::Spec; use lib '.';
BEGIN {$INC{'Slim/Utils/Prefs.pm'}=1;package Slim::Utils::Prefs;our $root;sub dir {$root}}
use Plugins::ListenBrainzLove::Material;
$Slim::Utils::Prefs::root=tempdir(CLEANUP=>1);
my $dir=File::Spec->catdir($Slim::Utils::Prefs::root,'material-skin');mkdir $dir or die $!;
my $path=File::Spec->catfile($dir,'custom.js');
sub read_file {open my $r,'<:raw',$_[0] or die $!;local $/;return <$r>//''}
sub write_file {open my $w,'>:raw',$_[0] or die $!;print {$w} $_[1];close $w or die $!}
Plugins::ListenBrainzLove::Material::configure(0);
ok(!-e $path,'disabled integration creates no custom JavaScript');
my $original="window.existingAddon = 'keep';\r\n";write_file($path,$original);
Plugins::ListenBrainzLove::Material::configure(1);
my $installed=read_file($path);
is(substr($installed,0,length($original)),$original,'existing custom JavaScript bytes are preserved');
is(read_file(File::Spec->catfile($dir,'custom.js.before-listenbrainzlove')),$original,'original content has a separate exact backup');
like($installed,qr/api\.enableButton\(\)/,'managed loader starts only the optional footer button');
Plugins::ListenBrainzLove::Material::configure(1);
is(read_file($path),$installed,'repeated startup does not duplicate or grow the loader');
my $later="window.laterAddon = true;\n";write_file($path,$installed.$later);
Plugins::ListenBrainzLove::Material::configure(0);
is(read_file($path),$original.$later,'disabling removes only the managed block and preserves later edits');
write_file($path,'/* BEGIN ListenBrainzLove managed loader */ incomplete');
ok(!eval {Plugins::ListenBrainzLove::Material::configure(1);1},'incomplete managed block requires review instead of overwriting');
like(read_file($path),qr/incomplete$/,'rejected setup leaves the file unchanged');
my $script=Plugins::ListenBrainzLove::Material::loader('love');
like($script,qr/api\.love\(pid,id\)/,'manual context loader retains its selected target across asynchronous loading');
unlike($script,qr/\$ITEMID|\$ARTISTNAME|\$TRACKNAME/,'no unescaped track substitutions enter executable code');
done_testing;
