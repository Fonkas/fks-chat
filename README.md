# fks-chat

Chat, roleplay commands, admin mode and reports for **RedM** - works with **RSG** and **VORP** (detected automatically).

- Chat with command suggestions, message history and colour per channel
- `/me`, `/do`, `/dice`, `/flipcoin` and `/random` shown in 3D above the player (with line of sight) and in the local chat
- `/ooc` global chat, local chat by distance, paid `/ad` newspaper ads with cooldown and job restriction
- `/chatsettings`: position, width, text size, background, fade time, timestamps and channel colours (saved per player)
- `/adminmode`: god mode, no hunger / thirst, "Admin" tag with the steam name above the head, notification to everyone
- `/report` and `/reports`: categories, take the report, go to / bring / return the player, conversation with turns
- `/clearall` and `/announce` for admins, Discord logs, English and Português
- Drop-in replacement of the default `chat` resource

---

It **replaces the default `chat` resource** (`provide 'chat'`): `chat:addMessage`, `chat:addSuggestion(s)`,
`chat:removeSuggestion`, `chat:clear`, `chatMessage` and `exports.chat:addMessage` keep working, so the other
scripts do not need changes. Every registered command (for example `/items` from fks-core) works from the chat.

## Installation

```cfg
ensure oxmysql         # needed by fks-core
ensure vorp_core        # or rsg-core
ensure fks-core        # 2.1.0+, before the FKS scripts (it also draws the chat)
ensure fks-chat
```

The server console shows whether fks-chat is **up to date** or **OUTDATED** compared with GitHub (`Config.VersionCheck`).
Do not run the default `chat` resource at the same time. OneSync is needed for the local range (without it local
messages and 3D text go to everyone).

## Commands

| Command | Who | |
|---|---|---|
| text without `/` | all | local chat (`Config.Chat.plainText`: `'local'`, `'global'` or `false`) |
| `/ooc text` | all | out-of-character chat for the whole server |
| `/me action` | all | 3D text above the player + chat line for the players in range |
| `/do description` | all | 3D text above the player + chat line for the players in range |
| `/dice [faces]` · `/flipcoin` · `/random [min] [max]` | all | result in 3D and in the chat |
| `/ad text` | all | newspaper ad for everyone (price, cooldown and jobs in `Config.Ad`) |
| `/clear` · `/chatsettings` | all | clear your chat · chat settings (also the gear in the chat bar) |
| `/report` | all | send a report, or open the conversation of your open report |
| `/reports` | admin | report panel |
| `/adminmode` | admin | god mode, no hunger / thirst, "Admin" + steam name above the head, notification to everyone |
| `/clearall` · `/announce text` | admin | clear everyone's chat · announcement to the whole server |

All command names can be changed (or disabled with `false`) in `Config.Commands`.

**Who is admin:** the VORP groups / RSG permissions in `Config.AdminGroups`, anyone with the `fks-chat.admin` ACE
(`add_ace group.admin fks-chat.admin allow`) and anyone with full ACE access. Admin commands only appear in the
suggestions of admins (as well as the commands in `Config.Chat.adminSuggestions`, by default `/items`).

## Chat

- **T** opens the chat · **Enter** sends · **Esc** closes · **↑ / ↓** previous messages or suggestion · **Tab** completes the command.
- Settings per player (saved on their PC): position, width, text size, background, time until the messages hide,
  show the time, and the colour of every channel.

## Reports

1. The player writes `/report`, picks the category (player / question / bug), the subject and the information.
2. Every admin online gets a notification and a line in the chat.
3. In `/reports` the admin opens a report and clicks **Take report** — from then on only that admin can act on it.
4. Then: **Go to** (teleports to the player; **Back** returns to where they were), **Bring** (brings the player;
   **Return** sends them back), answer in the conversation, **Release** or **Close report**.
5. The player answers in `/report`. Admins can always write; the player can only write again after an admin answered.

Reports live in memory (a restart clears them). When a player leaves, their report stays marked offline
(`Config.Reports.closeOnDisconnect = true` closes it). Discord logs: `Config.Webhooks`.

## For other scripts

```lua
-- client
exports['fks-chat']:IsAdminMode()
AddEventHandler('fks-chat:client:adminModeChanged', function(on) end)

-- server (same as the default chat)
TriggerClientEvent('chat:addMessage', src, { color = { 255, 200, 80 }, args = { 'Sheriff', 'Text' } })
exports['fks-chat']:addMessage(src, { args = { 'Text' } })
```

## License

GNU GPL v3 or later (see `LICENSE`).
