---------------------------------------------------------------------------
-- Roleplay commands: /ooc /me /do /ad /dice /flipcoin /random /clear /chatsettings
---------------------------------------------------------------------------
local Scene3D = Config.ThreeD

-- 3D text above the player + chat line, for the players in range
local function Scene(src, kind, bubble, msg)
    for _, t in ipairs(Nearby(src, Scene3D.range)) do
        TriggerClientEvent('fks-chat:client:bubble', t, src, kind, bubble)
        if Scene3D.chat then Send(t, msg) end
    end
    if Config.Chat.consoleLog then print(('[fks-chat] [%s] %s (%s): %s'):format(kind, GetPlayerName(src), src, msg.text)) end
end

AddCommand('ooc', { 'arg_text' }, function(src, _, text)
    if not text then return Usage(src, 'ooc', 'arg_text') end
    if not Throttle(src) then return end
    Send(-1, { kind = 'ooc', author = GetPlayerName(src), id = src, text = text })
    if Config.Chat.consoleLog then print(('[fks-chat] [ooc] %s (%s): %s'):format(GetPlayerName(src), src, text)) end
end)

AddCommand('me', { 'arg_action' }, function(src, _, text)
    if not text then return Usage(src, 'me', 'arg_action') end
    if not Throttle(src) then return end
    Scene(src, 'me', text, { kind = 'me', author = Name(src), id = src, text = text })
end)

AddCommand('do', { 'arg_description' }, function(src, _, text)
    if not text then return Usage(src, 'do', 'arg_description') end
    if not Throttle(src) then return end
    Scene(src, 'do', text, { kind = 'do', author = Name(src), id = src, text = text })
end)

AddCommand('dice', { 'arg_faces' }, function(src, args)
    if not Throttle(src) then return end
    local cfg = Config.Dice
    local faces = math.floor(tonumber(args[1]) or cfg.defaultFaces)
    faces = math.max(2, math.min(faces, cfg.maxFaces))
    local n = math.random(1, faces)
    Scene(src, 'dice', ('%s · d%s'):format(n, faces), { kind = 'dice', author = Name(src), id = src, text = _L('dice_result', faces, n) })
end)

AddCommand('flipcoin', nil, function(src)
    if not Throttle(src) then return end
    local side = _L(math.random(2) == 1 and 'heads' or 'tails')
    Scene(src, 'coin', side, { kind = 'dice', author = Name(src), id = src, text = _L('flip_result', side) })
end)

AddCommand('random', { 'arg_min', 'arg_max' }, function(src, args)
    if not Throttle(src) then return end
    local cfg = Config.Random
    local a, b = tonumber(args[1]), tonumber(args[2])
    local min, max = cfg.min, cfg.max
    if a and b then min, max = a, b elseif a then max = a end
    min, max = math.floor(math.max(-cfg.limit, min)), math.floor(math.min(cfg.limit, max))
    if min > max then min, max = max, min end
    local n = math.random(min, max)
    Scene(src, 'random', ('%s · %s-%s'):format(n, min, max), { kind = 'dice', author = Name(src), id = src, text = _L('random_result', min, max, n) })
end)

---------------------------------------------------------------------------
-- Newspaper ad (paid, with cooldown, optionally only for some jobs)
---------------------------------------------------------------------------
local lastAd = {}

AddCommand('ad', { 'arg_text' }, function(src, _, text)
    if not text then return Usage(src, 'ad', 'arg_text') end
    local cfg = Config.Ad
    local P = Bridge.GetPlayer(src)
    if not P then return end

    if cfg.jobs then
        local ok = false
        for _, job in ipairs(cfg.jobs) do if P.job == job then ok = true break end end
        if not ok then return Notify(src, _L('ad_job'), 'error') end
    end

    local now = os.time()
    if lastAd[src] and now - lastAd[src] < cfg.cooldown then
        return Notify(src, _L('ad_cooldown', cfg.cooldown - (now - lastAd[src])), 'error')
    end

    local price = tonumber(cfg.price) or 0
    if price > 0 and not P.remove('cash', price, 'fks-chat newspaper ad') then
        return Notify(src, _L('ad_no_money', price), 'error')
    end
    lastAd[src] = now

    Send(-1, { kind = 'ad', author = P.name, id = src, text = text })
    if price > 0 then Notify(src, _L('ad_paid', price), 'success') end
    Log('ads', _L('ad_title'), ('%s [%s] (%s): %s'):format(P.name, src, GetPlayerName(src), text), 15909198)
end)

AddEventHandler('playerDropped', function() lastAd[source] = nil end)

---------------------------------------------------------------------------
-- Own chat
---------------------------------------------------------------------------
AddCommand('clear', nil, function(src)
    TriggerClientEvent('chat:clear', src)
end)

AddCommand('settings', nil, function(src)
    TriggerClientEvent('fks-chat:client:settings', src)
end)
