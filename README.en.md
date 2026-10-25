# ListenBrainzLove 0.5.1

Standalone Perl plugin for Lyrion Music Server 9.1.x. Explicitly Love a selected recording on ListenBrainz and verify the saved state, including a track that is not playing. Existing scrobblers continue to submit completed listens.

Version 0.5.1 fixes incomplete performer credits that could incorrectly reject a matching recording.

## Use

In Material Skin 6.4.6+, choose **ListenBrainz Love** in the selected queue/library track menu. Opening this native view only reads state: filled heart means confirmed Love, outline means known not-loved, and a question mark means unknown. MSID-only Love is explicitly distinguished from MusicBrainz linkage. **Mark selected track as Love** is a separate explicit write; **Refresh Love status** and clicking the state heart only read.

The initial context-menu navigation icon is static. Actual state is shown inside the plugin view. Rating stars remain independent; no Material JavaScript, ratings hook or user custom.js is modified. Refresh Material after an update. Standard TrackInfo provides **ListenBrainz: Love selected track** and a separate status link. Love works with stopped playback or an empty queue when LMS knows the selected recording and reliable metadata. An inactive remote selection requires a known positive track duration, avoiding indefinite radio stations. Refresh after provider metadata loads. Invalid/expired IDs never fall back to loving the current recording. No Unlove or automatic migration is introduced.

## Identity flow

1. Capture immutable click-time metadata from the selected track's canonical URL object and its own provider metadata. Retain TIDAL MAIN/FEATURED and local ARTIST/TRACKARTIST names, excluding composer/conductor roles. Never use forceCurrent or the playing track's MBID for a different selection. Retain available ISRC; this release does not add an ISRC resolver.
2. Prefer authoritative source recording MBID or an accepted cache entry for this exact source and metadata.
3. Otherwise inspect matching playing-now and bounded recent listens (300 seconds, fewer than 100 rows). Playing-now MSID does not short-circuit available MBID resolution. Saturated or conflicting results fail closed.
4. Resolve missing MBID using authenticated GET `/1/metadata/lookup/`, with `artist_name`, `recording_name` and optional `release_name`. A separate version is retained in the lookup title. Empty `{}` alone means no match; malformed data and network errors do not.
5. Require a recording UUID and compatible normalized artist/title/version. Unicode, case and punctuation separators are normalized; version words are never discarded and no fuzzy guessing is used. Album is a hint, not an exact-edition requirement. Basic lookup has no candidate duration, so duration is not claimed as verified there. Existing-listen matching compares two available durations within three seconds.
6. POST feedback with `score=1`. Attach both IDs only when the same accepted listen explicitly pairs them; otherwise prefer MBID. Verify exact IDs via targeted `get-feedback-for-recordings`, independently of the first 100 favorites. A combined-ID write requires confirmation of their shared row.

Positive lookup cache: maximum 128 entries, one-hour TTL, keyed by username, source URL, metadata and algorithm version, with a SHA-256 digest. No negative or credential cache. Direct source MBIDs are trusted as authoritative recording IDs; UUID syntax alone cannot establish entity type or recording correctness. Text lookup does not prove a unique catalog match.

After a confirmed no-match, reuse a matching MSID. If absent, only explicit Love of the actually playing track may recheck unchanged active playback and submit one real timestamp-free `playing_now?return_msid=true`, then Love the returned MSID. This is temporary state, not a completed scrobble. An unresolved non-playing selection stops without writing or announcing fake playback. Status reads never submit it. Network errors, rejected candidates and malformed responses never silently fall through to another identity. A failed post-write readback reports uncertainty because feedback may already be stored.

## Installation

Add under **Settings → Plugins → Additional repositories**, apply, select **ListenBrainz Love**, then install/restart as prompted:

`https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/main/repo.xml`

Configure username/token in plugin settings. Empty token input preserves the saved token; validation checks ownership. Minimum declared LMS 9.1.0; integration targets 9.1.1. Repository: [vysmaty/lyrion-listenbrainz-love](https://github.com/vysmaty/lyrion-listenbrainz-love), release `v0.5.1`.

The exact generated `ListenBrainzLove-0.5.1.zip` has `install.xml` at root. `repo.xml` points to the immutable `dist-v0.5.1` distribution tag and contains SHA-1 of complete ZIP bytes. SHA-256 is provided separately. GitHub's automatic source archive is not an installable plugin ZIP.

## Safety and diagnostics

Fixed HTTPS origin and allowlisted paths/methods; strict TLS/hostname verification; no redirects; token only in Authorization. Lookup enforces a 250-Unicode-character sum and correct UTF-8 escaping. Eight-second HTTP timeout, 30-second operation deadline, bounded JSON. HTTP 429 observes numeric Retry-After / X-RateLimit-Reset-In or a 30-second default cooldown; no automatic write retries. Repeated concurrent Love on one player is blocked during verification.

Transport rejects completed listens (`single`, `import`), timestamps in playing-now, multiple tracks, manual mapping and feedback other than Love. No global AudioScrobbler Love handler is registered.

Tokens are stored in ordinary unencrypted local LMS preferences; protect administration and files. The plugin never reads tokens from the environment. Read-only `listenbrainzlove metadata` reports source/effective IDs, available ISRC and metadata, including while stopped, without ListenBrainz requests. It excludes tokens and potentially credentialed stream URLs.

## Verification and build

`prove -v t`: **20 files, 424 assertions, PASS**. Covers MBID/MSID priority, lookup before the first scrobble, Unicode, conflicting versions, bounds, cache, targeted readback, uncertain POST, native read-only state, non-playing selection, stopped/empty players and preventing fake playing-now, with two real local TCP/HTTP fake providers. No real account or feedback writes are used by these tests.

`python tools/build.py` runs tests and creates the plugin/source ZIPs, checksums, generated repo.xml and clean allowlisted `.publication/` sources. Local diagnostic notes and listening evidence are excluded. The build never publishes or deploys.

The test Perl lacks IO::Socket::SSL; transport facades are not a live TLS handshake. Target LMS and Material verification is a separate release check; an actual user click verifies a real feedback write.

[Česky](README.md) · [API/source evidence](docs/UPSTREAM.md) · [license](LICENSE)
