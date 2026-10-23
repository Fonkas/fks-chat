---------------------------------------------------------------------------
-- Reports: player form / conversation (/report) and admin panel (/reports), drawn as fks-core screens.
-- The server validates everything (permissions, who took the report, whose turn it is to write).
---------------------------------------------------------------------------
local function T(key, ...)
    local s = LocaleUI[key] or key
    if select('#', ...) > 0 then
        local ok, res = pcall(string.format, s, ...)
        if ok then return res end
    end
    return s
end

local CAT_ICON = { player = 'user', question = 'question', bug = 'bug' }
local CATS = { 'player', 'question', 'bug' }
local panel = nil   -- 'report' | 'reports' (which screen of this script fks-core is showing)

local function statusText(r)
    if r.status == 'claimed' then return T('status_claimed', r.adminName or '') end
    return T('status_' .. tostring(r.status))
end

local function statusTone(r)
    return r.status == 'open' and 'gold' or (r.status == 'closed' and 'bad' or nil)
end

-- messages of a report; `mine` = 'player' | 'admin' (shown on the right)
local function threadItems(messages, mine, you)
    local items = {}
    for _, m in ipairs(messages or {}) do
        items[#items + 1] = {
            name = (m.from == mine and you) or m.name or '', text = m.text, time = m.time,
            right = m.from == mine, tone = m.from == 'admin' and 'gold' or nil,
        }
    end
    return items
end

UI.On('close', function()
    if panel == 'reports' then TriggerServerEvent('fks-chat:server:reports:closed') end
    panel = nil
end)

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
local rp = { report = nil }

