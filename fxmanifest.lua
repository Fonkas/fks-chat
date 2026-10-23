-- fks-chat · Copyright (C) 2026 FKS · Licensed under the GNU GPL v3 or later (see LICENSE)
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'fks-chat'
author 'FKS'
description 'Chat for RedM (VORP / RSG): roleplay commands with 3D text, newspaper ads, dice, admin mode and a report system'
version '1.1.0'
license 'GPL-3.0-or-later'
fks_core_version '2.1.0' -- minimum fks-core version (VORP / RSG bridge, shared UI, notifications)

-- replaces the default "chat" resource (chat:addMessage, chat:addSuggestion, chatMessage... keep working)
provide 'chat'

shared_scripts {
    '@fks-core/import.lua',
    'config.lua',
    'locales/*.lua',
    'shared/locale.lua',
}

client_scripts {
    'client/main.lua',
    'client/bubbles.lua',
    'client/admin.lua',
    'client/reports.lua',
}

server_scripts {
    'server/version.lua',
    'server/main.lua',
    'server/commands.lua',
    'server/admin.lua',
    'server/reports.lua',
}

-- the chat is drawn inside the fks-core NUI (extension): only its own script and styles live here
files {
    'ui/chat.js',
    'ui/chat.css',
}

-- + fks-core 2.1.0+ (required: VORP / RSG bridge, shared UI, notifications) - https://github.com/Fonkas/fks-core
--   not listed below so that, when it is missing, the server console shows the download link (server/version.lua)
-- + a framework (vorp_core or rsg-core)
