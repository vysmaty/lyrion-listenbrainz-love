use strict; use warnings; use Test::More;
open my $file,'<','Plugins/ListenBrainzLove/strings.txt' or die $!;
binmode $file; local $/; my $strings=<$file>;
unlike($strings,qr/\r/,'LMS translations use Unix line endings');
like($strings,qr/^PLUGIN_LISTENBRAINZLOVE$/m,'name token matches the LMS strings parser');
like($strings,qr/^\tEN\tListenBrainz Love$/m,'English plugin name is readable by LMS');
like($strings,qr/^\tCS\tListenBrainz Love$/m,'Czech plugin name is readable by LMS');
done_testing;
