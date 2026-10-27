# ListenBrainzLove 0.7.6

Samostatný Perl plugin pro Lyrion Music Server 9.1.x. Ručně označí vybranou nahrávku jako **Love** na ListenBrainz a ověří uložený stav. Skladba nemusí právě hrát. Dokončené poslechy dál odesílá stávající scrobbler.

Verze 0.7.6 opravuje HTML značky zobrazované v popupu z detailu skladby. Potvrzení i chyby jsou čistý text. Zachovává čekání na dosud nenačtená metadata nepřehrávané skladby. Zachovává společnou frontu API požadavků, sdílenou cache a rušení Love kliknutím na plné srdíčko. Stav Love zůstává v detailu skladby, místní nabídka obsahuje jen přímé Love. Zachovává dokumentovaný metadata lookup, přednost dostupného recording MBID před MSID a cílené ověření konkrétní nahrávky. ISRC se zachytí, pokud ho poskytovatel vrací; samostatný ISRC resolver tato verze nezavádí.

## Použití

V Material Skin 6.4.6+ otevřít menu vybrané skladby a zvolit **ListenBrainz Love**. Jedno kliknutí rovnou požádá o Love a po ověření zobrazí nativní popup s výsledkem. Při chybě nebo neověřeném zápisu popup nehlásí úspěch. Aktuální pohled se nepřepíná.

Položka **ListenBrainz: Love status** v detailu skladby pouze načte stav: plné srdíčko pro potvrzené Love, obrys pro známý neoznačený stav, otazník při neznámém stavu. Duplicitní příkaz pro stav v místní nabídce Materialu není. U MSID je odlišeno nepotvrzené propojení s MusicBrainz.

Volitelné desktopové srdíčko lze zapnout v nastavení pluginu. Je ve spodní liště vedle hvězdiček a ukazuje ověřený stav aktuální skladby. Kliknutí na prázdné srdíčko požádá o Love; kliknutí na plné srdíčko Love zruší. Ikona se změní až po ověření uloženého stavu. Po nejistém zápisu další kliknutí nejprve obnoví stav. Pravé kliknutí také jen čte a obejde krátkou cache stavu. Dvojklik neopakuje zápis. Změna skladby či přehrávače ruší použití zastaralé odpovědi.

Srdíčko používá dokumentovaný `prefs/material-skin/custom.js`: plugin po výslovném zapnutí přidá označený loader a původní obsah zachová, případně uloží do `custom.js.before-listenbrainzlove`. Vypnutí v nastavení odstraní jen jeho vlastní blok. Po zapnutí/vypnutí obnovit Material; před odinstalací srdíčko vypnout. Jádro Material Skin ani hvězdičky se nemění. Mobilní nabídka funguje dál; tlačítko ve spodní liště je desktopové. Bez zapnutí této volby se `custom.js` nemění.

Ve standardních informacích o skladbě jsou přímá akce **ListenBrainz: Love selected track** a odkaz **ListenBrainz: Love status**. V Materialu akce Love zobrazí ověřený výsledek v popupu a zachová detail skladby; ostatní klienti mají nadále k dispozici OPML callback. Fungují také při zastavení či prázdné frontě, pokud Lyrion zná vybranou skladbu a její spolehlivá metadata. Na chybějící metadata vzdálené skladby plugin asynchronně čeká nejvýše 8 sekund. Zachovává původní výběr i celkový 30sekundový limit, při čekání neposílá požadavky ListenBrainz a zápis Love neopakuje. U vzdálené nepřehrávané položky se vyžaduje známá kladná délka, aby se nepoužila neurčitá rozhlasová stanice jako konkrétní nahrávka. Po načtení metadat poskytovatele lze stav obnovit. Neznámé/neplatné ID nikdy neoznačí místo výběru právě hrající skladbu. Automatická migrace starších oblíbených není součástí této verze.

## Jak se získá identita

