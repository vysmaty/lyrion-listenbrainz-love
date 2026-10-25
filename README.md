# ListenBrainzLove 0.4.1

Samostatný Perl plugin pro Lyrion Music Server 9.1.x. Ručně označí právě hrající nahrávku jako **Love** na ListenBrainz a ověří uložený stav. Dokončené poslechy dál odesílá stávající scrobbler.

Verze 0.4.1 přidává dokumentovaný metadata lookup, přednost dostupného recording MBID před MSID, cílené ověření konkrétní nahrávky a čtení stavu srdíčka. ISRC se zachytí, pokud ho poskytovatel vrací; samostatný ISRC resolver tato verze nezavádí.

## Použití

V Material Skin 6.4.6+ otevřít menu právě hrající skladby nebo její položky ve frontě a zvolit **ListenBrainz Love**. Tato položka pouze načte stav. Nativní nabídka zobrazí plné srdíčko pro potvrzené Love, obrys pro známý neoznačený stav nebo otazník, pokud stav nelze zjistit. U MSID upozorní, že propojení s MusicBrainz není potvrzené.

**Označit právě hrající skladbu jako Love** je samostatná ruční akce. **Obnovit stav Love** pouze čte. Při neověřeném výsledku zápisu nabídka upozorní, že feedback už mohl být uložen. Otevření nabídky nic nezapisuje.

Ikona vstupní položky kontextového menu je statická; skutečný stav ukazuje až nabídka pluginu. Hvězdičky Lyrionu zůstávají nezávislé. Plugin nemění JavaScript Material Skin ani uživatelův `custom.js`. Po aktualizaci obnovit stránku Material Skin.

Ve standardních informacích o skladbě zůstávají přímá akce **ListenBrainz: Love currently playing** a odkaz **ListenBrainz: Love status**. Love funguje jen pro právě hrající skladbu. Při zastaveném přehrávání lze stav pouze přečíst. Unlove ani automatická migrace starších oblíbených nejsou součástí této verze.

## Jak se získá identita

1. Zachytit neměnný snímek skladby v okamžiku kliku. Použít kanonický objekt podle URL jako AudioScrobbler a čerstvá metadata poskytovatele.
2. Upřednostnit důvěryhodné zdrojové recording MBID nebo dříve přijatou cache stejného zdroje a metadat.
3. Jinak přečíst ListenBrainz playing-now a případně nedávné poslechy. Samotné MSID v playing-now nezastaví hledání dostupného MBID. Historie je omezená na 300 sekund a méně než 100 položek. Sto položek znamená potenciálně oříznutý výsledek a bezpečnou chybu.
4. Pokud MBID chybí, zavolat autentizovaný `GET /1/metadata/lookup/` s `artist_name`, `recording_name` a případně `release_name`. Samostatná verze skladby je součástí názvu pro lookup.
5. Přijmout pouze validní recording UUID s odpovídajícím interpretem a názvem včetně verze. Normalizuje se Unicode, velikost písmen a interpunkční oddělovače; žádné fuzzy hádání ani odstraňování live/remix/cover označení. Album je vodítko, nikoli požadavek na stejné vydání. Základní lookup nevrací délku kandidáta, proto se její ověření nepředstírá. U již existujících poslechů se dvě dostupné délky porovnají s tolerancí tří sekund.
6. Love odeslat samostatným feedbackem s `score=1`. MBID a MSID se posílají společně pouze tehdy, když je stejný přijatý listen výslovně páruje. Při více MSID pro jedno MBID lze použít samotné MBID. Konfliktní MBID nebo nejednoznačná MSID skončí bez zápisu.
7. Použít cílené `get-feedback-for-recordings` a ověřit přesné ID a `score=1`. Zápis obou ID vyžaduje potvrzenou společnou vazbu. Kontrola není závislá na prvních 100 oblíbených.

Cache obsahuje jen přijatá MBID: nejvýše 128 položek na hodinu, klíč zahrnuje účet, zdrojovou URL, metadata a verzi algoritmu. URL je v klíči hashovaná. Nenalezení a síťové chyby se necachují. Formát UUID sám neprokazuje typ nebo správnost nahrávky; přímé zdrojové recording MBID se stejně jako u scrobbleru považuje za autoritativní. Textový lookup není důkazem jedinečné shody v celém katalogu.

