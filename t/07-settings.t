use strict; use warnings; use Test::More; use lib '.';
BEGIN {
 for(qw(Slim/Web/Settings.pm Slim/Utils/Prefs.pm Plugins/ListenBrainzLove/Transport.pm Plugins/ListenBrainzLove/Material.pm)){$INC{$_}=1}
 package Slim::Web::Settings; sub handler{my($c,$client,$p)=@_; return $p}
 package Slim::Web::HTTP::CSRF; sub protectName{$_[1]} sub protectURI{$_[1]}
 package Slim::Utils::Prefs; sub import{no strict 'refs'; *{caller().'::preferences'}=sub{bless {},'FixturePrefs'}}
 package FixturePrefs; our %v=(username=>'old',token=>'old-fixture'); sub get{$v{$_[1]}} sub set{$v{$_[1]}=$_[2]}
 package Plugins::ListenBrainzLove::Transport; our $valid=1; sub request{$_[4]->(undef,{valid=>$valid,user_name=>'tester'})}
 package Plugins::ListenBrainzLove::Material; our (@enabled,$fail); sub configure {die 'Fixture failure' if $fail;push @enabled,$_[0]}
}
my $loaded=eval{require Plugins::ListenBrainzLove::Settings;1}; ok($loaded,'settings loads') or diag($@);
if($loaded) {
 my $p={}; my $r=Plugins::ListenBrainzLove::Settings->handler(undef,$p);
 ok(!exists $r->{token} && !exists $r->{pref_token},'GET never prepopulates secret');
 my $out;
 Plugins::ListenBrainzLove::Settings->handler(undef,{saveSettings=>1,token=>'new-fixture',username=>'tester'},sub{my($c,$p,$body)=@_;$out=$body});
 is($FixturePrefs::v{token},'new-fixture','valid token saved'); is($FixturePrefs::v{username},'tester','validated username saved');
 unlike(join(' ',values %$out),qr/new-fixture/,'secret absent from rendered parameters');
 $Plugins::ListenBrainzLove::Transport::valid=0;
 Plugins::ListenBrainzLove::Settings->handler(undef,{saveSettings=>1,token=>'bad-fixture',username=>'tester'},sub{my($c,$p,$body)=@_;$out=$body});
 is($FixturePrefs::v{token},'new-fixture','invalid token does not overwrite');
 like($out->{warning},qr/failed/i,'validation error visible');
 $Plugins::ListenBrainzLove::Transport::valid=1;
 Plugins::ListenBrainzLove::Settings->handler(undef,{saveSettings=>1,username=>'tester',material_button=>1},sub{my($c,$p,$body)=@_;$out=$body});
 is($FixturePrefs::v{material_button},1,'desktop heart is an explicit opt-in preference');
 is($Plugins::ListenBrainzLove::Material::enabled[-1],1,'verified save installs the managed loader');
 $Plugins::ListenBrainzLove::Material::fail=1;
 Plugins::ListenBrainzLove::Settings->handler(undef,{saveSettings=>1,token=>'replacement',username=>'tester'},sub{my($c,$p,$body)=@_;$out=$body});
 is($FixturePrefs::v{token},'new-fixture','failed loader setup cannot silently replace credentials');
 is($FixturePrefs::v{material_button},1,'failed loader removal preserves the enabled preference');
 like($out->{warning},qr/Material button setup failed/,'file integration failure is reported in settings');
}
done_testing;
