'use strict';

const IN_GAME = typeof GetParentResourceName === 'function';
const RES = IN_GAME ? GetParentResourceName() : 'fks-chat';
const $ = (id) => document.getElementById(id);

const post = (name, data = {}) => {
    if (!IN_GAME) return Promise.resolve();
    return fetch(`https://${RES}/${name}`, { method: 'POST', body: JSON.stringify(data) }).catch(() => {});
};

let L = {};
const t = (key, ...args) => {
    let s = L[key] ?? key;
    args.forEach((a) => { s = s.replace('%s', a); });
    return s;
};

// element with class and text
const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
};
const icon = (id) => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', `#${id}`);
    svg.appendChild(use);
    return svg;
};
const hhmm = (sec) => {
    const d = sec ? new Date(sec * 1000) : new Date();
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
};

/* ================================================================ settings */
const POSITIONS = ['top-left', 'center-left', 'bottom-left', 'top-right'];
const KINDS = ['local', 'ooc', 'me', 'do', 'ad', 'dice', 'announce', 'admin', 'report', 'system'];
const SWATCHES = ['#e8dcc4', '#cfc2a6', '#a39a88', '#f2c14e', '#e2ae3c', '#e0874a', '#d9553f', '#e88aa8', '#c79ad6', '#8fb3c9', '#6fc2b0', '#9cc27a'];

const S = {
    defaults: { position: 'top-left', width: 42, fontSize: 100, opacity: 55, fade: 10, maxMessages: 80, timestamps: false, colors: {} },
    settings: null,
    showIds: true,
    maxLength: 250,
    rp: { subjectMax: 60, infoMax: 600, messageMax: 300 },
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

function applySettings() {
    const s = S.settings;
    const chatEl = $('chat');
    chatEl.classList.remove(...POSITIONS);
    chatEl.classList.add(s.position);
    chatEl.classList.toggle('no-time', !s.timestamps);
    chatEl.style.setProperty('--w', s.width);
    chatEl.style.setProperty('--fs', s.fontSize / 100);
    chatEl.style.setProperty('--bg', s.opacity / 100);
    KINDS.forEach((k) => document.documentElement.style.setProperty(`--c-${k}`, s.colors[k] || '#cfc2a6'));
}

let saveTimer = 0;
function saveSettings() {
    applySettings();
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => post('settings:save', S.settings), 300);
}

/* ================================================================ focus
   Every open thing is tracked; when the last one closes the game gets the mouse/keyboard back. */
const open = { chat: false, settings: false, report: false, reports: false };
const release = () => { if (!Object.values(open).some(Boolean)) post('release'); };

/* ================================================================ chat */
const chat = {
    el: $('chat'), log: $('chat-log'), input: $('ci-text'), box: $('ci-suggest'),
    history: [], hIdx: -1, draft: '',
    base: new Map(), extra: new Map(), shown: [], sel: 0,
};

const nearBottom = () => chat.log.scrollHeight - chat.log.scrollTop - chat.log.clientHeight < 60;
const toBottom = () => { chat.log.scrollTop = chat.log.scrollHeight; };

function openChat() {
    open.chat = true;
    chat.el.classList.add('open');
    $('chat-input').classList.remove('hidden');
    chat.input.value = '';
    chat.hIdx = -1;
    renderSuggest();
    toBottom();
    setTimeout(() => chat.input.focus(), 30);
}

function closeChat(silent) {
    open.chat = false;
    chat.el.classList.remove('open');
    $('chat-input').classList.add('hidden');
    chat.box.classList.add('hidden');
    chat.input.blur();
    toBottom();
    if (!silent) release();
}

function submit() {
    const text = chat.input.value.trim();
    if (text && chat.history[chat.history.length - 1] !== text) {
        chat.history.push(text);
        if (chat.history.length > 50) chat.history.shift();
    }
    closeChat(true); // the game takes the focus back itself
    post('chat:submit', { text });
}

/* messages ------------------------------------------------------- */
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
    if (S.showIds && m.id != null) frag.appendChild(el('span', 'm-id', `[${m.id}]`));
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
    const kind = KINDS.includes(m.kind) ? m.kind : (m.kind === 'external' ? 'external' : 'system');
    const div = el('div', `msg k-${kind}`);
    if (kind !== 'external') div.style.setProperty('--c', `var(--c-${kind})`);
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
    chat.log.appendChild(div);
    while (chat.log.childElementCount > S.settings.maxMessages) chat.log.firstElementChild.remove();
    if (stick) toBottom();
    if (S.settings.fade > 0) setTimeout(() => div.classList.add('old'), S.settings.fade * 1000);
}

