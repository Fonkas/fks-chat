'use strict';

/* =====================================================================
   fks-chat inside the fks-core NUI (extension: UI.Extend in client/main.lua).
   Message feed, input with command suggestions, chat settings and the 3D text above the players.
   The reports are normal fks-core screens (client/reports.lua). Tokens and fonts come from fks-core.
   ===================================================================== */
FKS.extension(document.currentScript.dataset.owner, (() => {
    let api = null;
    let L = {};
    const t = (key, ...args) => {
        let s = L[key] ?? key;
        args.forEach((a) => { s = s.replace('%s', a); });
        return s;
    };
    const el = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    };
    const icon = (name) => FKS.icon(name, 'fc-ico');
    const hhmm = () => {
        const d = new Date();
        return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    };

    /* ============================================================ settings */
    const POSITIONS = ['top-left', 'center-left', 'bottom-left', 'top-right'];
    const KINDS = ['local', 'ooc', 'me', 'do', 'ad', 'dice', 'announce', 'admin', 'report', 'system'];
    const SWATCHES = ['#e8dcc4', '#cfc2a6', '#a39a88', '#f2c14e', '#e2ae3c', '#e0874a', '#d9553f', '#e88aa8', '#c79ad6', '#8fb3c9', '#6fc2b0', '#9cc27a'];

    const S = {
        defaults: { position: 'top-left', width: 42, fontSize: 100, opacity: 55, fade: 10, maxMessages: 80, timestamps: false, colors: {} },
        settings: null,
        showIds: true,
        maxLength: 250,
        maxBubbles: 3,
    };

    const clampNum = (v, min, max, def) => {
        const n = Number(v);
        return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def;
    };

    function mergeSettings(saved) {
        const d = S.defaults;
        const s = saved && typeof saved === 'object' ? saved : {};
        return {
            position: POSITIONS.includes(s.position) ? s.position : d.position,
            width: clampNum(s.width, 30, 70, d.width),
            fontSize: clampNum(s.fontSize, 80, 140, d.fontSize),
            opacity: clampNum(s.opacity, 0, 100, d.opacity),
            fade: clampNum(s.fade, 0, 60, d.fade),
            maxMessages: d.maxMessages,
            timestamps: typeof s.timestamps === 'boolean' ? s.timestamps : d.timestamps,
            colors: { ...d.colors, ...(s.colors || {}) },
        };
    }

    let D = {};   // elements

    function applySettings() {
        const s = S.settings;
        D.chat.classList.remove(...POSITIONS);
        D.chat.classList.add(s.position);
        D.chat.classList.toggle('no-time', !s.timestamps);
        D.chat.style.setProperty('--w', s.width);
        D.chat.style.setProperty('--fs', s.fontSize / 100);
        D.chat.style.setProperty('--bg', s.opacity / 100);
        KINDS.forEach((k) => api.root.style.setProperty(`--fc-${k}`, s.colors[k] || '#cfc2a6'));
    }

    let saveTimer = 0;
    function saveSettings() {
        applySettings();
        clearTimeout(saveTimer);
        saveTimer = setTimeout(() => api.call('settings:save', S.settings), 300);
    }

    /* ============================================================ focus: given back when the last thing closes */
    const open = { chat: false, settings: false };
    const release = () => { if (!open.chat && !open.settings) api.call('release'); };

    /* ============================================================ chat */
    const chat = { history: [], hIdx: -1, draft: '', base: new Map(), extra: new Map(), shown: [], sel: 0 };

    const nearBottom = () => D.log.scrollHeight - D.log.scrollTop - D.log.clientHeight < 60;
    const toBottom = () => { D.log.scrollTop = D.log.scrollHeight; };

    function openChat() {
        open.chat = true;
        D.chat.classList.add('open');
        D.input.classList.remove('hidden');
        D.text.value = '';
        chat.hIdx = -1;
        renderSuggest();
        toBottom();
        setTimeout(() => D.text.focus(), 30);
    }

    function closeChat(silent) {
        open.chat = false;
        D.chat.classList.remove('open');
        D.input.classList.add('hidden');
        D.suggest.classList.add('hidden');
        D.text.blur();
        toBottom();
        if (!silent) release();
    }

    function submit() {
        const text = D.text.value.trim();
        if (text && chat.history[chat.history.length - 1] !== text) {
            chat.history.push(text);
            if (chat.history.length > 50) chat.history.shift();
        }
        closeChat(true);   // the Lua side gives the focus back before running the command
        api.call('submit', { text });
    }

    /* messages ---------------------------------------------------- */
    const CODES = { 0: '#e8dcc4', 1: '#d9553f', 2: '#9cc27a', 3: '#f2c14e', 4: '#6f9bd1', 5: '#8fb3c9', 6: '#c79ad6', 7: '#e8dcc4', 8: '#a33a2a', 9: '#e88aa8' };

    // text with ^0-^9 colour codes (messages of other scripts)
    function coloured(parent, text) {
        let target = parent;
        String(text ?? '').split(/\^(\d)/).forEach((part, i) => {
            if (i % 2 === 1) {
                target = el('span');
                target.style.color = CODES[part];
                parent.appendChild(target);
            } else if (part) {
                target.appendChild(document.createTextNode(part));
            }
        });
        return parent;
    }
    const plain = (s) => String(s ?? '').replace(/\^\d/g, '');

    function authorEl(m) {
        const frag = document.createDocumentFragment();
        frag.appendChild(el('span', 'm-author', m.author || ''));
        if (S.showIds && m.id !== undefined && m.id !== null) frag.appendChild(el('span', 'm-id', `[${m.id}]`));
        return frag;
    }

    function buildExternal(div, m) {
        if (Array.isArray(m.color) && m.color.length >= 3) div.style.setProperty('--c', `rgb(${m.color.slice(0, 3).map(Number).join(',')})`);
        const args = Array.isArray(m.args) ? m.args.map((a) => String(a ?? '')) : [];
        if (m.template && typeof m.template === 'string') {
            // templates of the default chat are HTML: only the text is kept
            const text = m.template.replace(/\{(\d+)\}/g, (_, i) => args[Number(i)] ?? '').replace(/<[^>]*>/g, '');
            div.appendChild(coloured(el('span', 'm-text'), text));
        } else if (args.length > 1 && args[0] !== '') {
            div.appendChild(coloured(el('span', 'm-author'), args[0]));
            div.appendChild(document.createTextNode(': '));
            div.appendChild(coloured(el('span', 'm-text'), args.slice(1).join(' ')));
        } else {
            div.appendChild(coloured(el('span', 'm-text'), args.filter(Boolean).join(' ')));
        }
    }

    function addMessage(m) {
        if (!m || typeof m !== 'object') return;
        const kind = KINDS.includes(m.kind) ? m.kind : (m.kind === 'external' ? 'external' : 'system');
        const div = el('div', `fc-msg k-${kind}`);
        if (kind !== 'external') div.style.setProperty('--c', `var(--fc-${kind})`);
        div.appendChild(el('span', 'm-time', hhmm()));

        if (kind === 'external') {
            buildExternal(div, m);
        } else {
            if (kind !== 'me' && kind !== 'do') div.appendChild(el('span', 'm-tag', t(`ch_${kind}`)));
            const text = plain(m.text);
            if (kind === 'me') {
                const body = el('span', 'm-text', '* ');
                body.appendChild(authorEl(m));
                body.appendChild(document.createTextNode(` ${text}`));
                div.appendChild(body);
            } else if (kind === 'do') {
                div.appendChild(el('span', 'm-text', `* ${text} `));
                div.appendChild(el('span', 'm-who', `(${m.author || ''})`));
            } else if (kind === 'dice') {
                div.appendChild(authorEl(m));
                div.appendChild(el('span', 'm-text', ` ${text}`));
            } else if (m.author) {
                div.appendChild(authorEl(m));
                div.appendChild(document.createTextNode(': '));
                div.appendChild(el('span', 'm-text', text));
            } else {
                div.appendChild(coloured(el('span', 'm-text'), m.text));
            }
        }

        const stick = !open.chat || nearBottom();
        D.log.appendChild(div);
        while (D.log.childElementCount > S.settings.maxMessages) D.log.firstElementChild.remove();
        if (stick) toBottom();
        if (S.settings.fade > 0) setTimeout(() => div.classList.add('old'), S.settings.fade * 1000);
    }

    /* suggestions ------------------------------------------------- */
    function normSuggestion(s) {
        if (!s || !s.name) return null;
        const name = s.name.startsWith('/') ? s.name : `/${s.name}`;
        const params = Array.isArray(s.params) ? s.params.filter((p) => p && p.name) : [];
        return { name, help: s.help || '', params };
    }

    function allSuggestions() {
        const map = new Map(chat.base);
        chat.extra.forEach((s, name) => {
            const b = map.get(name);
            map.set(name, { name, help: s.help || (b && b.help) || '', params: s.params.length ? s.params : ((b && b.params) || []) });
        });
        return [...map.values()];
    }

    function renderSuggest() {
        const v = D.text.value;
        chat.shown = [];
        if (!v.startsWith('/')) { D.suggest.classList.add('hidden'); return; }
        const words = v.slice(1).split(' ');
        const cmd = words[0].toLowerCase();
        const all = allSuggestions();
        const list = words.length === 1
            ? all.filter((s) => s.name.slice(1).toLowerCase().startsWith(cmd)).sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8)
            : all.filter((s) => s.name.slice(1).toLowerCase() === cmd);
        if (!list.length) { D.suggest.classList.add('hidden'); return; }

        chat.shown = list;
        chat.sel = Math.min(chat.sel, list.length - 1);
        const arg = words.length - 2;
        D.suggest.innerHTML = '';
        list.forEach((s, i) => {
            const row = el('button', `fc-sg${i === chat.sel ? ' on' : ''}`);
            row.addEventListener('click', () => complete(i));
            row.appendChild(el('b', null, s.name));
            s.params.forEach((p, n) => row.appendChild(el('span', `p${n === arg ? ' on' : ''}`, `[${p.name}]`)));
            const help = arg >= 0 && s.params[arg] && s.params[arg].help ? s.params[arg].help : s.help;
            if (help) row.appendChild(el('p', null, help));
            D.suggest.appendChild(row);
        });
        D.suggest.classList.remove('hidden');
    }

    function complete(i) {
        const s = chat.shown[i];
        if (!s) return;
        D.text.value = `${s.name} `;
        chat.sel = 0;
        renderSuggest();
        D.text.focus();
    }

    function historyStep(dir) {
        const h = chat.history;
        if (!h.length) return;
        if (chat.hIdx === -1) chat.draft = D.text.value;
        chat.hIdx = Math.max(-1, Math.min(h.length - 1, chat.hIdx + dir));
        D.text.value = chat.hIdx === -1 ? chat.draft : h[h.length - 1 - chat.hIdx];
        renderSuggest();
    }

    /* ============================================================ settings panel */
    function setRange(input, out, value, label) {
        input.value = value;
        input.style.setProperty('--p', `${((value - input.min) / (input.max - input.min)) * 100}%`);
        out.textContent = label;
    }

    function renderSettings() {
        const s = S.settings;
        D.stPos.querySelectorAll('[data-pos]').forEach((b) => b.classList.toggle('on', b.dataset.pos === s.position));
        setRange(D.st.width.input, D.st.width.out, s.width, s.width);
        setRange(D.st.font.input, D.st.font.out, s.fontSize, `${s.fontSize}%`);
        setRange(D.st.opacity.input, D.st.opacity.out, s.opacity, `${s.opacity}%`);
        setRange(D.st.fade.input, D.st.fade.out, s.fade, s.fade > 0 ? `${s.fade} s` : t('set_fade_never'));
        D.stTime.querySelectorAll('[data-time]').forEach((b) => b.classList.toggle('on', (b.dataset.time === '1') === s.timestamps));

        D.stColors.innerHTML = '';
        KINDS.forEach((k) => {
            const row = el('div', 'fc-sc');
            row.style.setProperty('--c', s.colors[k]);
            row.appendChild(el('span', null, t(`ch_${k}`)));
            const sw = el('div', 'sw');
            const swatches = SWATCHES.includes(S.defaults.colors[k]) ? SWATCHES : [S.defaults.colors[k], ...SWATCHES];
            swatches.filter(Boolean).forEach((c) => {
                const b = el('button', c.toLowerCase() === String(s.colors[k]).toLowerCase() ? 'on' : '');
                b.style.setProperty('--s', c);
                b.addEventListener('click', () => { S.settings.colors[k] = c; renderSettings(); saveSettings(); });
                sw.appendChild(b);
            });
            row.appendChild(sw);
            D.stColors.appendChild(row);
        });
    }

    function openSettings() {
        open.settings = true;
        D.settings.classList.remove('hidden');
        D.chat.classList.add('preview');
        renderSettings();
    }

    function closeSettings() {
        open.settings = false;
        D.settings.classList.add('hidden');
        D.chat.classList.remove('preview');
        if (open.chat) D.text.focus(); else release();
    }

    /* ============================================================ 3D text above the players */
    const anchors = new Map();   // server id -> { el, bubbles, tag, name }
    const BUBBLE_ICON = { dice: 'dice', coin: 'flip', random: 'hash' };
    const BUBBLE_COLOR = { me: 'me', do: 'do', dice: 'dice', coin: 'dice', random: 'dice' };

    function anchor(sid) {
        let a = anchors.get(sid);
        if (a) return a;
        const root = el('div', 'fc-anchor');
        root.style.display = 'none';
        const bubbles = el('div', 'bubbles');
        const tag = el('div', 'fc-tag hidden');
        const name = el('span', 't-name');
        tag.append(el('span', 't-rank', t('admin_tag')), name);
        root.append(bubbles, tag);
        D.world.appendChild(root);
        a = { el: root, bubbles, tag, name };
        anchors.set(sid, a);
        return a;
    }

    function cleanupAnchor(sid) {
        const a = anchors.get(sid);
        if (a && !a.bubbles.childElementCount && a.tag.classList.contains('hidden')) {
            a.el.remove();
            anchors.delete(sid);
        }
    }

    function addBubble(d) {
        const a = anchor(d.sid);
        const b = el('div', `fc-bb k-${d.kind}`);
        b.style.setProperty('--c', `var(--fc-${BUBBLE_COLOR[d.kind] || 'me'})`);
        if (BUBBLE_ICON[d.kind]) {
            b.classList.add('has-icon');
            b.appendChild(icon(BUBBLE_ICON[d.kind]));
        }
        b.appendChild(el('span', null, plain(d.text)));
        a.bubbles.appendChild(b);
        while (a.bubbles.childElementCount > S.maxBubbles) a.bubbles.firstElementChild.remove();
        setTimeout(() => {
            b.classList.add('out');
            setTimeout(() => { b.remove(); cleanupAnchor(d.sid); }, 400);
        }, Math.max(1000, (d.duration || 7000) - 400));
    }

    function setTags(list) {
        const names = new Map((Array.isArray(list) ? list : []).map((x) => [x.sid, x.name]));
        anchors.forEach((a, sid) => {
            if (!names.has(sid)) {
                a.tag.classList.add('hidden');
                cleanupAnchor(sid);
            }
        });
        names.forEach((name, sid) => {
            const a = anchor(sid);
            a.name.textContent = name;
            a.tag.classList.remove('hidden');
        });
    }

    function positions(list) {
        const W = window.innerWidth, H = window.innerHeight;
        const seen = new Set();
        (Array.isArray(list) ? list : []).forEach(([sid, x, y, s]) => {
            const a = anchors.get(sid);
            if (!a) return;
            seen.add(sid);
            a.el.style.display = '';
            a.el.style.transform = `translate(${x * W}px, ${y * H}px) translate(-50%, -100%) scale(${s})`;
        });
        anchors.forEach((a, sid) => { if (!seen.has(sid)) a.el.style.display = 'none'; });
    }

    /* ============================================================ building the DOM */
    function seg(cls, items) {
        const box = el('div', `fc-seg ${cls || ''}`);
        items.forEach(([key, value, label]) => {
            const b = el('button', '', label);
            b.dataset[key] = value;
            box.appendChild(b);
        });
        return box;
    }

    function slider(labelKey, min, max, step) {
        const wrap = el('label', 'fc-slider');
        wrap.appendChild(el('span', 'fc-label', t(labelKey)));
        const input = el('input');
        input.type = 'range';
        input.min = min;
        input.max = max;
        input.step = step;
        const out = el('em');
        wrap.append(input, out);
        return { wrap, input, out };
    }

    function build() {
        const root = api.root;
        root.innerHTML = '';
        anchors.clear();

        D.world = el('div', 'fc-world');
        root.appendChild(D.world);

        D.chat = el('div', 'fc-chat top-left');
        D.log = el('div', 'fc-log');
        D.input = el('div', 'fc-input hidden');
        const bar = el('div', 'fc-bar');
        bar.appendChild(icon('quill'));
        D.text = el('input');
        D.text.type = 'text';
        D.text.autocomplete = 'off';
        D.text.spellcheck = false;
        D.text.placeholder = t('chat_placeholder');
        D.text.maxLength = S.maxLength;
        const gear = el('button', 'fc-gear');
        gear.appendChild(icon('gear'));
        gear.addEventListener('click', openSettings);
        bar.append(D.text, gear);
        D.suggest = el('div', 'fc-suggest hidden');
        D.input.append(bar, D.suggest);
        D.chat.append(D.log, D.input);
        root.appendChild(D.chat);

        // settings card
        D.settings = el('div', 'fc-overlay hidden');
        D.settings.addEventListener('click', (e) => { if (e.target === D.settings) closeSettings(); });
        const card = el('section', 'fc-card');
        const x = el('button', 'back danger fc-x');
        x.appendChild(FKS.icon('x', ''));
        x.addEventListener('click', closeSettings);
        const head = el('header', 'fc-head');
        const eyebrow = el('div', 'eyebrow', `FKS · ${t('set_eyebrow')}`);
        head.append(eyebrow, el('h1', '', t('set_title')));
        const field = (labelKey, node, cls) => {
            const f = el('div', `fc-field ${cls || ''}`);
            f.append(el('span', 'fc-label', t(labelKey)), node);
            return f;
        };
        D.stPos = seg('', POSITIONS.map((p) => ['pos', p, t(`pos_${p.replace('-', '_')}`)]));
        D.stPos.addEventListener('click', (e) => {
            const b = e.target.closest('[data-pos]');
            if (b) { S.settings.position = b.dataset.pos; renderSettings(); saveSettings(); }
        });
        D.st = {
            width: slider('set_width', 30, 70, 1), font: slider('set_font', 80, 140, 5),
            opacity: slider('set_opacity', 0, 100, 5), fade: slider('set_fade', 0, 60, 5),
        };
        const sliders = el('div', 'fc-sliders');
        [['width', 'width'], ['font', 'fontSize'], ['opacity', 'opacity'], ['fade', 'fade']].forEach(([id, key]) => {
            sliders.appendChild(D.st[id].wrap);
            D.st[id].input.addEventListener('input', (e) => { S.settings[key] = Number(e.target.value); renderSettings(); saveSettings(); });
        });
        D.stTime = seg('small', [['time', '1', t('yes')], ['time', '0', t('no')]]);
        D.stTime.addEventListener('click', (e) => {
            const b = e.target.closest('[data-time]');
            if (b) { S.settings.timestamps = b.dataset.time === '1'; renderSettings(); saveSettings(); }
        });
        D.stColors = el('div', 'fc-colors');
        const actions = el('div', 'fc-actions');
        const reset = el('button', 'btn ghost', t('set_reset'));
        reset.addEventListener('click', () => { S.settings = mergeSettings({}); renderSettings(); saveSettings(); });
        const done = el('button', 'btn', t('set_done'));
        done.addEventListener('click', closeSettings);
        actions.append(reset, done);
        card.append(x, head, field('set_position', D.stPos), sliders, field('set_timestamps', D.stTime, 'row'), field('set_colors', D.stColors), actions);
        D.settings.appendChild(card);
        root.appendChild(D.settings);

        // keys
        D.text.addEventListener('input', () => { chat.sel = 0; renderSuggest(); });
        D.text.addEventListener('keydown', (ev) => {
            const listing = chat.shown.length > 0 && !D.text.value.includes(' ');
            if (ev.key === 'Enter') { ev.preventDefault(); submit(); }
            else if (ev.key === 'Tab') { ev.preventDefault(); if (listing) complete(chat.sel); }
            else if (ev.key === 'ArrowUp') {
                ev.preventDefault();
                if (listing && chat.shown.length > 1) { chat.sel = (chat.sel - 1 + chat.shown.length) % chat.shown.length; renderSuggest(); } else historyStep(1);
            } else if (ev.key === 'ArrowDown') {
                ev.preventDefault();
                if (listing && chat.shown.length > 1) { chat.sel = (chat.sel + 1) % chat.shown.length; renderSuggest(); } else historyStep(-1);
            }
        });
    }

    function onKey(ev) {
        if (ev.key !== 'Escape') return;
        if (open.settings) { ev.preventDefault(); closeSettings(); }
        else if (open.chat) { ev.preventDefault(); closeChat(); }
    }

    return {
        mount(a) {
            api = a;
            S.settings = mergeSettings({});
            build();
            applySettings();
            document.addEventListener('keydown', onKey);
        },
        unmount() {
            document.removeEventListener('keydown', onKey);
        },
        messages: {
            init(d) {
                L = d.locale || {};
                if (d.defaults) S.defaults = { ...S.defaults, ...d.defaults, colors: { ...(d.defaults.colors || {}) } };
                S.settings = mergeSettings(d.settings);
                S.showIds = d.showIds !== false;
                S.maxLength = d.maxLength || S.maxLength;
                S.maxBubbles = d.maxBubbles || S.maxBubbles;
                const log = [...D.log.children];
                build();               // texts in the right language
                log.forEach((n) => D.log.appendChild(n));
                applySettings();
            },
            'chat:open': openChat,
            'chat:close': () => { if (open.chat) closeChat(true); },
            'chat:message': addMessage,
            'chat:clear': () => { D.log.innerHTML = ''; },
            'chat:hide': (d) => api.root.classList.toggle('paused', !!(d && d.on)),
            'chat:suggestions': (d) => {
                chat.base = new Map();
                (Array.isArray(d.list) ? d.list : []).map(normSuggestion).filter(Boolean).forEach((s) => {
                    const prev = chat.base.get(s.name);
                    if (!prev || (!prev.help && s.help)) chat.base.set(s.name, s);
                });
                if (open.chat) renderSuggest();
            },
            'chat:suggestion': (s) => {
                const n = normSuggestion(s);
                if (n) chat.extra.set(n.name, n);
            },
            'chat:removeSuggestion': (d) => {
                const n = String((d && d.name) || '');
                const key = n.startsWith('/') ? n : `/${n}`;
                chat.extra.delete(key);
                chat.base.delete(key);
            },
            'settings:open': openSettings,
            '3d:bubble': addBubble,
            '3d:tags': (d) => setTags(d.list),
            '3d:pos': (d) => positions(d.list),
        },
    };
})());
