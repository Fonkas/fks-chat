Config = {}

-- Server console: "up to date" / "OUTDATED" compared with the version in fxmanifest.lua on GitHub,
-- and a warning (with the download link) when fks-core (required) is not running
Config.VersionCheck = {
    enabled  = true,
    repo     = 'Fonkas/fks-chat',      -- GitHub "user/repository"
    branch   = 'main',
    interval = 12,                     -- check again every X hours (0 = only on start)
    coreUrl = 'https://github.com/Fonkas/fks-core',
}

-- Language: 'pt' | 'en' (files in locales/; missing keys fall back to English)
Config.Locale = 'en'

-- Framework: 'auto' | 'vorp' | 'rsg'
Config.Framework = 'auto'

-- Who is admin (/adminmode, /reports, /clearall, /announce, admin suggestions):
-- VORP groups / RSG permissions, plus anyone with this ACE (add_ace group.admin fks-chat.admin allow).
-- Full ACE access ('command') is always admin.
Config.AdminGroups = { 'admin', 'superadmin' }
Config.AdminAce = 'fks-chat.admin'

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
Config.Chat = {
    key = 0x9720FCEE,           -- opens the chat (T · INPUT_MP_TEXT_CHAT_ALL)
    maxLength = 250,            -- characters per message
    cooldown = 750,             -- ms between messages of the same player (anti-spam)
    plainText = 'local',        -- text without a command: 'local' (players near you) | 'global' (everyone) | false (disabled)
    localRange = 25.0,          -- distance of 'local' messages
    showIds = true,             -- show the player server id next to the name
    consoleLog = true,          -- print every message to the server console
    -- commands that only admins see in the suggestions (of other scripts too)
    adminSuggestions = { 'items' },
}

-- Commands: change the name or set false to disable
Config.Commands = {
    ooc       = 'ooc',          -- /ooc text            global out-of-character chat
    me        = 'me',           -- /me action           3D text above the player + local chat
    ['do']    = 'do',           -- /do description      3D text above the player + local chat
    ad        = 'ad',           -- /ad text             newspaper ad (paid)
    dice      = 'dice',         -- /dice [faces]        roll a dice
    flipcoin  = 'flipcoin',     -- /flipcoin            heads or tails
    random    = 'random',       -- /random [min] [max]  random number
    clear     = 'clear',        -- /clear               clears your own chat
    settings  = 'chatsettings', -- /chatsettings        chat settings (also the gear button in the chat)
    report    = 'report',       -- /report              send a report / open your report
    -- admin
    reports   = 'reports',      -- /reports             report panel
    adminmode = 'adminmode',    -- /adminmode           god mode + "Admin" tag above the head
    clearall  = 'clearall',     -- /clearall            clears the chat of everyone
    announce  = 'announce',     -- /announce text       announcement to the whole server
}

---------------------------------------------------------------------------
-- 3D text (/me, /do, /dice, /flipcoin, /random)
---------------------------------------------------------------------------
Config.ThreeD = {
    range = 15.0,               -- who sees it (and receives the chat line)
    duration = 7000,            -- ms on screen
    maxPerPlayer = 3,           -- bubbles stacked above the same player
    lineOfSight = true,         -- hide behind walls
    chat = true,                -- also write the line in the chat of the players in range
}

-- Dice / random
Config.Dice = { defaultFaces = 6, maxFaces = 100 }
Config.Random = { min = 1, max = 100, limit = 1000000 }

---------------------------------------------------------------------------
-- Newspaper ads (/ad)
---------------------------------------------------------------------------
Config.Ad = {
    price = 5,                  -- cash (0 = free)
    cooldown = 120,             -- seconds between ads of the same player
    jobs = nil,                 -- nil = everyone · { 'journalist' } = only these jobs
}

---------------------------------------------------------------------------
-- Admin mode (/adminmode)
---------------------------------------------------------------------------
Config.AdminMode = {
    announce = 'all',           -- notification when someone enters / leaves: 'all' | 'admins' | false
    godMode = true,             -- cannot die nor be hurt
    noNeeds = true,             -- hunger / thirst always full (fks-hud, rsg-hud and vorp_metabolism events)
    fullCores = true,           -- health / stamina cores always full
    noRagdoll = true,
    tagRange = 30.0,            -- distance at which the "Admin" tag is seen
    showOwnTag = true,          -- you also see your own tag
}

---------------------------------------------------------------------------
-- Reports (/report and /reports)
---------------------------------------------------------------------------
Config.Reports = {
    cooldown = 60,              -- seconds between reports of the same player
    subjectMax = 60,
    infoMax = 600,
    messageMax = 300,
    closeOnDisconnect = false,  -- true: the report is closed when the player leaves
    returnOffset = 1.5,         -- "go to": you appear this far from the player
}

---------------------------------------------------------------------------
-- Discord logs (webhook urls, '' = off)
---------------------------------------------------------------------------
Config.Webhooks = {
    reports = '',
    adminmode = '',
    ads = '',
}

---------------------------------------------------------------------------
-- Chat defaults (each player can change them in /chatsettings; saved on their PC)
---------------------------------------------------------------------------
Config.Defaults = {
    position = 'top-left',      -- 'top-left' | 'center-left' | 'bottom-left' | 'top-right'
    width = 42,                 -- % of the screen height units (30 - 70)
    fontSize = 100,             -- % (80 - 140)
    opacity = 55,               -- message background % (0 - 100)
    fade = 10,                  -- seconds until the messages hide (0 = never)
    maxMessages = 80,
    timestamps = false,
    colors = {
        ['local'] = '#cfc2a6',
        ooc       = '#8fb3c9',
        me        = '#c79ad6',
        ['do']    = '#9cc27a',
        ad        = '#f2c14e',
        dice      = '#e2ae3c',
        announce  = '#d9553f',
        admin     = '#f2c14e',
        report    = '#e0874a',
        system    = '#a39a88',
    },
}