1. Zachytit neměnný snímek vybrané skladby v okamžiku kliku. Použít její kanonický objekt podle URL jako AudioScrobbler a metadata poskytovatele pro tutéž URL. TIDAL MAIN/FEATURED a lokální ARTIST/TRACKARTIST se zachovají v úplném kreditu; skladatelé a dirigenti se nepřidávají. Příznak `forceCurrent` a MBID aktuálního přehrávání se nepřebírají pro jinou skladbu.
2. Upřednostnit důvěryhodné zdrojové recording MBID nebo dříve přijatou cache stejného zdroje a metadat.
3. Jinak přečíst ListenBrainz playing-now a případně nedávné poslechy. Samotné MSID v playing-now nezastaví hledání dostupného MBID. Historie je omezená na 300 sekund a méně než 100 položek. Sto položek znamená potenciálně oříznutý výsledek a bezpečnou chybu.
4. Pokud MBID chybí, zavolat autentizovaný `GET /1/metadata/lookup/` s `artist_name`, `recording_name` a případně `release_name`. Samostatná verze skladby je součástí názvu pro lookup.
5. Přijmout pouze validní recording UUID s odpovídajícím interpretem a názvem včetně verze. Normalizuje se Unicode, velikost písmen a interpunkční oddělovače; žádné fuzzy hádání ani odstraňování live/remix/cover označení. Album je vodítko, nikoli požadavek na stejné vydání. Základní lookup nevrací délku kandidáta, proto se její ověření nepředstírá. U již existujících poslechů se dvě dostupné délky porovnají s tolerancí tří sekund.
6. Love odeslat samostatným feedbackem s `score=1`. MBID a MSID se posílají společně pouze tehdy, když je stejný přijatý listen výslovně páruje. Při více MSID pro jedno MBID lze použít samotné MBID. Konfliktní MBID nebo nejednoznačná MSID skončí bez zápisu.
7. Použít cílené `get-feedback-for-recordings` a ověřit přesné ID a `score=1`. Zápis obou ID vyžaduje potvrzenou společnou vazbu. Kontrola není závislá na prvních 100 oblíbených.

Cache přijatých MBID má nejvýše 128 položek a hodinovou platnost; klíč zahrnuje účet, zdrojovou URL, metadata a verzi algoritmu. URL je v klíči hashovaná. Ověření tokenu se ukládá na 5 minut, ověřený stav Love na 30 sekund. Obě nové cache jsou sdílené mezi přehrávači a otevřenými stránkami, mají nejvýše 128 položek a odděluje je SHA-256 účtu a tokenu; samotný token se do cache neukládá. Souběžné kontroly stejné skladby se sloučí. Nenalezení ani chyby se necachují. Změna Love zneplatní cache stavu účtu před operací i po ní; nový stav se uloží až po ověření. Pozdní odpověď starší kontroly ho nepřepíše. Výslovné obnovení stavu obejde cache. Změna provedená mimo plugin se při nové automatické kontrole může projevit až po 30 sekundách; během stejné skladby se stav periodicky nekontroluje.

Rušení Love posílá `score=0`, nikoli dislike (`-1`). Použije stejnou vybranou identitu nebo nedávno ověřenou dvojici MBID/MSID. Cílený readback musí potvrdit nulu u každého poslaného ID; po smazání jsou přípustné samostatné nulové řádky. Rušení Love nikdy nevytváří playing-now. Formát UUID sám neprokazuje typ nebo správnost nahrávky; přímé zdrojové recording MBID se stejně jako u scrobbleru považuje za autoritativní. Textový lookup není důkazem jedinečné shody v celém katalogu.

## Fallback přes MSID

Pouze prázdná odpověď lookupu znamená potvrzené nenalezení. Pak lze použít již existující odpovídající MSID. Pokud chybí i to, výhradně ruční Love skutečně přehrávané skladby znovu ověří stejné aktivní přehrávání a odešle jeden skutečný `playing_now?return_msid=true`, bez timestampu. Na vrácené MSID uloží a ověří Love. Nevzniká dokončený scrobble. Nepřehrávaná skladba bez dohledatelné identity skončí bez zápisu; nepředstírá přehrávání. Čtení stavu tuto cestu nikdy nespouští.

Neúplná odpověď, jiné jméno/verze, síťová chyba nebo vyčerpaný limit nejsou nenalezením a nesmí tiše změnit identitu. MSID úspěch se neoznačuje jako potvrzené MusicBrainz propojení.

## Instalace

Do **Settings → Plugins → Additional repositories** přidat:

