# Monica 4 for Home Assistant

A Home Assistant OS add-on that runs the official `monica:4.1.2-apache` image
([monicahq/monica](https://github.com/monicahq/monica), last 4.x release), with
MariaDB bundled inside the add-on and HTTPS from Nginx Proxy Manager.

## Install

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fjpcoenen%2Fmonica-ha)

Or by hand: Settings → Add-ons → Add-on Store → ⋮ → **Repositories**, add
`https://github.com/jpcoenen/monica-ha`, then install **Monica** from the store.

Setup (options, Nginx Proxy Manager, backups) is in
[`monica/DOCS.md`](monica/DOCS.md), also shown on the add-on's Documentation tab.
