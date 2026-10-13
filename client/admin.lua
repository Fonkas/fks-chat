---------------------------------------------------------------------------
-- Admin mode: cannot die, no hunger / thirst, full cores. The "Admin" tag is drawn by bubbles.lua
-- from the state bag the server sets.
---------------------------------------------------------------------------
local cfg = Config.AdminMode
local active = false

local function SetGod(on)
    local ped = PlayerPedId()
    if cfg.godMode then
        SetEntityInvincible(ped, on)
        SetPlayerInvincible(PlayerId(), on)
    end
    if cfg.noRagdoll then SetPedCanRagdoll(ped, not on) end
end

local function Refill()
    local ped = PlayerPedId()
    if cfg.fullCores then
        Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, 100) -- SET_ATTRIBUTE_CORE_VALUE health
        Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, 100) -- stamina
        local max = GetEntityMaxHealth(ped)
        if not IsEntityDead(ped) and GetEntityHealth(ped) < max then SetEntityHealth(ped, max, 0) end
        RestorePlayerStamina(PlayerId(), 100.0)
    end
    if cfg.noNeeds then
        TriggerEvent('hud:client:UpdateNeeds', 100, 100)          -- fks-hud / rsg-hud
        TriggerEvent('vorpmetabolism:setValue', 'Hunger', 1000)   -- vorp_metabolism (fks-hud also listens)
        TriggerEvent('vorpmetabolism:setValue', 'Thirst', 1000)
    end
end

RegisterNetEvent('fks-chat:client:adminMode', function(on)
    active = on == true
    TriggerEvent('fks-chat:client:adminModeChanged', active) -- for other scripts
    if not active then return SetGod(false) end

    CreateThread(function()
        local nextRefill = 0
        while active do
            SetGod(true) -- again every tick: the ped changes after a respawn or a skin change
            if GetGameTimer() >= nextRefill then
                nextRefill = GetGameTimer() + 5000
                Refill()
            end
            Wait(500)
        end
    end)
end)

exports('IsAdminMode', function() return active end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then
        active = false
        SetGod(false)
    end
end)
