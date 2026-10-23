---------------------------------------------------------------------------
-- 3D UI above the players: /me, /do, dice... bubbles and the "Admin" tag.
-- The page draws them; this file only sends, every frame, where each player's head is on screen.
---------------------------------------------------------------------------
local cfg = Config.ThreeD
local HEAD = 21030                        -- SKEL_Head

local bubbleUntil = {}                    -- [server id] = GetGameTimer() when the last bubble ends
local tags = {}                           -- [server id] = steam name of admins in admin mode
local visible = {}                        -- [server id] = line of sight (refreshed every 300 ms)

RegisterNetEvent('fks-chat:client:bubble', function(sid, kind, text)
    if type(text) ~= 'string' then return end
    bubbleUntil[sid] = GetGameTimer() + cfg.duration
    SendUI('3d:bubble', { sid = sid, kind = kind, text = text, duration = cfg.duration })
end)

local function HeadCoords(ped)
    local bone = GetPedBoneIndex(ped, HEAD)
    local c = bone and bone ~= -1 and GetWorldPositionOfEntityBone(ped, bone)
    if not c or (c.x == 0.0 and c.y == 0.0) then c = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.75) end
    return c
end

-- admin tags + line of sight, a few times per second
CreateThread(function()
    local me = PlayerId()
    while true do
        local myPed = PlayerPedId()
        local newTags, newVisible, changed = {}, {}, false
        for _, pid in ipairs(GetActivePlayers()) do
            local sid = GetPlayerServerId(pid)
            local name = Player(sid).state.fksAdmin
            if name and (pid ~= me or Config.AdminMode.showOwnTag) then
                newTags[sid] = name
                if tags[sid] ~= name then changed = true end
            end
            local ped = GetPlayerPed(pid)
            newVisible[sid] = pid == me or not cfg.lineOfSight or HasEntityClearLosToEntity(myPed, ped, 17)
        end
        for sid in pairs(tags) do if not newTags[sid] then changed = true end end
        tags, visible = newTags, newVisible
        if changed then
            local list = {}
            for sid, name in pairs(tags) do list[#list + 1] = { sid = sid, name = name } end
            SendUI('3d:tags', { list = list })
        end
        Wait(300)
    end
end)

-- positions on screen
CreateThread(function()
    local lastSent = false
    while true do
        local now = GetGameTimer()
        local sids = {}
        for sid, untilT in pairs(bubbleUntil) do
            if now > untilT + 500 then bubbleUntil[sid] = nil else sids[sid] = cfg.range end
        end
        for sid in pairs(tags) do sids[sid] = math.max(sids[sid] or 0, Config.AdminMode.tagRange) end

        if next(sids) then
            local cam = GetFinalRenderedCamCoord()
            local out = {}
            for sid, range in pairs(sids) do
                local pid = GetPlayerFromServerId(sid)
                local ped = pid ~= -1 and GetPlayerPed(pid) or 0
                if ped ~= 0 and DoesEntityExist(ped) and visible[sid] ~= false then
                    local head = HeadCoords(ped)
                    local dist = #(cam - head)
                    if dist <= range then
                        local onScreen, x, y = GetScreenCoordFromWorldCoord(head.x, head.y, head.z + 0.28)
                        if onScreen then
                            local scale = math.max(0.55, 1.0 - (dist / range) * 0.45)
                            out[#out + 1] = { sid, x, y, scale }
                        end
                    end
                end
            end
            SendUILive('3d:pos', { list = out })
            lastSent = #out > 0
            Wait(0)
        else
            if lastSent then
                SendUILive('3d:pos', { list = {} })
                lastSent = false
            end
            Wait(250)
        end
    end
end)