local function ReportView()
    local r = rp.report
    local head = { eyebrow = 'FKS · ' .. T('rp_eyebrow') }
    if not r then
        local options = {}
        for _, c in ipairs(CATS) do options[#options + 1] = { value = c, label = T('cat_' .. c), icon = CAT_ICON[c] } end
        head.title, head.subtitle = T('rp_title'), T('rp_sub')
        head.body = {
            { type = 'segmented', style = 'switch', name = 'category', label = T('rp_category'), value = 'player', options = options },
            { type = 'input', name = 'subject', label = T('rp_subject'), placeholder = T('rp_subject_ph'), max = Config.Reports.subjectMax },
            { type = 'textarea', name = 'info', label = T('rp_info'), placeholder = T('rp_info_ph'), max = Config.Reports.infoMax },
            { type = 'row', align = 'center', children = { { type = 'button', label = T('rp_submit'), icon = 'quill', action = 'rpCreate' } } },
        }
        return head
    end

    local closed = r.status == 'closed'
    local body = {
        { type = 'badges', items = { { text = T('cat_' .. tostring(r.category)) }, { text = statusText(r), tone = statusTone(r) } } },
        { type = 'text', style = 'sub', text = r.subject },
        { type = 'thread', items = threadItems(r.messages, 'player', T('you')) },
    }
    if not closed and r.canSend then
        body[#body + 1] = { type = 'composer', name = 'msg', placeholder = T('rp_msg_ph'), max = Config.Reports.messageMax, action = 'rpMessage' }
    else
        body[#body + 1] = { type = 'text', style = 'note', text = closed and T('rp_closed') or T('rp_wait') }
    end
    if not closed then
        body[#body + 1] = { type = 'row', align = 'center', children = { {
            type = 'button', label = T('rp_cancel'), style = 'ghost', action = 'rpCancel',
            confirm = { title = T('rp_cancel'), text = r.subject, danger = true, ok = T('rp_cancel'), cancel = T('close') },
        } } }
    end
    head.title, head.body = ('%s #%s'):format(T('rp_title'), r.id), body
    return head
end

RegisterNetEvent('fks-chat:client:report:open', function(report)
    rp.report = report
    if UI.Open(ReportView()) then panel = 'report' end
end)

RegisterNetEvent('fks-chat:client:report:update', function(report)
    rp.report = report
    if panel == 'report' then UI.Update(ReportView()) end
end)

UI.On('rpCreate', function(d)
    local v = d.values or {}
    local subject = type(v.subject) == 'string' and v.subject:gsub('^%s+', ''):gsub('%s+$', '') or ''
    local info = type(v.info) == 'string' and v.info:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if subject == '' then return { errors = { subject = T('rp_subject_ph') } } end
    if info == '' then return { errors = { info = T('rp_info_ph') } } end
    TriggerServerEvent('fks-chat:server:report:create', { category = v.category or 'player', subject = subject, info = info })
end)

UI.On('rpMessage', function(d)
    if type(d.value) == 'string' and d.value ~= '' then TriggerServerEvent('fks-chat:server:report:message', d.value) end
end)

UI.On('rpCancel', function()
    TriggerServerEvent('fks-chat:server:report:cancel')
end)

---------------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------------
local rs = { list = {}, me = 0, sel = nil, now = 0, at = 0, canBack = false }

local function serverNow() return rs.now + (GetGameTimer() - rs.at) / 1000 end

local function ago(sec)
    local s = math.max(0, serverNow() - (tonumber(sec) or 0))
    if s < 60 then return T('ago_now') end
    if s < 3600 then return T('ago_min', math.floor(s / 60)) end
    return T('ago_h', math.floor(s / 3600))
end

local function inTab(r, tab)
    if tab == 'open' then return r.status == 'open' end
    if tab == 'mine' then return r.admin == rs.me end
    return true
end

local function find(id)
    for _, r in ipairs(rs.list) do if r.id == id then return r end end
end

local function listPage(tab)
    local items = {}
    for _, r in ipairs(rs.list) do
        if inTab(r, tab) then
            local mine = r.admin == rs.me
            local last = r.messages and r.messages[#r.messages]
            local who = ('%s [%s]'):format(r.name, r.src) .. (r.online and '' or (' · ' .. T('offline')))
            items[#items + 1] = {
                value = r.id, icon = CAT_ICON[r.category] or 'question', action = 'rsSelect',
                title = r.subject, tag = ('#%s · %s'):format(r.id, ago(r.created)),
                sub = ('%s · %s'):format(who, r.admin and T('status_claimed', r.adminName or '') or T('status_open')),
                flag = (mine and last and last.from == 'player') and { text = '●', tone = 'bad' } or nil,
            }
        end
    end
    local body = #items > 0 and { { type = 'list', expand = 'none', items = items } } or { { type = 'empty', text = T('rs_empty') } }
    return { body = body }
end

local function action(id, labelKey, iconName, opts)
    opts = opts or {}
    return { type = 'button', small = true, style = opts.style or 'ghost', label = T(labelKey), icon = iconName,
             action = 'rsAction', value = id, disabled = opts.disabled, confirm = opts.confirm }
end

local function detailPage()
    local r = rs.sel and find(rs.sel)
    if not r then return nil end
    local mine = r.admin == rs.me
    local buttons, note = {}, nil
    if not r.admin then
        buttons[#buttons + 1] = action('claim', 'act_claim', 'check', { style = 'primary' })
        note = T('rs_need_claim')
    elseif mine then
        buttons[#buttons + 1] = action('goto', 'act_goto', 'pin', { disabled = not r.online })
        buttons[#buttons + 1] = action('bring', 'act_bring', 'hand', { disabled = not r.online })
        if r.canReturn then buttons[#buttons + 1] = action('return', 'act_return', 'back', { disabled = not r.online }) end
        buttons[#buttons + 1] = action('release', 'act_release', 'release')
        buttons[#buttons + 1] = action('close', 'act_close', 'flag', {
            style = 'danger', confirm = { title = T('act_close'), text = r.subject, danger = true, ok = T('act_close'), cancel = T('close') } })
    else
        note = T('rs_taken', r.adminName or '')
    end

    local body = {
        { type = 'badges', items = { { text = ('%s · #%s · %s'):format(T('cat_' .. tostring(r.category)), r.id, ago(r.created)) }, { text = statusText(r), tone = statusTone(r) } } },
        { type = 'text', style = 'plain', text = '**' .. (tostring(r.subject):gsub('%*', '')) .. '**' },
        { type = 'kv', items = {
            { label = T('cat_player'), value = ('%s [%s]'):format(r.name, r.src) .. (r.online and '' or (' · ' .. T('offline'))), tone = not r.online and 'bad' or nil },
            { label = 'Steam', value = r.steam },
        } },
        { type = 'row', children = buttons },
        { type = 'thread', items = threadItems(r.messages, 'admin') },
    }
    if mine then
        body[#body + 1] = { type = 'composer', name = 'rsMsg', placeholder = T('rp_msg_ph'), max = Config.Reports.messageMax, action = 'rsMessage' }
    elseif note then
        body[#body + 1] = { type = 'text', style = 'note', text = note }
    end
    return { title = '#' .. r.id, tabs = {}, body = body }
end

local function ReportsView()
    local counts = { open = 0, mine = 0, all = 0 }
    for _, r in ipairs(rs.list) do
        for tab in pairs(counts) do if inTab(r, tab) then counts[tab] = counts[tab] + 1 end end
    end
    local tabs = {}
    for _, tab in ipairs({ 'open', 'mine', 'all' }) do
        tabs[#tabs + 1] = { page = tab, label = ('%s (%d)'):format(T('tab_' .. tab), counts[tab]) }
    end
    local footer = rs.canBack and { buttons = { { type = 'button', small = true, style = 'ghost', icon = 'back', label = T('act_back'), action = 'rsBack' } } } or nil
    return {
        eyebrow = 'FKS · ' .. T('rs_eyebrow'), title = T('rs_title'), page = 'open', tabs = tabs, footer = footer,
        pages = { open = listPage('open'), mine = listPage('mine'), all = listPage('all'), detail = detailPage() },
    }
end

local function setData(data)
    data = type(data) == 'table' and data or {}
    rs.list = data.reports or {}
    if data.me then rs.me = data.me end
    if data.now then rs.now, rs.at = data.now, GetGameTimer() end
    rs.canBack = data.canBack == true
    if rs.sel and not find(rs.sel) then rs.sel = nil end
end

RegisterNetEvent('fks-chat:client:reports:open', function(data)
    setData(data)
    rs.sel = nil
    if UI.Open(ReportsView()) then panel = 'reports' end
end)

RegisterNetEvent('fks-chat:client:reports:update', function(data)
    setData(data)
    if panel == 'reports' then UI.Update(ReportsView()) end
end)

UI.On('rsSelect', function(d)
    rs.sel = tonumber(d.value)
    return { view = ReportsView(), go = 'detail' }
end)

UI.On('page', function(d)
    if panel == 'reports' and d.to ~= 'detail' then rs.sel = nil end
end)

UI.On('rsAction', function(d)
    if rs.sel then TriggerServerEvent('fks-chat:server:reports:action', rs.sel, d.value) end
end)

UI.On('rsMessage', function(d)
    if rs.sel and type(d.value) == 'string' and d.value ~= '' then
        TriggerServerEvent('fks-chat:server:reports:action', rs.sel, 'message', d.value)
    end
end)

UI.On('rsBack', function()
    TriggerServerEvent('fks-chat:server:reports:action', nil, 'back')
end)

-- "x min ago" keeps moving
CreateThread(function()
    while true do
        Wait(30000)
        if panel == 'reports' then UI.Update(ReportsView()) end
    end
end)

---------------------------------------------------------------------------
-- Teleport (go to / bring / return) - only the server triggers it
---------------------------------------------------------------------------
RegisterNetEvent('fks-chat:client:teleport', function(c)
    if not c then return end
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    Wait(300)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end
    DoScreenFadeIn(300)
end)
