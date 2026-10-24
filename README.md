# ListenBrainzLove 0.2.0 — testovací verze

Samostatný Perl plugin pro **Lyrion Music Server 9.1.x**, ověřený proti upstreamu **9.1.1**. Přidává do Track Info explicitní položku **ListenBrainz: Love currently playing**. Nemění Last.fm Love handler a nikdy neposílá scrobbly.

**Stav:** testovací verze. Instalace a stránka nastavení byly ověřeny na Lyrionu 9.1.1; skutečný ListenBrainz zápis dosud nebyl ověřen. Plugin nezasahuje do existujícího scrobblingu.

**Změny v 0.2.0:** Love může fungovat i před prvním dokončeným poslechem. Pokud chybí existující ID, ruční kliknutí může odeslat skutečné `playing_now` s `return_msid=true` a použít vrácené MSID. Jde o dočasné oznámení, nikoli dokončený scrobble. Zároveň se opravuje fallback z `playing_now` bez ID na dokončené poslechy. Potvrzení a chyby zůstávají čitelné v Material Skin.

## Instalace přes repo.xml

Veřejný repozitář: https://github.com/vysmaty/lyrion-listenbrainz-love, větev `main`, release `v0.2.0`. Samotný build nic nenahrává.

1. Přidat do **Settings → Plugins → Additional repositories** adresu:
   `https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/main/repo.xml`
2. Použít změny, vybrat **ListenBrainz Love**, nainstalovat a restartovat LMS podle výzvy. Minimální verze je 9.1.0; ověření cílilo na 9.1.1, nikoli všechny novější verze.
3. V nastavení pluginu zadat účet až po kontrole zabezpečení administračního rozhraní.

Release musí obsahovat **přesně ZIP vytvořený buildem**, pojmenovaný `ListenBrainzLove-0.2.0.zip`, nikoli automatický GitHub source ZIP. `repo.xml` odkazuje na `https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/dist-v0.2.0/dist/ListenBrainzLove-0.2.0.zip`, aby se vyhnul příliš dlouhým hlavičkám při stahování GitHub Release. Jeho `<sha>` je SHA-1 bajtů tohoto ZIPu; SHA-256 je dostupné v manifestu. Po změně zdrojů znovu sestavit a publikovat odpovídající ZIP, distribuční tag i XML.

## Použití

1. Balíček `ListenBrainzLove-0.2.0.zip` je standardní LMS plugin ZIP: `install.xml` přímo v kořeni. Zdrojový projekt má runtime soubory v `Plugins/ListenBrainzLove/`. Tento projekt sám nic neinstaluje do živého serveru.
2. V nastavení pluginu vyplnit username a token získaný přímo na ListenBrainz. Pole tokenu je `password`, je vždy prázdné při vykreslení; prázdné uložení zachová dosavadní token. Save ověřuje token i shodu `user_name` a neplatné nastavení neuloží.
3. Při přehrávání otevřít informace o právě hrající položce a zvolit **ListenBrainz: Love currently playing**. Akce vědomě znamená skladbu aktuální **v okamžiku kliku**, nikoli v okamžiku otevření menu. Po async odpovědi se metadata z přehrávače už nepřepisují.
4. Kliknutí už provede akci Love; další potvrzovací tlačítko není potřeba. Výsledek zůstane v menu jako **ListenBrainz Love verified**, nebo **ListenBrainz Love failed: …** s důvodem. Úspěch znamená až přesnou shodu recording ID a score=1 při následném GET readbacku.

Nativní TrackInfo provider je určen i pro klienty využívající standardní menu včetně Material Skin; **klikání v Material Skin ani skutečný přehrávač/Radio Paradise nebyly při tomto vývoji testovány**.

## Identifikace a hranice

- Snapshot obsahuje artist, title, version, recording MBID, album, délku a číslo skladby. Radio metadata se načítají čerstvě přes protocol handler `getMetadataFor(client, currentTrack->url, 'forceCurrent')`. URL slouží k nalezení zdroje metadat a kontrole stále stejného přehrávání, nikdy jako identita nahrávky.
- Přednost má syntakticky validní recording UUID z přehrávače; neplatný neprázdný MBID skončí chybou. Plugin samostatně neověřuje MusicBrainz záznam podle názvu, spoléhá na autoritativní metadata zdroje.
- Bez MBID následuje dokumentovaný `GET /1/user/{user}/playing-now`, pak při chybějícím ID omezený recent `listens?count=100&min_ts=<klik-300s>`. ID lze převzít i z `track_metadata.additional_info.recording_msid`. Metadata v `playing_now` bez ID neblokují fallback na dokončené poslechy.
- Artist a title se porovnávají **přesně**, bez fuzzy normalizace nebo ořezání označení verzí. Pokud snapshot obsahuje samostatnou version, musí shodnou hodnotu poskytnout i listen `additional_info.version`. Prázdná samostatná version neodstraňuje verzi obsaženou v title.
- Recent listen musí mít timestamp v intervalu klik−300 až klik. Sto vrácených recent položek znamená potenciálně oříznutý výsledek a bezpečnou chybu. Dvě různé exact recording identity znamenají ambiguity a žádný POST. Shodné opakované listeny jedné identity lze sloučit.
- Pokud po těchto kontrolách chybí existující ID, plugin znovu ověří stále stejné aktivní přehrávání a odešle jediný `POST /1/submit-listens?return_msid=true` typu `playing_now`. Obsahuje skutečně zachycenou skladbu včetně dostupného alba, délky a čísla skladby, bez `listened_at`. Love použije přesně validní MSID vrácené tímto požadavkem. Změna skladby, zastavení, chyba či chybějící ID skončí bez Love. Tento fallback se spouští pouze ruční akcí, nikoli při otevření menu nebo automaticky.
- Playing-now dle API nemá `listened_at`; plugin věří čerstvě načtenému aktuálnímu stavu služby, nikoli nedokumentovanému času. Neumí prokázat stáří chybně zatuhlého provider playing-now. Celá operace je použitelná nejvýše 30 sekund od kliku; každý HTTP request má timeout 8 sekund.
- Readback je záměrně omezen na prvních 100 Loved záznamů (`score=1&metadata=true&count=100&offset=0`). Nenalezení ID je chyba/neověřený výsledek; žádné procházení celé historie. POST mohl být uložen i když readback selhal. Opakování Love je idempotentní pro dané recording ID.
- Žádná pending queue, unlove, synchronizace playlistů ani automatický Love. Transport dovoluje pouze jednotlivé skutečné `playing_now` bez timestampu; typy `single` a `import`, více skladeb či `listened_at` odmítne ještě před HTTP. Dokončené poslechy dál řeší stávající scrobbler.

