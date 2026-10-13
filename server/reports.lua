---------------------------------------------------------------------------
-- Reports
--   /report  (player) form to send a report, or the conversation of the open one
--   /reports (admin)  panel with the open reports: take it, go to / bring the player, answer, close
-- A player can only write again after an admin answered; admins can always write.
-- Only the admin that took a report can act on it. Reports live in memory (gone after a restart).
---------------------------------------------------------------------------
local cfg = Config.Reports
local CATEGORIES = { player = true, question = true, bug = true }

local reports, nextId = {}, 1
local activeOf = {}     -- [player src] = id of their open report
local lastReport = {}   -- [player src] = os.time() of their last report
local watching = {}     -- [admin src] = true while the panel is open
local backPos = {}      -- [admin src] = position before "go to"

---------------------------------------------------------------------------
-- Views sent to the page
---------------------------------------------------------------------------
local function AdminView(r)
    return {
        id = r.id, src = r.src, name = r.name, steam = r.steam, category = r.category, subject = r.subject,
        created = r.created, status = r.status, admin = r.admin, adminName = r.adminName, online = r.online,
        messages = r.messages, canReturn = r.returnPos ~= nil,
    }
end

local function PlayerView(r)
    if not r then return nil end
    local last = r.messages[#r.messages]
    return {
        id = r.id, category = r.category, subject = r.subject, status = r.status, adminName = r.adminName,
        messages = r.messages, canSend = r.status ~= 'closed' and last ~= nil and last.from == 'admin',
    }
end

local function List()
    local out = {}
    for _, r in pairs(reports) do out[#out + 1] = AdminView(r) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function PanelData(admin)
    return { reports = List(), now = os.time(), me = admin, canBack = backPos[admin] ~= nil }
end

local function PushAdmins()
    for admin in pairs(watching) do
        if GetPlayerName(admin) then
            TriggerClientEvent('fks-chat:client:reports:update', admin, PanelData(admin))
        else
            watching[admin] = nil
        end
    end
end

local function PushPlayer(r)
    if r.online then TriggerClientEvent('fks-chat:client:report:update', r.src, PlayerView(r), os.time()) end
end

local function Changed(r)
    PushAdmins()
    PushPlayer(r)
end

-- the admin that has the report, or every admin when nobody took it
local function NotifyHandlers(r, ...)
    if r.admin then return Notify(r.admin, ...) end
    for _, a in ipairs(OnlineAdmins()) do Notify(a, ...) end
end

local function Close(r)
    r.status = 'closed'
    reports[r.id] = nil
    if activeOf[r.src] == r.id then activeOf[r.src] = nil end
    Changed(r)
end

local function Ped(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and ped or nil
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
AddCommand('report', nil, function(src)
    local r = activeOf[src] and reports[activeOf[src]]
    TriggerClientEvent('fks-chat:client:report:open', src, PlayerView(r), os.time())
end)

RegisterNetEvent('fks-chat:server:report:create', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if activeOf[src] then return Notify(src, _L('report_exists', activeOf[src]), 'error') end

    local now = os.time()
    if lastReport[src] and now - lastReport[src] < cfg.cooldown then
        return Notify(src, _L('report_cooldown', cfg.cooldown - (now - lastReport[src])), 'error')
    end

    local subject = CleanText(data.subject, cfg.subjectMax)
    local info = CleanText(data.info, cfg.infoMax, true)
    if not subject or not info then return Notify(src, _L('report_invalid'), 'error') end

    local r = {
        id = nextId, src = src, name = Name(src), steam = GetPlayerName(src),
        category = CATEGORIES[data.category] and data.category or 'question',
        subject = subject, created = now, status = 'open', online = true,
        messages = { { from = 'player', name = Name(src), text = info, time = now } },
    }
    nextId = nextId + 1
    reports[r.id], activeOf[src], lastReport[src] = r, r.id, now

    Notify(src, _L('report_sent', r.id), 'success')
    for _, a in ipairs(OnlineAdmins()) do
        Notify(a, { title = _L('report_new_title', r.id), description = _L('report_new', r.name, src, subject), type = 'warning', duration = 8000 })
        Send(a, { kind = 'report', text = _L('report_new_chat', r.id, r.name, src, subject, Config.Commands.reports or 'reports') })
    end
    Changed(r)
    Log('reports', _L('report_new_title', r.id), ('**%s** [%s] (%s) · %s\n**%s**\n%s'):format(r.name, src, r.steam, r.category, subject, info), 14714954)
end)

RegisterNetEvent('fks-chat:server:report:message', function(text)
    local src = source
    local r = activeOf[src] and reports[activeOf[src]]
    if not r then return end

    local last = r.messages[#r.messages]
    if not last or last.from ~= 'admin' then return Notify(src, _L('report_wait'), 'error') end
    text = CleanText(text, cfg.messageMax, true)
    if not text then return end

    r.messages[#r.messages + 1] = { from = 'player', name = r.name, text = text, time = os.time() }
    Changed(r)
    NotifyHandlers(r, { title = _L('report_title'), description = _L('report_reply_admin', r.name, r.id), type = 'inform' })
end)

RegisterNetEvent('fks-chat:server:report:cancel', function()
    local src = source
    local r = activeOf[src] and reports[activeOf[src]]
    if not r then return end
    NotifyHandlers(r, { title = _L('report_title'), description = _L('report_cancelled_admin', r.name, r.id), type = 'inform' })
    Close(r)
    Notify(src, _L('report_cancelled'), 'inform')
end)

---------------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------------
AddCommand('reports', nil, function(src)
    watching[src] = true
    TriggerClientEvent('fks-chat:client:reports:open', src, PanelData(src))
end, true)

RegisterNetEvent('fks-chat:server:reports:closed', function()
    watching[source] = nil
end)

local Actions = {}

function Actions.claim(src, r)
    r.admin, r.adminName, r.status = src, GetPlayerName(src), 'claimed'
    Notify(src, _L('report_claimed', r.id), 'success')
    if r.online then Notify(r.src, { title = _L('report_title'), description = _L('report_claimed_player', r.adminName), type = 'inform' }) end
    Changed(r)
end

function Actions.release(src, r)
    r.admin, r.adminName, r.status = nil, nil, 'open'
    Notify(src, _L('report_released', r.id), 'inform')
    Changed(r)
end

function Actions.message(src, r, text)
    text = CleanText(text, cfg.messageMax, true)
    if not text then return end
    r.messages[#r.messages + 1] = { from = 'admin', name = GetPlayerName(src), text = text, time = os.time() }
    Changed(r)
    if r.online then
        Notify(r.src, { title = _L('report_title'), description = _L('report_reply_player', GetPlayerName(src), Config.Commands.report or 'report'), type = 'inform', duration = 7000 })
    end
end

function Actions.close(src, r)
    if r.online then Notify(r.src, { title = _L('report_title'), description = _L('report_closed_player', GetPlayerName(src)), type = 'inform' }) end
    Notify(src, _L('report_closed_admin', r.id), 'success')
    Log('reports', _L('report_closed_admin', r.id), ('%s (%s)'):format(GetPlayerName(src), src), 10721928)
    Close(r)
end

Actions['goto'] = function(src, r)
    local target, me = Ped(r.src), Ped(src)
    if not target or not me then return Notify(src, _L('report_offline'), 'error') end
    backPos[src] = GetEntityCoords(me)
    TriggerClientEvent('fks-chat:client:teleport', src, GetEntityCoords(target) + vector3(cfg.returnOffset, 0.0, 0.0))
    Notify(src, _L('report_goto', r.name), 'success')
    PushAdmins()
end

function Actions.bring(src, r)
    local target, me = Ped(r.src), Ped(src)
    if not target or not me then return Notify(src, _L('report_offline'), 'error') end
    r.returnPos = r.returnPos or GetEntityCoords(target) -- the first position (bringing twice keeps the original)
    TriggerClientEvent('fks-chat:client:teleport', r.src, GetEntityCoords(me) + vector3(cfg.returnOffset, 0.0, 0.0))
    Notify(src, _L('report_bring', r.name), 'success')
    Notify(r.src, _L('report_brought'), 'inform')
    Changed(r)
end

Actions['return'] = function(src, r)
    if not r.returnPos then return Notify(src, _L('report_no_back'), 'error') end
    TriggerClientEvent('fks-chat:client:teleport', r.src, r.returnPos)
    r.returnPos = nil
    Notify(src, _L('report_returned', r.name), 'success')
    Notify(r.src, _L('report_player_returned'), 'inform')
    Changed(r)
end

-- actions that need the player in town
local NEEDS_ONLINE = { ['goto'] = true, bring = true, ['return'] = true }

RegisterNetEvent('fks-chat:server:reports:action', function(id, action, text)
    local src = source
    if not IsAdmin(src) then return end

    -- back to where the admin was before "go to" (not tied to a report)
    if action == 'back' then
        if not backPos[src] then return Notify(src, _L('report_no_back'), 'error') end
        TriggerClientEvent('fks-chat:client:teleport', src, backPos[src])
        backPos[src] = nil
        Notify(src, _L('report_back'), 'success')
        return PushAdmins()
    end

    local fn = Actions[action]
    local r = reports[tonumber(id) or -1]
    if not fn then return end
    if not r then
        Notify(src, _L('report_not_found'), 'error')
        return PushAdmins()
    end
    if r.admin and r.admin ~= src then return Notify(src, _L('report_taken', r.adminName), 'error') end
    if action ~= 'claim' and r.admin ~= src then return Notify(src, _L('report_need_claim'), 'error') end
    if action == 'claim' and r.admin == src then return end
    if NEEDS_ONLINE[action] and not r.online then return Notify(src, _L('report_offline'), 'error') end
    fn(src, r, text)
end)

---------------------------------------------------------------------------
-- Leaving: the player's report stays (marked offline) unless Config.Reports.closeOnDisconnect;
-- the reports the admin had go back to pending
---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    watching[src], backPos[src], lastReport[src] = nil, nil, nil

    for _, r in pairs(reports) do
        if r.admin == src then r.admin, r.adminName, r.status = nil, nil, 'open' end
    end

    local r = activeOf[src] and reports[activeOf[src]]
    activeOf[src] = nil
    if r then
        r.online, r.returnPos = false, nil
        if cfg.closeOnDisconnect then
            reports[r.id] = nil
        elseif r.admin then
            Notify(r.admin, _L('report_left', r.name, r.id), 'warning')
        end
    end
    PushAdmins()
end)
