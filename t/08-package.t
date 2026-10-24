use strict; use warnings; use Test::More;
for my $file (qw(Plugins/ListenBrainzLove/install.xml Plugins/ListenBrainzLove/strings.txt Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/settings/basic.html)) {ok(-s $file,"package includes $file")}
if (-f 'Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/settings/basic.html') {
 open my $f,'<','Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/settings/basic.html'; local $/; my $s=<$f>;
 like($s,qr/type="password"/,'token masked'); unlike($s,qr/value="\[%\s*(?:pref_)?token/,'token never echoed');
}
done_testing;
