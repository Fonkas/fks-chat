---------------------------------------------------------------------------
-- Chat core: helpers shared by the other server files, plain messages, command suggestions
-- and compatibility with the default "chat" resource (chatMessage, chat:addMessage...)
---------------------------------------------------------------------------

function IsAdmin(src)
    return Bridge.IsAdmin(src, Config.AdminGroups, Config.AdminAce)
end

function OnlineAdmins()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if IsAdmin(src) then list[#list + 1] = src end
    end
    return list
end

function Notify(src, ...)
    Bridge.Notify(src, ...)
end

-- character name (falls back to the steam name)
function Name(src)
    return Bridge.CharacterName(src) or GetPlayerName(src)
end

-- text typed by a player: no colour codes nor control characters, trimmed and cut to `max` characters.
-- multiline keeps line breaks (report texts). nil when nothing is left.
function CleanText(text, max, multiline)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('%^%d', '')
    if multiline then
        text = text:gsub('\r', ''):gsub('[\0-\9\11-\31]', ' '):gsub('\n\n\n+', '\n\n')
    else
        text = text:gsub('%c', ' '):gsub('%s%s+', ' ')
    end
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return nil end
    if max then
        local len = utf8.len(text)
        if len and len > max then
            text = text:sub(1, utf8.offset(text, max + 1) - 1)
        elseif not len and #text > max then
            text = text:sub(1, max)
        end
    end
    return text
end

-- anti-spam: false when the player wrote less than Config.Chat.cooldown ms ago
local lastMessage = {}
function Throttle(src)
    local now = GetGameTimer()
    if lastMessage[src] and now - lastMessage[src] < Config.Chat.cooldown then
        Notify(src, _L('cooldown'), 'error', 2500)
        return false
    end
    lastMessage[src] = now
    return true
end

-- players within `range` of src (same routing bucket), src included.
-- Without OneSync the server has no positions: everyone.
local warnedOneSync = false
function Nearby(src, range)
    local list = {}
    local ped = GetPlayerPed(src)
    local origin = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    if not origin and not warnedOneSync then
        warnedOneSync = true
        print('^3[fks-chat] OneSync is off: local messages and 3D text are sent to everyone.^0')
    end
    local bucket = GetPlayerRoutingBucket(src)
    for _, id in ipairs(GetPlayers()) do
        local t = tonumber(id)
        if t == src or not origin then
            list[#list + 1] = t
        elseif GetPlayerRoutingBucket(t) == bucket then
            local p = GetPlayerPed(t)
            if p ~= 0 and #(GetEntityCoords(p) - origin) <= range then list[#list + 1] = t end
        end
    end
    return list
end

-- chat line: { kind, author, id, text } (kind = colour / tag of the line)
function Send(target, msg)
    TriggerClientEvent('fks-chat:client:message', target, msg)
end

function Log(webhook, title, text, color)
    if Config.Chat.consoleLog then print(('[fks-chat] %s: %s'):format(title, (text:gsub('\n', ' ')))) end
    local url = Config.Webhooks[webhook]
    if not url or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = 'fks-chat',
        embeds = { { title = title, description = text, color = color or 15909198, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end

---------------------------------------------------------------------------
-- Commands: AddCommand(key, params, handler, admin)
--   key     = entry of Config.Commands (its value is the command name; false = disabled)
--   params  = { 'arg_text', ... } locale keys of the arguments (chat suggestions)
--   handler = function(src, args, text) - text = everything after the command, cleaned (nil if empty)
---------------------------------------------------------------------------
local Suggestions = {}
local hiddenForPlayers = {}
for _, name in ipairs(Config.Chat.adminSuggestions or {}) do hiddenForPlayers[name] = true end

function AddCommand(key, params, handler, admin)
    local name = Config.Commands[key]
    if not name then return end

    RegisterCommand(name, function(src, args, raw)
        if src == 0 then return print('[fks-chat] ' .. _L('player_only')) end
        if admin and not IsAdmin(src) then return Notify(src, _L('no_permission'), 'error') end
        local text = raw:match('^%S+%s+(.+)$')
        handler(src, args, text and CleanText(text, Config.Chat.maxLength))
    end, false)

    local list = {}
    for _, p in ipairs(params or {}) do list[#list + 1] = { name = _L(p), help = '' } end
    Suggestions[#Suggestions + 1] = { name = name, help = _L('help_' .. key), params = list, admin = admin }
    if admin then hiddenForPlayers[name] = true end
end

-- "Usage: /me action"
function Usage(src, key, ...)
    local args = {}
    for i, p in ipairs({ ... }) do args[i] = '[' .. _L(p) .. ']' end
    Notify(src, _L('usage', Config.Commands[key], table.concat(args, ' ')), 'error')
end

-- suggestions of one player: the fks-chat commands (admin ones only for admins) and the commands of the
-- other resources that the player is allowed to use (Config.Chat.adminSuggestions only for admins)
local function SuggestionsFor(src)
    local admin = IsAdmin(src)
    local list, seen = {}, {}
    for _, s in ipairs(Suggestions) do
        if admin or not s.admin then list[#list + 1] = { name = '/' .. s.name, help = s.help, params = s.params } end
        seen[s.name] = true
    end
    for _, c in ipairs(GetRegisteredCommands()) do
        local n = c.name
        if not seen[n] and c.resource and c.resource ~= '' and not n:find('^[_+%-]')
            and (admin or not hiddenForPlayers[n]) and IsPlayerAceAllowed(src, 'command.' .. n) then
            seen[n] = true
            list[#list + 1] = { name = '/' .. n, help = '' }
        end
    end
    return list
end

local function RefreshSuggestions(src)
    TriggerClientEvent('fks-chat:client:suggestions', src, SuggestionsFor(src))
end

-- the page is ready / the character was loaded (the admin group may only be known then)
RegisterNetEvent('fks-chat:server:init', function() RefreshSuggestions(source) end)
Bridge.OnCharacterLoaded(function(src) SetTimeout(1000, function() RefreshSuggestions(src) end) end)

-- a resource started: its commands become available
AddEventHandler('onServerResourceStart', function(res)
    if res == GetCurrentResourceName() then return end
    SetTimeout(1000, function()
        for _, id in ipairs(GetPlayers()) do RefreshSuggestions(tonumber(id)) end
    end)
end)

---------------------------------------------------------------------------
-- Text without a command (Config.Chat.plainText). Other resources can still cancel it the
-- old way: AddEventHandler('chatMessage', function(src, author, text) CancelEvent() end)
---------------------------------------------------------------------------
RegisterNetEvent('fks-chat:server:message', function(text)
    local src = source
    text = CleanText(text, Config.Chat.maxLength)
    if not text or not Throttle(src) then return end

    TriggerEvent('chatMessage', src, GetPlayerName(src), text)
    if WasEventCanceled() then return end

    local mode = Config.Chat.plainText
    if mode == 'global' then
        Send(-1, { kind = 'ooc', author = GetPlayerName(src), id = src, text = text })
    elseif mode == 'local' then
        local msg = { kind = 'local', author = Name(src), id = src, text = text }
        for _, t in ipairs(Nearby(src, Config.Chat.localRange)) do Send(t, msg) end
    else
        return Notify(src, _L('plain_disabled', Config.Commands.ooc or Config.Commands.me or 'report'), 'error')
    end
    if Config.Chat.consoleLog then print(('[fks-chat] [%s] %s (%s): %s'):format(mode, GetPlayerName(src), src, text)) end
end)

-- command that does not exist on the client nor on the server
AddEventHandler('__cfx_internal:commandFallback', function(command)
    local src = source
    CancelEvent()
    TriggerEvent('chatMessage', src, GetPlayerName(src), '/' .. command)
    if WasEventCanceled() then return end
    Send(src, { kind = 'system', text = _L('unknown_command', command:match('^%S+') or command) })
end)

AddEventHandler('playerDropped', function() lastMessage[source] = nil end)

---------------------------------------------------------------------------
-- Same exports as the default chat resource
---------------------------------------------------------------------------
exports('addMessage', function(target, message)
    TriggerClientEvent('chat:addMessage', target or -1, message)
end)