/* suggestions ---------------------------------------------------- */
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
        map.set(name, { name, help: s.help || b?.help || '', params: s.params.length ? s.params : (b?.params || []) });
    });
    return [...map.values()];
}

function renderSuggest() {
    const v = chat.input.value;
    chat.shown = [];
    if (!v.startsWith('/')) { chat.box.classList.add('hidden'); return; }
    const words = v.slice(1).split(' ');
    const cmd = words[0].toLowerCase();
    const all = allSuggestions();
    let list;
    if (words.length === 1) {
        list = all.filter((s) => s.name.slice(1).toLowerCase().startsWith(cmd))
            .sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8);
    } else {
        list = all.filter((s) => s.name.slice(1).toLowerCase() === cmd);
    }
    if (!list.length) { chat.box.classList.add('hidden'); return; }

    chat.shown = list;
    chat.sel = Math.min(chat.sel, list.length - 1);
    const arg = words.length - 2;
    chat.box.innerHTML = '';
    list.forEach((s, i) => {
        const row = el('button', `sg${i === chat.sel ? ' on' : ''}`);
        row.dataset.sg = i;
        row.appendChild(el('b', null, s.name));
        s.params.forEach((p, n) => row.appendChild(el('span', `p${n === arg ? ' on' : ''}`, `[${p.name}]`)));
        const help = arg >= 0 && s.params[arg]?.help ? s.params[arg].help : s.help;
        if (help) row.appendChild(el('p', null, help));
        chat.box.appendChild(row);
    });
    chat.box.classList.remove('hidden');
}

function complete(i) {
    const s = chat.shown[i];
    if (!s) return;
    chat.input.value = `${s.name} `;
    chat.sel = 0;
    renderSuggest();
    chat.input.focus();
}

function historyStep(dir) {
    const h = chat.history;
    if (!h.length) return;
    if (chat.hIdx === -1) chat.draft = chat.input.value;
    chat.hIdx = Math.max(-1, Math.min(h.length - 1, chat.hIdx + dir));
    chat.input.value = chat.hIdx === -1 ? chat.draft : h[h.length - 1 - chat.hIdx];
    renderSuggest();
}

