# ListenBrainzLove 0.2.0

Standalone Perl plugin targeting LMS 9.1.x. Adds an independent TrackInfo action, **ListenBrainz: Love currently playing**. Never registers the global AudioScrobbler Love handler, never scrobbles, and never creates a fake playing-now submission.

Version 0.2.0 can obtain an MSID before a completed listen exists. Only an explicit Love action may send a real, timestamp-free `playing_now` notification with `return_msid=true`, after rechecking that the same track is still playing. This creates temporary now-playing state, not a completed listen. Existing recording IDs retain priority. Results remain readable in Material Skin.

The action captures immutable click-time artist/title/version/recording MBID, album, duration and track number. Metadata comes from the current protocol handler. A valid supplied MBID has priority, followed by exact playing-now / bounded recent-listen matching (300 seconds, fewer than 100 results). A playing-now response without an ID allows recent-listen fallback. If no existing identity is available, the explicit action may request an MSID using the real current track. Ambiguous, saturated or malformed lookup results fail closed. Token and username are validated; success requires exact recording-ID feedback readback among the first 100 Loved records.

The transport allows `submit-listens?return_msid=true` only for one `playing_now` item with no `listened_at`. It rejects `single`, `import`, multiple tracks and timestamps before HTTP. No background submissions or completed scrobbles are created by this plugin.

Configure username and token in the plugin settings after a separately approved installation. Password input is never prefilled; tokens are stored in ordinary local LMS preferences, not encrypted. Protect the LMS administration interface and preference files. Fixed HTTPS provider, strict TLS verification, no redirects, 8-second requests, 30-second operation deadline. No pending queue or unlove.

## Verification

`prove -v t`: **15 files, 208 assertions, PASS**. Includes actual local TCP HTTP fake-server POST/readback plus transport injection and LMS facades for negative scenarios. Development evidence and integration logs are excluded from publication.

Upstream LMS 9.1.1 commit `1ceeaf1d601134f765b5a3e65113726284eaae6d` was started in an isolated scratch tree. The plugin was loaded there and its real settings HTML returned HTTP 200 with password input. Installation and the settings page were subsequently checked on a live LMS 9.1.1 server. A real ListenBrainz write has not yet been verified end to end.

Limitations: this environment lacks Perl IO::Socket::SSL; production HTTPS is therefore untested here and the plugin refuses SSL downgrade. No real Radio Paradise/player/Material Skin GUI click or live ListenBrainz write was exercised. Service playing-now has no timestamp, so the plugin trusts the service's current response within the operation deadline. The full Czech README documents security, matching rules, and deployment gates.

Run `prove -v t`; `python3 tools/build.py` runs all tests and creates `dist/ListenBrainzLove-0.2.0.zip` (standard LMS ZIP with `install.xml` at root), the source ZIP, SHA-1/SHA-256 manifests, generated `repo.xml`, and clean allowlisted sources in `.publication/`. It never includes evidence, local state, credentials or previous archives. Review source contents before publishing. The optional `tools/isolated_lms.py` requires a disposable LMS 9.1.1 clone at `.local/lms-9.1.1`; it is not run by the build.

## Repository installation

The repository is https://github.com/vysmaty/lyrion-listenbrainz-love, branch `main`, release `v0.2.0`. Nothing is uploaded by the build tools. Add this URL under **Settings → Plugins → Additional repositories**, apply, select **ListenBrainz Love**, then install/restart as prompted:

`https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/main/repo.xml`

LMS 9.1.0 or later is declared; verification targeted 9.1.1, not every later release. The release asset must be the exact generated `ListenBrainzLove-0.2.0.zip`, not GitHub's automatic source archive. `repo.xml` points to `https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/dist-v0.2.0/dist/ListenBrainzLove-0.2.0.zip` to avoid oversized headers from GitHub Release downloads; `<sha>` is the SHA-1 of its bytes. Rebuild XML and ZIP together and publish the matching distribution tag after source changes.
