use strict; use warnings; use Test::More;
ok(-s 'Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/html/images/refresh.svg','package includes the distinct refresh icon');
for my $file (qw(Plugins/ListenBrainzLove/install.xml Plugins/ListenBrainzLove/strings.txt Plugins/ListenBrainzLove/Identity.pm Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/settings/basic.html Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/html/images/heart-filled.svg Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/html/images/heart-outline.svg Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/html/images/heart-unknown.svg)) {ok(-s $file,"package includes $file")}
{
 open my $f,'<','Plugins/ListenBrainzLove/install.xml' or die $!; local $/; my $s=<$f>;
 like($s,qr/<defaultState>enabled<\/defaultState>/,'selected plugin starts enabled after installation');
}
if (-f 'Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/settings/basic.html') {
 open my $f,'<','Plugins/ListenBrainzLove/HTML/EN/plugins/ListenBrainzLove/settings/basic.html'; local $/; my $s=<$f>;
 like($s,qr/type="password"/,'token masked'); unlike($s,qr/value="\[%\s*(?:pref_)?token/,'token never echoed');
}
done_testing;
