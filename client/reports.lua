---------------------------------------------------------------------------
-- Reports: player form / conversation (/report) and admin panel (/reports).
-- The server validates everything (permissions, who took the report, whose turn it is to write).
---------------------------------------------------------------------------

-- player
RegisterNetEvent('fks-chat:client:report:open', function(report, now)
    OpenPanel('report:open', { report = report, now = now })
end)

RegisterNetEvent('fks-chat:client:report:update', function(report, now)
    SendUI('report:update', { report = report, now = now })
end)

RegisterNUICallback('report:create', function(data, cb)
    if type(data) == 'table' then
        TriggerServerEvent('fks-chat:server:report:create', { category = data.category, subject = data.subject, info = data.info })
    end
    cb('ok')
end)

RegisterNUICallback('report:message', function(data, cb)
    if type(data) == 'table' then TriggerServerEvent('fks-chat:server:report:message', data.text) end
    cb('ok')
end)

RegisterNUICallback('report:cancel', function(_, cb)
    TriggerServerEvent('fks-chat:server:report:cancel')
    cb('ok')
end)

-- admin
RegisterNetEvent('fks-chat:client:reports:open', function(data)
    OpenPanel('reports:open', data)
end)

RegisterNetEvent('fks-chat:client:reports:update', function(data)
    SendUI('reports:update', data)
end)

RegisterNUICallback('reports:action', function(data, cb)
    if type(data) == 'table' then TriggerServerEvent('fks-chat:server:reports:action', data.id, data.action, data.text) end
    cb('ok')
end)

RegisterNUICallback('reports:closed', function(_, cb)
    TriggerServerEvent('fks-chat:server:reports:closed')
    cb('ok')
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
