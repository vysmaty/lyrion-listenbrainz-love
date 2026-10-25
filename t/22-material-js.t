use strict;use warnings;
my $node=$ENV{NODE_BIN}||'node';
exec {$node} $node,'t/22-material-js.cjs' or die "Cannot run Node.js UI tests: $!";
