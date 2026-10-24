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

## Distribution repository format

The publication preparation reviewed the real [LyrionJS repo.xml](https://raw.githubusercontent.com/JameZUK/LyrionJS/main/repo.xml): `extensions/details/title` and `extensions/plugins/plugin`, attributes `name`, `version`, `minTarget`, `maxTarget`, and child elements `title`, `desc`, `creator`, `category`, `link`, `url`, `sha`. That example is on a mutable branch; it is a format example, not a pinned dependency.

The pinned LMS [PluginDownloader.pm](https://github.com/LMS-Community/slimserver/blob/1ceeaf1d601134f765b5a3e65113726284eaae6d/Slim/Utils/PluginDownloader.pm) imports `Digest::SHA1`; `_getDigest` opens the downloaded ZIP in binary mode and returns its SHA-1 hex digest. `_installDownload` compares that value with the repository's `sha`. Thus `repo.xml` uses **SHA-1 of the complete plugin ZIP**, not SHA-256 or a hash of source files. A separate SHA-256 manifest is provided for independent verification.

`tools/build.py` derives the version from `install.xml`, generates the plugin ZIP first, hashes it, then generates `repo.xml` and the source archive. This avoids a circular checksum dependency. The plugin ZIP does not contain `repo.xml`; the source archive does.
