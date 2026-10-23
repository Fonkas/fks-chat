# Changelog

## 1.1.0

- **The chat is now drawn inside the fks-core NUI** (shared FKS UI, as an extension): fks-chat no longer has a NUI of
  its own, so the server runs one NUI for every FKS script. Fonts and colours come from fks-core (`Config.Theme`).
- `/report` and `/reports` are fks-core screens (same flow: categories, take the report, go to / bring / return,
  conversation with turns). The chat does not open on top of another FKS screen.
- **Requires fks-core 2.1.0+.**

## 1.0.0

First release: chat (replaces the default `chat` resource), `/me` `/do` `/dice` `/flipcoin` `/random` with 3D text,
`/ooc`, `/ad` newspaper ads, chat settings per player, `/adminmode`, `/clearall`, `/announce` and the report system
(`/report` and `/reports`).