chat.input.addEventListener('input', () => { chat.sel = 0; renderSuggest(); });
chat.input.addEventListener('keydown', (ev) => {
    const listing = chat.shown.length > 0 && !chat.input.value.includes(' ');
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

/* ================================================================ settings panel */
function setRange(id, value, label) {
    const input = $(id);
    input.value = value;
    input.style.setProperty('--p', `${((value - input.min) / (input.max - input.min)) * 100}%`);
    $(`${id}-v`).textContent = label;
}

function renderSettings() {
    const s = S.settings;
    document.querySelectorAll('#st-position [data-pos]').forEach((b) => b.classList.toggle('on', b.dataset.pos === s.position));
    setRange('st-width', s.width, s.width);
    setRange('st-font', s.fontSize, `${s.fontSize}%`);
    setRange('st-opacity', s.opacity, `${s.opacity}%`);
    setRange('st-fade', s.fade, s.fade > 0 ? `${s.fade} s` : t('set_fade_never'));
    document.querySelectorAll('#st-time [data-time]').forEach((b) => b.classList.toggle('on', (b.dataset.time === '1') === s.timestamps));

    const box = $('st-colors');
    box.innerHTML = '';
    KINDS.forEach((k) => {
        const row = el('div', 'sc');
        row.style.setProperty('--c', s.colors[k]);
        row.appendChild(el('span', null, t(`ch_${k}`)));
        const sw = el('div', 'sw');
        const swatches = SWATCHES.includes(S.defaults.colors[k]) ? SWATCHES : [S.defaults.colors[k], ...SWATCHES];
        swatches.forEach((c) => {
            const b = el('button', c.toLowerCase() === String(s.colors[k]).toLowerCase() ? 'on' : '');
            b.style.setProperty('--s', c);
            b.dataset.kind = k;
            b.dataset.color = c;
            sw.appendChild(b);
        });
        row.appendChild(sw);
        box.appendChild(row);
    });
}

function openSettings() {
    open.settings = true;
    $('settings').classList.remove('hidden');
    chat.el.classList.add('preview');
    renderSettings();
}

function closeSettings() {
    open.settings = false;
    $('settings').classList.add('hidden');
    chat.el.classList.remove('preview');
    if (open.chat) chat.input.focus(); else release();
}

[['st-width', 'width'], ['st-font', 'fontSize'], ['st-opacity', 'opacity'], ['st-fade', 'fade']].forEach(([id, key]) => {
    $(id).addEventListener('input', (ev) => {
        S.settings[key] = Number(ev.target.value);
        renderSettings();
        saveSettings();
    });
});

/* ================================================================ player report */
const rp = { report: null, cat: 'player', sending: false };

function reportForm() {
    $('rp-title').textContent = t('rp_title');
    $('rp-sub').textContent = t('rp_sub');
    $('rp-sub').classList.remove('hidden');
    $('rp-form').classList.remove('hidden');
    $('rp-thread').classList.add('hidden');
    document.querySelectorAll('#rp-cats [data-cat]').forEach((b) => b.classList.toggle('on', b.dataset.cat === rp.cat));
    updateReportForm();
}

function updateReportForm() {
    const info = $('rp-info').value;
    $('rp-info-count').textContent = `${info.length} / ${S.rp.infoMax}`;
    $('rp-send').disabled = rp.sending || !$('rp-subject').value.trim() || !info.trim();
}

function renderThread(box, messages, mine, youLabel) {
    const keep = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
    const grew = messages.length !== box.childElementCount;
    box.innerHTML = '';
    messages.forEach((m) => {
        const d = el('div', `tm ${m.from}${m.from === mine ? ' right' : ''}`);
        const head = el('div', 'tm-head');
        head.appendChild(el('b', null, m.from === mine && youLabel ? youLabel : (m.name || '')));
        head.appendChild(document.createTextNode(` · ${hhmm(m.time)}`));
        d.append(head, el('div', 'tm-body', m.text));
        box.appendChild(d);
    });
    if (keep || grew) box.scrollTop = box.scrollHeight;
}

function statusChip(node, r) {
    node.className = `status ${r.status}`;
    node.textContent = r.status === 'claimed' ? t('status_claimed', r.adminName || '') : t(`status_${r.status}`);
}

function renderReport() {
    const r = rp.report;
    if (!r) return reportForm();

    $('rp-title').textContent = `${t('rp_title')} #${r.id}`;
    $('rp-sub').classList.add('hidden');
    $('rp-form').classList.add('hidden');
    $('rp-thread').classList.remove('hidden');

    const cat = $('rp-cat');
    cat.innerHTML = '';
    cat.append(icon(CAT_ICON[r.category] || 'i-question'), el('span', null, t(`cat_${r.category}`)));
    $('rp-subject-v').textContent = r.subject;
    statusChip($('rp-status'), r);
    renderThread($('rp-messages'), r.messages || [], 'player', t('you'));

    const closed = r.status === 'closed';
    $('rp-composer').classList.toggle('hidden', closed || !r.canSend);
    $('rp-cancel').classList.toggle('hidden', closed);
    const note = closed ? t('rp_closed') : (r.canSend ? '' : t('rp_wait'));
    $('rp-note').textContent = note;
    $('rp-note').classList.toggle('hidden', !note);
    if (!closed && r.canSend) setTimeout(() => $('rp-msg').focus(), 30);
}

function reportOpen(d) {
    open.report = true;
    rp.report = d.report || null;
    rp.sending = false;
    $('report').classList.remove('hidden');
    renderReport();
    if (!rp.report) setTimeout(() => $('rp-subject').focus(), 50);
}

function reportUpdate(d) {
    const had = rp.report;
    rp.report = d.report || null;
    if (rp.report && !had) { // the report was created: clear the form
        rp.sending = false;
        $('rp-subject').value = '';
        $('rp-info').value = '';
    }
    if (open.report) renderReport();
}

function closeReport() {
    open.report = false;
    $('report').classList.add('hidden');
    release();
}

function sendReport() {
    if ($('rp-send').disabled) return;
    rp.sending = true;
    updateReportForm();
    post('report:create', { category: rp.cat, subject: $('rp-subject').value, info: $('rp-info').value });
    setTimeout(() => { rp.sending = false; if (open.report && !rp.report) updateReportForm(); }, 1500);
}

function sendReportMessage() {
    const input = $('rp-msg');
    const text = input.value.trim();
    if (!text || !rp.report?.canSend) return;
    post('report:message', { text });
    input.value = '';
    rp.report.canSend = false; // until the server answers
    renderReport();
}

$('rp-subject').addEventListener('input', updateReportForm);
$('rp-info').addEventListener('input', updateReportForm);

/* ================================================================ admin reports */
const CAT_ICON = { player: 'i-user', question: 'i-question', bug: 'i-bug' };
const rs = { list: [], me: 0, tab: 'open', sel: null, offset: 0, canBack: false };

const nowServer = () => Date.now() / 1000 + rs.offset;
function ago(sec) {
    const s = Math.max(0, nowServer() - sec);
    if (s < 60) return t('ago_now');
    if (s < 3600) return t('ago_min', Math.floor(s / 60));
    return t('ago_h', Math.floor(s / 3600));
}

const inTab = (r, tab) => (tab === 'open' ? r.status === 'open' : tab === 'mine' ? r.admin === rs.me : true);

function renderReports() {
    ['open', 'mine', 'all'].forEach((tab) => { $(`rs-n-${tab}`).textContent = rs.list.filter((r) => inTab(r, tab)).length; });
    document.querySelectorAll('#rs-tabs [data-tab]').forEach((b) => b.classList.toggle('on', b.dataset.tab === rs.tab));
    $('rs-back').classList.toggle('hidden', !rs.canBack);

    const box = $('rs-list');
    const list = rs.list.filter((r) => inTab(r, rs.tab));
    box.innerHTML = '';
    if (!list.length) box.appendChild(el('div', 'rs-empty', t('rs_empty')));
    list.forEach((r) => {
        const mine = r.admin === rs.me;
        const card = el('button', `rs-item${r.admin ? (mine ? ' claimed' : ' taken') : ''}${r.id === rs.sel ? ' on' : ''}`);
        card.dataset.report = r.id;

        const r1 = el('div', 'r1');
        r1.append(icon(CAT_ICON[r.category] || 'i-question'), el('span', null, `${t(`cat_${r.category}`)} · #${r.id}`), el('span', 'ago', ago(r.created)));
        const r3 = el('div', 'r3');
        const who = el('span', null, `${r.name} [${r.src}]`);
        if (!r.online) who.appendChild(el('span', 'off', ` · ${t('offline')}`));
        const last = r.messages[r.messages.length - 1];
        const st = el('span', 'st', r.admin ? t('status_claimed', r.adminName) : t('status_open'));
        if (mine && last && last.from === 'player') st.appendChild(el('i', 'dot'));
        r3.append(who, st);
        card.append(r1, el('div', 'r2', r.subject), r3);
        box.appendChild(card);
    });
    renderDetail();
}

function actionBtn(act, label, iconId, cls = 'btn ghost small', disabled = false) {
    const b = el('button', cls);
    b.dataset.rsAct = act;
    if (iconId) b.appendChild(icon(iconId));
    b.appendChild(el('span', null, label));
    b.disabled = disabled;
    return b;
}

function renderDetail() {
    const r = rs.list.find((x) => x.id === rs.sel);
    $('rs-pick').classList.toggle('hidden', !!r);
    $('rs-view').classList.toggle('hidden', !r);
    if (!r) return;

    const mine = r.admin === rs.me;
    const kicker = $('rs-kicker');
    kicker.innerHTML = '';
    kicker.append(icon(CAT_ICON[r.category] || 'i-question'), el('span', null, `${t(`cat_${r.category}`)} · #${r.id} · ${ago(r.created)}`));
    $('rs-subject').textContent = r.subject;
    const who = $('rs-who');
    who.innerHTML = '';
    who.append(el('span', null, `${r.name} [${r.src}] `), el('small', null, `· ${r.steam}`));
    if (!r.online) who.appendChild(el('span', 'off', ` · ${t('offline')}`));
    statusChip($('rs-status'), r);

    const actions = $('rs-actions');
    actions.innerHTML = '';
    let note = '';
    if (!r.admin) {
        actions.appendChild(actionBtn('claim', t('act_claim'), 'i-check', 'btn small'));
        note = t('rs_need_claim');
    } else if (mine) {
        actions.append(
            actionBtn('goto', t('act_goto'), 'i-pin', undefined, !r.online),
            actionBtn('bring', t('act_bring'), 'i-hand', undefined, !r.online),
        );
        if (r.canReturn) actions.appendChild(actionBtn('return', t('act_return'), 'i-back', undefined, !r.online));
        actions.append(el('span', 'grow'), actionBtn('release', t('act_release'), 'i-release'), actionBtn('close', t('act_close'), 'i-flag', 'btn small danger'));
    } else {
        note = t('rs_taken', r.adminName);
    }

    renderThread($('rs-messages'), r.messages || [], 'admin');
    $('rs-composer').classList.toggle('hidden', !mine);
    $('rs-note').textContent = note;
    $('rs-note').classList.toggle('hidden', !note);
}

function reportsUpdate(d) {
    rs.list = d.reports || [];
    if (d.me != null) rs.me = d.me;
    if (d.now) rs.offset = d.now - Date.now() / 1000;
    rs.canBack = !!d.canBack;
    if (rs.sel != null && !rs.list.some((r) => r.id === rs.sel)) rs.sel = null;
    if (open.reports) renderReports();
}

function reportsOpen(d) {
    open.reports = true;
    $('reports').classList.remove('hidden');
    reportsUpdate(d);
    renderReports();
}

function closeReports() {
    open.reports = false;
    $('reports').classList.add('hidden');
    post('reports:closed');
    release();
}

function sendAdminMessage() {
    const input = $('rs-msg');
    const text = input.value.trim();
    if (!text || rs.sel == null) return;
    post('reports:action', { id: rs.sel, action: 'message', text });
    input.value = '';
}

// "x min ago" keeps moving
setInterval(() => { if (open.reports) renderReports(); }, 30000);

/* ================================================================ 3D text above the players */
const world = $('world');
const anchors = new Map(); // server id -> { el, bubbles, tag, name }
const BUBBLE_ICON = { dice: 'i-dice', coin: 'i-coin', random: 'i-hash' };
const BUBBLE_COLOR = { me: 'me', do: 'do', dice: 'dice', coin: 'dice', random: 'dice' };

function anchor(sid) {
    let a = anchors.get(sid);
    if (a) return a;
    const root = el('div', 'anchor');
    root.style.display = 'none';
    const bubbles = el('div', 'bubbles');
    const tag = el('div', 'tag hidden');
    const name = el('span', 't-name');
    tag.append(el('span', 't-rank', t('admin_tag')), name);
    root.append(bubbles, tag);
    world.appendChild(root);
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
    const b = el('div', `bb k-${d.kind}`);
    b.style.setProperty('--c', `var(--c-${BUBBLE_COLOR[d.kind] || 'me'})`);
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
    const names = new Map((list || []).map((x) => [x.sid, x.name]));
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
    (list || []).forEach(([sid, x, y, s]) => {
        const a = anchors.get(sid);
        if (!a) return;
        seen.add(sid);
        a.el.style.display = '';
        a.el.style.transform = `translate(${x * W}px, ${y * H}px) translate(-50%, -100%) scale(${s})`;
    });
    anchors.forEach((a, sid) => { if (!seen.has(sid)) a.el.style.display = 'none'; });
}

/* ================================================================ clicks and keys */
document.addEventListener('click', (ev) => {
    const sg = ev.target.closest('[data-sg]');
    if (sg) return complete(Number(sg.dataset.sg));

    const pos = ev.target.closest('[data-pos]');
    if (pos) { S.settings.position = pos.dataset.pos; renderSettings(); return saveSettings(); }
    const time = ev.target.closest('[data-time]');
    if (time) { S.settings.timestamps = time.dataset.time === '1'; renderSettings(); return saveSettings(); }
    const sw = ev.target.closest('[data-color]');
    if (sw) { S.settings.colors[sw.dataset.kind] = sw.dataset.color; renderSettings(); return saveSettings(); }

    const cat = ev.target.closest('[data-cat]');
    if (cat) { rp.cat = cat.dataset.cat; return reportForm(); }

    const tab = ev.target.closest('[data-tab]');
    if (tab) { rs.tab = tab.dataset.tab; return renderReports(); }
    const card = ev.target.closest('[data-report]');
    if (card) { rs.sel = Number(card.dataset.report); renderReports(); return setTimeout(() => $('rs-msg').focus(), 30); }
    const act = ev.target.closest('[data-rs-act]');
    if (act && rs.sel != null) return post('reports:action', { id: rs.sel, action: act.dataset.rsAct });

    const btn = ev.target.closest('[data-act]');
    if (!btn) {
        if (ev.target.classList.contains('overlay')) {
            if (ev.target.id === 'settings') closeSettings();
        }
        return;
    }
    switch (btn.dataset.act) {
        case 'settings': return openSettings();
        case 'settings-close': return closeSettings();
        case 'settings-reset':
            S.settings = mergeSettings({});
            renderSettings();
            return saveSettings();
        case 'report-close': return closeReport();
        case 'report-send': return sendReport();
        case 'report-msg': return sendReportMessage();
        case 'report-cancel': return post('report:cancel');
        case 'reports-close': return closeReports();
        case 'rs-back': return post('reports:action', { action: 'back' });
        case 'rs-msg': return sendAdminMessage();
        default:
    }
});

document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') {
        if (open.settings) return closeSettings();
        if (open.report) return closeReport();
        if (open.reports) return closeReports();
        if (open.chat) return closeChat();
        return;
    }
    if (ev.key === 'Enter' && !ev.shiftKey) {
        if (ev.target.id === 'rp-msg') { ev.preventDefault(); sendReportMessage(); }
        else if (ev.target.id === 'rs-msg') { ev.preventDefault(); sendAdminMessage(); }
        else if (ev.target.id === 'rp-subject') { ev.preventDefault(); $('rp-info').focus(); }
    }
});

