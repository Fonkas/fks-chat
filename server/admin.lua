---------------------------------------------------------------------------
-- Admin: /adminmode, /clearall, /announce
---------------------------------------------------------------------------
local inAdminMode = {}

-- the "Admin" tag above the head is read by every client from this state bag (value = steam name)
local function SetAdminMode(src, on)
    inAdminMode[src] = on or nil
    Player(src).state:set('fksAdmin', on and GetPlayerName(src) or nil, true)
    TriggerClientEvent('fks-chat:client:adminMode', src, on)
end

AddCommand('adminmode', nil, function(src)
    local on = not inAdminMode[src]
    SetAdminMode(src, on)

    local steam = GetPlayerName(src)
    local note = {
        title = _L('adminmode_title'),
        description = _L(on and 'adminmode_on' or 'adminmode_off', steam),
        type = on and 'warning' or 'inform',
    }
    local who = Config.AdminMode.announce
    if who == 'all' then
        Notify(-1, note)
    elseif who == 'admins' then
        for _, a in ipairs(OnlineAdmins()) do Notify(a, note) end
    else
        Notify(src, note)
    end
    Log('adminmode', _L('adminmode_title'), note.description, on and 15909198 or 10721928)
end, true)

AddEventHandler('playerDropped', function() inAdminMode[source] = nil end)

-- after a restart of the script nobody is in admin mode any more: clear old tags
CreateThread(function()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if Player(src).state.fksAdmin then Player(src).state:set('fksAdmin', nil, true) end
    end
end)

AddCommand('clearall', nil, function(src)
    TriggerClientEvent('chat:clear', -1)
    Send(-1, { kind = 'system', text = _L('chat_cleared') })
    if Config.Chat.consoleLog then print(('[fks-chat] %s (%s) cleared the chat'):format(GetPlayerName(src), src)) end
end, true)

AddCommand('announce', { 'arg_text' }, function(src, _, text)
    if not text then return Usage(src, 'announce', 'arg_text') end
    Notify(-1, { title = _L('announce_title'), description = text, type = 'warning', duration = 10000 })
    Send(-1, { kind = 'announce', author = GetPlayerName(src), text = text })
    if Config.Chat.consoleLog then print(('[fks-chat] [announce] %s (%s): %s'):format(GetPlayerName(src), src, text)) end
end, true)
