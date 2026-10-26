/* ListenBrainzLove: optional Material Skin desktop heart and manual action. */
(function () {
    'use strict';
    if (window.ListenBrainzLoveMaterial) return;
    const pending = new Map();
    let enabled = false, current = null, result = null, button = null, readSequence = 0;
    const cs = () => typeof lmsOptions !== 'undefined' && /^cs$/i.test(lmsOptions.lang);
    const text = (en, cz) => cs() ? cz : en;
    const valid = id => /^(?:track_id:)?-?\d+$/.test(String(id));
    const normalized = id => 'track_id:' + String(id).replace(/^track_id:/, '');
    const key = (pid, id) => String(pid) + '/' + normalized(id);
    const notice = data => {
        const message = data && typeof data.message === 'string' ? data.message : text('ListenBrainz: Save not verified. Refresh the Love status before trying again.', 'ListenBrainz: Uložení není ověřené. Před opakováním obnovte stav Love.');
        if (data && Number(data.ok) === 1) bus.$emit('showMessage', message, 6);
        else bus.$emit('showError', undefined, message, 12);
    };
    async function request(pid, id, method, refresh) {
        const command = ['listenbrainzlove', method, 'selected_id:' + normalized(id)];
        if (refresh) command.push('refresh:1');
        const response = await lmsCommand(pid, command);
        const data = response && response.data && response.data.result;
        if (!data || !Object.prototype.hasOwnProperty.call(data, 'ok')) throw new Error('Invalid ListenBrainz response');
        return data;
    }
    async function write(pid, id, method) {
        if (!pid || !valid(id)) { notice({message:text('ListenBrainz: Select a known track first.', 'ListenBrainz: Nejprve vyberte skladbu.')}); return; }
        if (pending.has(pid)) return pending.get(pid);
        const target = key(pid, id);
        const selectedKey = current && current.identity === target ? current.key : null;
        readSequence++; // An older status read must not override this write.
        const operation = (async function () {
            let data;
            try { data = await request(pid, id, method); }
            catch (_) { data = {ok:0, uncertain:1}; }
            notice(data);
            // A response for the old track/player must not fill the new track's heart.
            if (current && selectedKey && current.key === selectedKey) { readSequence++; result = data; }
            return data;
        })();
        pending.set(pid, operation); render();
        try { return await operation; }
        finally { pending.delete(pid); render(); }
    }
    function love(pid, id) { return write(pid, id, 'action'); }
    async function readStatus(announce) {
        if (!current) return;
        const target = current, sequence = ++readSequence;
        let data;
        try { data = await request(target.pid, target.id, 'status', announce); }
        catch (_) { data = {ok:0,message:text('ListenBrainz: State unknown. Click the heart to retry.', 'ListenBrainz: Stav není známý. Kliknutím na srdíčko zkuste Love.')}; }
        if (current && target.key === current.key && sequence === readSequence) { result = data; render(); }
        if (announce) notice(data);
        return data;
    }
    function select(pid, track) {
        if (!pid || !track || !valid(track.id)) { current = null; result = null; readSequence++; render(); return; }
        const identity = key(pid,track.id);
        const next = {pid:pid,id:track.id,identity:identity,key:identity+'\u0000'+[track.title,track.artist,track.album,track.duration].map(x => String(x || '')).join('\u0000')};
        if (current && current.key === next.key) return;
        current = next; result = null; render();
        readStatus(false).then(data => {
            // A cold provider can need one fetch before artist/title metadata exists.
            if (data && !Number(data.ok) && /Missing artist|selected-track metadata/.test(data.error || '')) {
                setTimeout(() => { if (current && current.key === next.key) readStatus(false); }, 2000);
            }
        });
    }
    function render() {
        if (!button) return;
        const known = result && Number(result.ok) === 1;
        const loved = known && Number(result.score) === 1;
        const busy = current && pending.has(current.pid);
        button.disabled = !current || !!busy;
        button.setAttribute('aria-busy', String(!!busy));
        button.setAttribute('aria-pressed', String(!!loved));
        const title = busy ? text('ListenBrainz: Verifying change…', 'ListenBrainz: Ověřuji změnu…') : loved ? text('ListenBrainz: Loved. Click to remove Love.', 'ListenBrainz: Love potvrzeno. Kliknutím zrušit Love.') : result && result.uncertain ? text('ListenBrainz: Save not verified. Click to refresh status.', 'ListenBrainz: Uložení není ověřené. Kliknutím obnovit stav.') : text('ListenBrainz: Love the current track', 'ListenBrainz: Označit aktuální skladbu jako Love');
        button.title = title; button.setAttribute('aria-label', title);
        button.dataset.state = known ? (loved ? 'filled' : 'outline') : 'unknown';
        button.querySelector('path').setAttribute('d', loved ? 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54Z' : 'M16.5 3A5.98 5.98 0 0 0 12 5.09 5.98 5.98 0 0 0 7.5 3C4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3ZM12.1 18.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5A3.47 3.47 0 0 1 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87A3.85 3.85 0 0 1 16.5 5 3.47 3.47 0 0 1 20 8.5c0 2.89-3.14 5.74-7.9 10.05Z');
        button.querySelector('text').textContent = known ? '' : '?';
    }
    function mount() {
        const bar = document.getElementById('np-bar');
        if (!bar || (button && button.isConnected)) return;
        const details = bar.querySelector('.np-bar-details');
        const action = details && details.querySelector('.v-list__tile__action');
        if (!action) return;
        details.classList.add('listenbrainz-love-host');
        button = document.createElement('button'); button.type = 'button'; button.id = 'listenbrainz-love-button';
        button.className = 'listenbrainz-love-button';
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path'); path.setAttribute('fill','currentColor'); svg.appendChild(path);
        const mark = document.createElementNS('http://www.w3.org/2000/svg', 'text');
        mark.setAttribute('x','12'); mark.setAttribute('y','14'); mark.setAttribute('text-anchor','middle'); mark.setAttribute('font-size','10'); mark.setAttribute('fill','currentColor'); svg.appendChild(mark);
        button.appendChild(svg);
        button.addEventListener('click', event => {
            event.stopPropagation();
            if (!current) return;
            if (result && result.uncertain) readStatus(true);
            else if (result && Number(result.ok) === 1 && Number(result.score) === 1) write(current.pid, current.id, 'unlove');
            else love(current.pid, current.id);
        });
        button.addEventListener('contextmenu', event => { event.preventDefault(); event.stopPropagation(); readStatus(true); });
        action.appendChild(button); render();
    }
    function enableButton() {
        if (enabled || typeof bus === 'undefined' || typeof store === 'undefined') return;
        enabled = true;
        const style = document.createElement('style');
        style.textContent = '#np-bar:not(.mobile) .listenbrainz-love-host .v-list__tile__action{position:relative;margin-left:52px}.listenbrainz-love-button{position:absolute;right:calc(100% + 4px);top:50%;transform:translateY(-50%);width:44px;height:44px;padding:10px;margin:0;border:0;border-radius:50%;background:transparent;color:inherit;cursor:pointer;display:inline-flex;align-items:center;justify-content:center}.listenbrainz-love-button svg{width:24px;height:24px}.listenbrainz-love-button:hover{background:rgba(127,127,127,.18)}.listenbrainz-love-button:focus-visible{outline:2px solid currentColor;outline-offset:-2px}.listenbrainz-love-button:disabled{opacity:.5;cursor:default}#np-bar.mobile .listenbrainz-love-button{display:none}';
        document.head.appendChild(style);
        new MutationObserver(mount).observe(document.body,{childList:true,subtree:true});
        bus.$on('playerStatus', status => select(store.state.player && store.state.player.id, status && status.current));
        bus.$on('playerChanged', () => { current=null; result=null; readSequence++; render(); });
        mount();
        const pid = store.state.player && store.state.player.id;
        if (pid) lmsCommand(pid,['status','-','1','tags:ad']).then(response => {
            if (!current && store.state.player.id === pid) select(pid,response.data.result.playlist_loop && response.data.result.playlist_loop[0]);
        }).catch(() => {});
    }
    window.ListenBrainzLoveMaterial = {love:love,enableButton:enableButton};
})();