/* ================================================================ messages from Lua */
function applyLocale() {
    document.querySelectorAll('[data-l]').forEach((e) => { e.textContent = t(e.dataset.l); });
    chat.input.placeholder = t('chat_placeholder');
    chat.input.maxLength = S.maxLength;
    $('rp-subject').placeholder = t('rp_subject_ph');
    $('rp-subject').maxLength = S.rp.subjectMax;
    $('rp-info').placeholder = t('rp_info_ph');
    $('rp-info').maxLength = S.rp.infoMax;
    $('rp-msg').placeholder = t('rp_msg_ph');
    $('rp-msg').maxLength = S.rp.messageMax;
    $('rs-msg').placeholder = t('rp_msg_ph');
    $('rs-msg').maxLength = S.rp.messageMax;
}

const handlers = {
    init(d) {
        L = d.locale || {};
        if (d.defaults) S.defaults = { ...S.defaults, ...d.defaults, colors: { ...(d.defaults.colors || {}) } };
        S.settings = mergeSettings(d.settings);
        S.showIds = d.showIds !== false;
        S.maxLength = d.maxLength || S.maxLength;
        S.rp = { ...S.rp, ...(d.reports || {}) };
        S.maxBubbles = d.maxBubbles || S.maxBubbles;
        applyLocale();
        applySettings();
    },
    'chat:open': openChat,
    'chat:message': addMessage,
    'chat:clear': () => { chat.log.innerHTML = ''; },
    'chat:hide': (v) => document.body.classList.toggle('paused', v === true),
    'chat:suggestions': (list) => {
        chat.base = new Map();
        (Array.isArray(list) ? list : []).map(normSuggestion).filter(Boolean).forEach((s) => {
            const prev = chat.base.get(s.name);
            if (!prev || (!prev.help && s.help)) chat.base.set(s.name, s);
        });
        if (open.chat) renderSuggest();
    },
    'chat:suggestion': (s) => {
        const n = normSuggestion(s);
        if (n) chat.extra.set(n.name, n);
    },
    'chat:removeSuggestion': (name) => {
        const n = String(name || '');
        const key = n.startsWith('/') ? n : `/${n}`;
        chat.extra.delete(key);
        chat.base.delete(key);
    },
    'settings:open': openSettings,
    'report:open': reportOpen,
    'report:update': reportUpdate,
    'reports:open': reportsOpen,
    'reports:update': reportsUpdate,
    '3d:bubble': addBubble,
    '3d:tags': setTags,
    '3d:pos': positions,
};

window.addEventListener('message', (ev) => {
    const msg = ev.data || {};
    const fn = handlers[msg.action];
    if (!fn) return;
    if (!S.settings && msg.action !== 'init') S.settings = mergeSettings({}); // message before init (should not happen)
    fn(msg.data ?? {});
});

post('ready');
