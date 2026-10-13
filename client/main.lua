---------------------------------------------------------------------------
-- NUI bridge: messages sent before the page is ready are queued
---------------------------------------------------------------------------
local uiReady = false
local queue = {}

function SendUI(action, data)
    if not uiReady then
        queue[#queue + 1] = { action = action, data = data }
        return
    end
    SendNUIMessage({ action = action, data = data })
end

-- frequent updates (3D positions): dropped instead of queued while the page loads
function SendUILive(action, data)
    if uiReady then SendNUIMessage({ action = action, data = data }) end
end

---------------------------------------------------------------------------
-- Focus: the chat and every panel use mouse + keyboard. The page calls "release" when the
-- last thing open is closed.
---------------------------------------------------------------------------
local focused = false

function SetFocus(on)
    focused = on
    SetNuiFocus(on, on)
end

function IsFocused() return focused end

-- opens a panel of the page (report, reports, settings)
function OpenPanel(action, data)
    SetFocus(true)
    SendUI(action, data)
end

RegisterNUICallback('release', function(_, cb)
    SetFocus(false)
    cb('ok')
end)

---------------------------------------------------------------------------
-- Settings of the player (saved on their PC)
---------------------------------------------------------------------------
local KVP = 'fks-chat:settings'

local function LoadSettings()
    local raw = GetResourceKvpString(KVP)
    if not raw or raw == '' then return nil end
    local ok, data = pcall(json.decode, raw)
    return ok and type(data) == 'table' and data or nil
end

RegisterNUICallback('settings:save', function(data, cb)
    if type(data) == 'table' then SetResourceKvp(KVP, json.encode(data)) end
    cb('ok')
end)

RegisterNetEvent('fks-chat:client:settings', function()
    OpenPanel('settings:open')
end)

RegisterNUICallback('ready', function(_, cb)
    uiReady = true
    SendNUIMessage({
        action = 'init',
        data = {
            locale = LocaleUI,
            defaults = Config.Defaults,
            settings = LoadSettings(),
            showIds = Config.Chat.showIds,
            maxLength = Config.Chat.maxLength,
            reports = { subjectMax = Config.Reports.subjectMax, infoMax = Config.Reports.infoMax, messageMax = Config.Reports.messageMax },
            maxBubbles = Config.ThreeD.maxPerPlayer,
        },
    })
    for _, msg in ipairs(queue) do SendNUIMessage(msg) end
    queue = {}
    TriggerServerEvent('fks-chat:server:init')
    cb('ok')
end)

---------------------------------------------------------------------------
-- Opening the chat (T) and sending
---------------------------------------------------------------------------
CreateThread(function()
    local key = Config.Chat.key
    while true do
        Wait(0)
        if not focused then
            DisableControlAction(0, key, true)
            if IsDisabledControlJustReleased(0, key) and not IsPauseMenuActive() then
                SetFocus(true)
                SendUI('chat:open')
            end
        end
    end
end)

RegisterNUICallback('chat:submit', function(data, cb)
    cb('ok')
    SetFocus(false) -- before running the command: a command may open a panel
    local text = type(data) == 'table' and type(data.text) == 'string' and data.text or ''
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return end
    if text:sub(1, 1) == '/' then
        if #text > 1 then ExecuteCommand(text:sub(2)) end
    else
        TriggerServerEvent('fks-chat:server:message', text)
    end
end)

-- hidden with the pause menu
CreateThread(function()
    local hidden = false
    while true do
        Wait(250)
        local h = IsPauseMenuActive()
        if h ~= hidden then
            hidden = h
            SendUI('chat:hide', h)
        end
    end
end)

---------------------------------------------------------------------------
-- Messages (fks-chat) and the events of the default chat resource
---------------------------------------------------------------------------
RegisterNetEvent('fks-chat:client:message', function(msg)
    if type(msg) == 'table' then SendUI('chat:message', msg) end
end)

-- TriggerClientEvent('chat:addMessage', src, { color = { 255, 0, 0 }, args = { 'Author', 'Text' } })
local function External(m)
    if type(m) == 'string' then m = { args = { m } } end
    if type(m) ~= 'table' then return end
    SendUI('chat:message', { kind = 'external', color = m.color, args = m.args, template = m.template })
end

RegisterNetEvent('chat:addMessage', External)
exports('addMessage', External)

-- TriggerClientEvent('chatMessage', src, 'Author', { 255, 255, 255 }, 'Text')
RegisterNetEvent('chatMessage', function(author, color, text)
    SendUI('chat:message', { kind = 'external', color = color, args = { author or '', text or '' } })
end)

RegisterNetEvent('chat:clear', function() SendUI('chat:clear') end)

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------
RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    SendUI('chat:suggestion', { name = name, help = help, params = params })
end)

RegisterNetEvent('chat:addSuggestions', function(list)
    for _, s in ipairs(list or {}) do SendUI('chat:suggestion', s) end
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    SendUI('chat:removeSuggestion', name)
end)

-- from the server (fks-chat commands + server commands this player may use) + the commands of this client
RegisterNetEvent('fks-chat:client:suggestions', function(list)
    list = type(list) == 'table' and list or {}
    for _, c in ipairs(GetRegisteredCommands()) do
        if c.resource and c.resource ~= '' and not c.name:find('^[_+%-]') then
            list[#list + 1] = { name = '/' .. c.name, help = '' }
        end
    end
    SendUI('chat:suggestions', list)
end)

-- the admin group is only known once the character is loaded
Bridge.OnLoaded(function()
    if uiReady then TriggerServerEvent('fks-chat:server:init') end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and focused then SetNuiFocus(false, false) end
end)