## Fallback přes MSID

Pouze prázdná odpověď lookupu znamená potvrzené nenalezení. Pak lze použít již existující odpovídající MSID. Pokud chybí i to, výhradně ruční Love znovu ověří stejné aktivní přehrávání a odešle jeden skutečný `playing_now?return_msid=true`, bez timestampu. Na vrácené MSID uloží a ověří Love. Nevzniká dokončený scrobble. Čtení stavu tuto cestu nikdy nespouští.

Neúplná odpověď, jiné jméno/verze, síťová chyba nebo vyčerpaný limit nejsou nenalezením a nesmí tiše změnit identitu. MSID úspěch se neoznačuje jako potvrzené MusicBrainz propojení.

## Instalace

Do **Settings → Plugins → Additional repositories** přidat:

`https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/main/repo.xml`

Použít změny, vybrat **ListenBrainz Love** a nainstalovat/restartovat podle výzvy. V nastavení pluginu zadat ListenBrainz username a token. Prázdné pole tokenu při uložení zachová stávající hodnotu. Ověřuje se platnost tokenu i vlastník účtu.

Minimální verze je deklarovaná 9.1.0; integrační ověření cílí na Lyrion 9.1.1. Veřejný projekt: [vysmaty/lyrion-listenbrainz-love](https://github.com/vysmaty/lyrion-listenbrainz-love), vydání `v0.4.1`.

Repozitář používá přesně sestavený standardní plugin ZIP s `install.xml` v kořeni a SHA-1 celých bajtů ZIPu. `repo.xml` odkazuje na distribuční tag `dist-v0.4.1`; samostatný SHA-256 je v manifestu. GitHub source ZIP není instalační balíček.

## Bezpečnost a diagnostika

Pevný origin `https://api.listenbrainz.org`, povolené konkrétní cesty/metody, povinné TLS a ověření hostname, žádné redirecty. Token pouze v Authorization hlavičce, nikdy v URL či logu. Lookup respektuje součet nejvýše 250 Unicode znaků a korektní UTF-8 percent encoding. HTTP požadavek má timeout 8 sekund, operace limit 30 sekund. HTTP 429 zavádí cooldown podle číselného Retry-After / X-RateLimit-Reset-In; bez údaje 30 sekund. Žádné automatické opakování zápisu.

Transport odmítá `single`, `import`, timestampy v now-playing, více skladeb, ruční mapování a jiné hodnoty feedbacku než Love. Nikdy se neregistruje globální AudioScrobbler Love handler. Současné opakované Love pro stejný přehrávač je během ověřování blokované.

Token je uložený v běžných lokálních LMS preferences, nikoli šifrovaný; zabezpečit administraci serveru a jeho soubory. Plugin nepřebírá token z prostředí. Diagnostický příkaz `listenbrainzlove metadata` přečte objektová/provider/effective ID, ISRC a metadata i při zastavení, bez ListenBrainz requestu. Nevrací token ani potenciálně credentialed streamovou URL.

## Ověření a build

`prove -v t`: **19 souborů, 382 assertions, PASS**. Regrese zahrnují přednost MBID před MSID, lookup před prvním scroblem, české znaky, jiné verze, bezpečné limity, cache, cílený readback, neověřený POST, read-only stavy, výběr skladby a dva skutečné lokální TCP/HTTP fake servery. Tyto testy nepoužívají skutečný účet ani skutečné Like zápisy.

`python tools/build.py` spustí testy a vytvoří `dist/ListenBrainzLove-0.4.1.zip`, source ZIP, manifesty, `repo.xml` a čistou kopii publikovatelných zdrojů v `.publication/`. Zdrojový balíček neobsahuje lokální diagnostické poznámky, listening-history evidence ani credentials. Build nic nepublikuje ani nenasazuje.

Testovací Perl nemá IO::Socket::SSL: testy transportu používají facades a nevydávají se za reálný TLS handshake. Před vydáním je potřeba doplnit ověření v cílovém LMS a Material Skin; skutečný feedback lze ověřit ručním kliknutím uživatele.

[English](README.en.md) · [ověřené API a zdroje](docs/UPSTREAM.md) · [licence](LICENSE)
