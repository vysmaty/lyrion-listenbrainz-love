# Authoritative API/source evidence

Reviewed upstream LMS tag **9.1.1**, commit **1ceeaf1d601134f765b5a3e65113726284eaae6d**. Source clone is scratch-only. Links pin the actual reviewed commit.

- [Slim/Menu/TrackInfo.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Menu/TrackInfo.pm): lines 67–83 demonstrate `registerInfoProvider(name => (func => ...))`. Lines 265–271 fetch radio metadata with protocol-handler `getMetadataFor(client,url)`. Line 286 provider signature is `(client,url,track,remoteMeta,tags,filter)`.
- [Slim/Plugin/Podcast/Plugin.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Plugin/Podcast/Plugin.pm#L400-L432): async menu `url => sub { my(client,cb,params)=@_; cb({items=>[...]}) }` example.
- [Slim/Player/Client.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Player/Client.pm#L1349): `playingSong` delegates to streaming controller. [Song.pm line 731](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Player/Song.pm#L731) exposes `currentTrack`.
- [Slim/Player/Playlist.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Player/Playlist.pm#L56-L169): `song`, `track`, `url` concern playlist items/positions, not immutable live radio metadata. The plugin instead captures currently playing Song plus fresh protocol metadata; station URL equality is only a menu visibility gate.
- [SimpleAsyncHTTP.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Networking/SimpleAsyncHTTP.pm): callbacks `new(success,error,params)`, GET/POST headers, body last, `hasSSL`, `code`, `content`.
- [Async/HTTP.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Networking/Async/HTTP.pm#L104-L161): socket `options` passed through, global insecureHTTPS can otherwise disable verification, and missing SSL otherwise falls back to HTTP. Plugin explicitly requires hasSSL and sets SSL verification and hostname options.
- [PluginDownloader.pm lines 9–11](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Utils/PluginDownloader.pm): LMS download ZIP must have `install.xml` at root, without extra plugin parent path.
- [AudioScrobbler/Plugin.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Plugin/AudioScrobbler/Plugin.pm): global Love handler intentionally NOT used. Existing scrobbling route remains untouched.

ListenBrainz authoritative documentation:

- https://listenbrainz.readthedocs.io/en/latest/users/api/core.html — `GET /1/user/{user}/playing-now` has at most one listen and no listened_at; recent listens support count/min_ts. `GET /1/validate-token` supports Authorization header and returns valid/user_name.
- https://listenbrainz.readthedocs.io/en/latest/users/api/recordings.html — feedback POST, user feedback GET with score/count/offset/metadata.
- https://listenbrainz.readthedocs.io/en/latest/users/feedback-json.html — score=1 with recording_mbid or recording_msid; feedback list contains identities and score.

Documentation and source review are not live API write verification. No real token was used or copied into this project.

## On-demand playing-now identity (0.2.0)

The [official submission format](https://listenbrainz.readthedocs.io/en/latest/users/json.html) documents `playing_now` as temporary state, without `listened_at`; permanent history requires a separate `single` or `import` submission. `POST /1/submit-listens?return_msid=true` returns a recording MSID for feedback before a completed listen exists. This behavior was also checked against `submit_listen` in [the upstream API implementation](https://github.com/metabrainz/listenbrainz-server/blob/master/listenbrainz/webserver/views/api.py) on 2026-10-24.

This plugin enables that fallback only inside its explicit Love action, rechecks current playback before sending it, and rejects completed-listen types and timestamps at the transport boundary. Existing exact identities retain priority. `playing_now` may also expose an existing MSID in `track_metadata.additional_info.recording_msid`.

## Source metadata and Material integration (0.3.1)

Compared LMS 9.1.1 `AudioScrobbler::Plugin::_getMetadata`, `checkScrobble`, and `API::ListenBrainz::getMetadata/_getTrackMetadata` with this plugin's capture path. AudioScrobbler reads `track->musicbrainz_id` for remote tracks too and falls back to `track->secs` when the protocol handler omits duration. The previous adapter omitted both. The adapter now preserves these sources; fresh explicit provider MBID/duration retain priority. No new remote lookup or completed-listen submission is introduced.

AudioScrobbler's `newsongCallback` first resolves `Slim::Schema->objectForUrl({url => $url})`. A playing Song's RemoteTrack may have a different ID and metadata from that canonical object. Version 0.3.1 mirrors this lookup before capturing source metadata. Material selection resolves a different selected ID through `Slim::Schema->find('Track', $id)` and requires the same exact current URL. Tests reproduce both differences; the metadata diagnostic exposes both object IDs and their MBIDs.

The [Material customisation documentation](https://github.com/CDrummond/lms-material/wiki/07-Customisation#custom-menu-entries-and-actions) documents plugin action registration since 6.4.6, `track` and `queue-track` contexts, native icon names, and `lmsbrowse`. Source review against installed version [6.4.14](https://github.com/CDrummond/lms-material/tree/6.4.14) confirmed `Plugin::registerCustomAction`, post-load `plugin-actions`, `$ITEMID` substitution, and native browse result rendering. Registration occurs in `postinitPlugin`, after plugins have loaded, and Material remains optional. A selected item ID is checked against the current track before any Love; stopped playback is still rejected. The heart action does not alter ratings or replace service-specific shuffle/repeat buttons.

The read-only `listenbrainzlove metadata` player query exposes the object/provider/effective IDs for live comparison without ListenBrainz reads or writes. Tests cover missing provider fields, precedence, registration without network activity, selected-item guards, async result handling, and Unicode labels.

## Metadata lookup and targeted feedback (0.4.0)

The user-requested [Lookup MBIDs example](https://listenbrainz.readthedocs.io/en/latest/users/api-usage.html#lookup-mbids) uses GET `/1/metadata/lookup/` with `artist_name` and `recording_name`. Version 0.4.0 follows that flow and sends optional `release_name` when available. The [endpoint reference](https://listenbrainz.readthedocs.io/en/latest/users/api/metadata.html) now requires `Authorization: Token ...`. Its optional expansion parameter is `inc`, while the older example spells it `incs`; this plugin requests no expansion and sends neither parameter. Release metadata is a hint, not proof of recording identity.

Checked [metadata_api.py](https://github.com/metabrainz/listenbrainz-server/blob/7d9a3d6f9d5283871d1aa48c9fa5301a1f4f8241/listenbrainz/webserver/views/metadata_api.py): `MAX_MAPPING_QUERY_LENGTH=250`; the sum is measured in Unicode characters before percent encoding. Both core and transport enforce that limit without truncating titles or versions. Empty `{}` is no-match; a nonempty incomplete response is an error. Candidates must contain a valid recording UUID, nonempty recording/artist names and compatible normalized names including all version words. The basic response does not supply duration, so this lookup does not claim to verify candidate duration.

The [recordings API](https://listenbrainz.readthedocs.io/en/latest/users/api/recordings.html) documents GET `get-feedback-for-recordings` with `recording_mbids` and/or `recording_msids`. This replaces first-100 favorites readback and also supplies read-only state. The implementation queries at most one of each type; it accepts score zero as known not-loved, checks exact requested IDs, and requires a shared row when verifying a write containing both IDs. [Upstream helper](https://github.com/metabrainz/listenbrainz-server/blob/7d9a3d6f9d5283871d1aa48c9fa5301a1f4f8241/listenbrainz/webserver/views/feedback_api.py#L203-L230), [zero-score pseudo records](https://github.com/metabrainz/listenbrainz-server/blob/7d9a3d6f9d5283871d1aa48c9fa5301a1f4f8241/listenbrainz/db/feedback.py#L235-L299).

Existing IDs are collected by type. Playing-now MSID does not short-circuit the bounded recent lookup. A mapped MBID wins; an MSID accompanies it only when the same accepted listen explicitly pairs them. Multiple MSIDs paired with one MBID do not need arbitrary selection: the MBID can be submitted alone. Conflicting MBIDs or ambiguous MSID-only matches fail closed.

Positive metadata lookup cache: exact source URL + metadata + username + algorithm version, SHA-256 key, 128 entries, one-hour TTL. No negative-result or credential cache. Available ISRC is captured for diagnostics and future resolver use; no ISRC-to-MBID API is introduced in this release. A network error or rejected candidate never silently falls through to a new identity.

Material's registered context entry is a static navigation icon. It opens a native bounded status list with verified filled/outline/unknown icons and a separate explicit Love action. No skin JavaScript, ratings hook, custom.js or background playing-now is installed. The existing TrackInfo Love action remains available alongside a read-only status link. Transport rejects Unlove, completed listens and manual mapping writes.

## Distribution repository format

The Material 6.4.14 renderer changes an untyped go action without an image into a text row. Its `doTextClick` uses a plain command for plugin verbs and omits list index/count arguments, so a tagged selection can be consumed as a positional argument. Version 0.4.1 sets `type=link` explicitly on both native Love and Refresh actions. This was isolated during live read-only testing, reproduced in regression assertions, and corrected without removing the selected-track guard.

## Non-playing selections and visible state (0.5.0)

The [feedback format](https://listenbrainz.readthedocs.io/en/latest/users/feedback-json.html) accepts recording MBID and score independently of any listen. Version 0.5.0 resolves the selected numeric Track ID, captures that track's URL and metadata, and allows verified feedback while another track plays, playback is stopped or the queue is empty. It never substitutes the current track for an invalid ID. TrackInfo already supplies its selected URL/object to providers; the same capture path now serves its selected-track actions.

Only matching current playback may supply playing-song MBID or forceCurrent. Inactive remote selections need positive object duration and complete provider artist/title metadata, avoiding indefinite stream station records. Playing-now fallback is enabled only for a snapshot matching actual active playback, then rechecked immediately before submission. No-match on a non-playing selection cannot manufacture a listen or now-playing notification.

Live read-only verification also exposed Material's short-list optimization: if a list contains only one distinct image, browse-resp.js clears all images. A distinct refresh icon preserves the state heart for both loved and not-loved lists. Explicit link rows route clicks on state/results to the read-only state command. No Material source files or ratings are modified.

The publication preparation reviewed the real [LyrionJS repo.xml](https://raw.githubusercontent.com/JameZUK/LyrionJS/main/repo.xml): `extensions/details/title` and `extensions/plugins/plugin`, attributes `name`, `version`, `minTarget`, `maxTarget`, and child elements `title`, `desc`, `creator`, `category`, `link`, `url`, `sha`. That example is on a mutable branch; it is a format example, not a pinned dependency.

The pinned LMS [PluginDownloader.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Utils/PluginDownloader.pm) imports `Digest::SHA1`; `_getDigest` opens the downloaded ZIP in binary mode and returns its SHA-1 hex digest. `_installDownload` compares that value with the repository's `sha`. Thus `repo.xml` uses **SHA-1 of the complete plugin ZIP**, not SHA-256 or a hash of source files. A separate SHA-256 manifest is provided for independent verification.

`tools/build.py` derives the version from `install.xml`, generates the plugin ZIP first, hashes it, then generates `repo.xml` and the source archive. This avoids a circular checksum dependency. The plugin ZIP does not contain `repo.xml`; the source archive does.