`https://raw.githubusercontent.com/vysmaty/lyrion-listenbrainz-love/main/repo.xml`

Použít změny, vybrat **ListenBrainz Love** a nainstalovat/restartovat podle výzvy. V nastavení pluginu zadat ListenBrainz username a token. Prázdné pole tokenu při uložení zachová stávající hodnotu. Ověřuje se platnost tokenu i vlastník účtu.

Minimální verze je deklarovaná 9.1.0; integrační ověření cílí na Lyrion 9.1.1. Veřejný projekt: [vysmaty/lyrion-listenbrainz-love](https://github.com/vysmaty/lyrion-listenbrainz-love), vydání `v0.7.6`.

Repozitář používá přesně sestavený standardní plugin ZIP s `install.xml` v kořeni a SHA-1 celých bajtů ZIPu. `repo.xml` odkazuje na distribuční tag `dist-v0.7.6`; samostatný SHA-256 je v manifestu. GitHub source ZIP není instalační balíček.

## Bezpečnost a diagnostika

Pevný origin `https://api.listenbrainz.org`, povolené konkrétní cesty/metody, povinné TLS a ověření hostname, žádné redirecty. Token pouze v Authorization hlavičce, nikdy v URL či logu. Lookup respektuje součet nejvýše 250 Unicode znaků a korektní UTF-8 percent encoding. HTTP požadavek má timeout 8 sekund, operace limit 30 sekund včetně čekání ve frontě. Všechny požadavky pluginu včetně nastavení procházejí jedinou asynchronní FIFO frontou: nanejvýš jeden aktivní požadavek, odstup začátků alespoň 1,05 sekundy a nejvýše 32 čekajících. Propadlý zápis se neodešle. Čekající playing-now těsně před odesláním znovu ověří aktuální přehrávání. HTTP 429 zavádí cooldown podle číselného Retry-After / X-RateLimit-Reset-In; bez údaje 30 sekund. Nulový počet zbývajících požadavků také blokuje další volání. Čekající operace skončí chybou bez automatického opakování. Vypnutí pluginu zruší čekající frontu.

Transport odmítá `single`, `import`, timestampy v now-playing, více skladeb, ruční mapování a jiné hodnoty feedbacku než Love a jeho zrušení. Nikdy se neregistruje globální AudioScrobbler Love handler. Současné opakované změny Love pro stejný přehrávač jsou během ověřování blokované.

Token je uložený v běžných lokálních LMS preferences, nikoli šifrovaný; zabezpečit administraci serveru a jeho soubory. Plugin nepřebírá token z prostředí. Diagnostický příkaz `listenbrainzlove metadata` přečte objektová/provider/effective ID, ISRC a metadata i při zastavení, bez ListenBrainz requestu. Nevrací token ani potenciálně credentialed streamovou URL.

## Ověření a build

`prove -v t` (Perl + Node.js pro UI testy): **27 souborů, 594 assertions, PASS**. Regrese zahrnují rozestupy fronty, cooldown, expiraci a vypnutí, životnost a souběh cache, její zneplatnění při změně Love, ověřené rušení Love a klikání na srdíčko. Dále přednost MBID před MSID, lookup před prvním scroblem, české znaky, jiné verze, bezpečné limity, cílený readback, neověřený POST, nepřehrávaný výběr, zákaz falešného playing-now a dva skutečné lokální TCP/HTTP fake servery. Tyto testy nepoužívají skutečný účet ani skutečné Like zápisy.

`python tools/build.py` spustí testy a vytvoří `dist/ListenBrainzLove-0.7.6.zip`, source ZIP, manifesty, `repo.xml` a čistou kopii publikovatelných zdrojů v `.publication/`. Zdrojový balíček neobsahuje lokální diagnostické poznámky, listening-history evidence ani credentials. Build nic nepublikuje ani nenasazuje.

Testovací Perl nemá IO::Socket::SSL: testy transportu používají facades a nevydávají se za reálný TLS handshake. Před vydáním je potřeba doplnit ověření v cílovém LMS a Material Skin; skutečný feedback lze ověřit ručním kliknutím uživatele.

[English](README.en.md) · [ověřené API a zdroje](docs/UPSTREAM.md) · [licence](LICENSE)
