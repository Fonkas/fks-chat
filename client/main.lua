---------------------------------------------------------------------------
-- The chat is drawn inside the fks-core NUI: ui/chat.js + ui/chat.css are loaded there as an
-- extension (UI.Extend). The reports are normal fks-core screens (client/reports.lua).
---------------------------------------------------------------------------
function SendUI(action, data)
    UI.ExtSend(action, data)
end

-- frequent updates (3D positions)
SendUILive = SendUI

---------------------------------------------------------------------------
-- Focus: the chat input and the settings card take mouse + keyboard; the page gives it back
-- (api.focus(false)) when the last of them closes.
---------------------------------------------------------------------------
local focused = false

function SetFocus(on)
    focused = on
    UI.ExtFocus(on)
end

function IsFocused() return focused end

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

UI.OnExt('settings:save', function(data)
    if type(data) == 'table' then SetResourceKvp(KVP, json.encode(data)) end
end)

RegisterNetEvent('fks-chat:client:settings', function()
    SetFocus(true)
    SendUI('settings:open')
end)

---------------------------------------------------------------------------
-- Loading into the fks-core NUI
---------------------------------------------------------------------------
local function Start()
    UI.Extend({ js = 'ui/chat.js', css = 'ui/chat.css' })
    SendUI('init', {
        locale = LocaleUI,
        defaults = Config.Defaults,
        settings = LoadSettings(),
        showIds = Config.Chat.showIds,
        maxLength = Config.Chat.maxLength,
        maxBubbles = Config.ThreeD.maxPerPlayer,
    })
    TriggerServerEvent('fks-chat:server:init')
end

CreateThread(Start)

-- fks-core restarted: the bridge loads the extension again, the chat needs its settings and suggestions back
UI.OnExt('restart', function()
    focused = false
    SendUI('init', {
        locale = LocaleUI, defaults = Config.Defaults, settings = LoadSettings(),
        showIds = Config.Chat.showIds, maxLength = Config.Chat.maxLength, maxBubbles = Config.ThreeD.maxPerPlayer,
    })
    TriggerServerEvent('fks-chat:server:init')
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
            -- not on top of another FKS screen (stable, character creator...)
            if IsDisabledControlJustReleased(0, key) and not IsPauseMenuActive() and not UI.HasFocus() then
                SetFocus(true)
                SendUI('chat:open')
            end
        end
    end
end)

-- the page closed the chat / settings with ESC
UI.OnExt('release', function() SetFocus(false) end)

UI.OnExt('submit', function(data)
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
            SendUI('chat:hide', { on = h })
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
    SendUI('chat:removeSuggestion', { name = name })
end)

-- from the server (fks-chat commands + server commands this player may use) + the commands of this client
RegisterNetEvent('fks-chat:client:suggestions', function(list)
    list = type(list) == 'table' and list or {}
    for _, c in ipairs(GetRegisteredCommands()) do
        if c.resource and c.resource ~= '' and not c.name:find('^[_+%-]') then
            list[#list + 1] = { name = '/' .. c.name, help = '' }
        end
    end
    SendUI('chat:suggestions', { list = list })
end)

-- the admin group is only known once the character is loaded
Bridge.OnLoaded(function()
    TriggerServerEvent('fks-chat:server:init')
end)
