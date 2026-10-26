use strict;use warnings;use lib '.';use JSON::PP qw(encode_json);
BEGIN {$INC{'Slim/Utils/Prefs.pm'}=1}
use Plugins::ListenBrainzLove::Material;
my $node=$ENV{NODE_BIN}||'node';
open my $child,'|-',$node,'t/26-material-bridge.cjs' or die "Cannot start Node: $!";
print {$child} encode_json({love=>Plugins::ListenBrainzLove::Material::loader('love'),button=>Plugins::ListenBrainzLove::Material::loader('button')});
close $child;exit($? >> 8);