## Bezpečnost

Provider origin je pevně `https://api.listenbrainz.org`; endpointy a metody jsou allowlistované, redirects vypnuté. Token je pouze v Authorization headeru, nikdy v URL nebo plugin logu. Chyby neodrážejí server payload ani token. TLS certifikát a hostname se ověřují explicitně; při chybějícím SSL plugin odmítne request, místo aby LMS degradoval na HTTP.

Token se po schváleném uložení ukládá do běžných lokálních LMS preferences (`plugin/listenbrainzlove.prefs`), **není šifrovaný**. Zabezpečit soubory a nastavení LMS, nepoužívat nedůvěryhodné HTTP spojení pro zadávání tokenu. Plugin nesahá na `LISTENBRAINZ_TOKEN` z prostředí. V testech jsou výlučně viditelně syntetické fixture hodnoty, nikoli skutečné credentials.

## Spuštění testů

```sh
cd lyrion-listenbrainz-love
prove -v t
python3 tools/build.py
# Volitelné: python3 tools/isolated_lms.py
# vyžaduje vlastní disposable clone LMS 9.1.1 v .local/lms-9.1.1
```

Build spustí celou Perl sadu, vytvoří `dist/ListenBrainzLove-0.2.0.zip`, zdrojový ZIP, `manifest.json`, `SHA1SUMS`, `SHA256SUMS` a kopii `repo.xml`. Adresář `.publication/` je čistá kopie zdrojů určená k publikaci. Plugin ZIP má `install.xml` v kořeni. ZIPy mají stabilní pořadí, timestamp a oprávnění; SHA závisí na přesných bajtech výsledku. Build používá explicitní allowlist zdrojových souborů a nepřebírá evidence, credentials, lokální stav ani staré archivy. Před publikací je přesto nutná kontrola obsahu zdrojů. Lokální výstup testů zůstává pouze v ignorovaném `evidence/publication-tests.log`.

Perl testy používají core `Test::More`, `JSON::PP`, `HTTP::Tiny`, `IO::Socket::INET`, `fork`; nevyžadují Docker ani CPAN instalaci. Poslední ověřený výsledek: **15 souborů, 208 assertions, PASS**. `t/09-http.t` skutečně spouští lokální TCP HTTP fake server, přijme POST a vrátí uložené přesné ID. Ostatní testy používají injekci transportu a minimální LMS facades tam, kde není smysluplné spouštět server pro každý negativní scénář.

Testy zahrnují přímý MBID, MSID z rádia, změnu metadat po kliku i mezi menu a klikem, recent fallback, ambiguity, stale/future listens, jiného interpreta/verzi, saturaci výsledků, neplatný token/username, redakci chyb, neplatný JSON/payload, falešný POST úspěch, špatné readback ID/score, povinné TLS a zákaz jiných providerů/scrobbling endpointu. Vývojové a integrační logy nejsou součástí publikovaných zdrojů ani ZIPů.

### Izolované integrační ověření

Při předchozím vývoji byl v izolovaném disposable stromu spuštěn upstream tag 9.1.1, commit `1ceeaf1d601134f765b5a3e65113726284eaae6d`. Oddělené prefs/cache/logs, bind loopback, ostatní pluginy disabled, žádný přehrávač ani token. Ověřeno HTTP 200 a vyrenderované nastavení s password inputem a username. Nejde o nové ověření při přípravě vydání; lokální integrační logy se nepublikují. Pomocný skript používá pouze `.local/` v projektu a není součástí běžného buildu.

**Omezení:** zdejší Perl nemá IO::Socket::SSL. Server běží, ale skutečný TLS provider transport nebyl v tomto prostředí otestován; plugin pro tuto situaci fail-closed testy má. Nebyl proveden skutečný ListenBrainz write, žádný live credential test, GUI klik ani end-to-end cesta z reálného Radio Paradise. Transportové testy s facadami nedokazují skutečný TLS handshake. To jsou další gate před schválením nasazení.

[English](README.en.md) · [ověření upstream API](docs/UPSTREAM.md) · [licence](LICENSE)
