# Monica 4

Runs the official `monica:4.1.2-apache` image (the last 4.x release of
[monicahq/monica](https://github.com/monicahq/monica)) as a Home Assistant add-on.
MariaDB is bundled inside the add-on, so there's no separate database to set up.
Put Nginx Proxy Manager in front for HTTPS.

## 1. Configure and start

| Option | What to set |
| --- | --- |
| `app_url` | The public address, e.g. `https://monica.example.nl`. Monica builds every link from it. |
| `force_url` | Keep `true` behind a proxy so links always use `app_url`, never the internal address. |
| `trusted_proxies` | `*` trusts the proxy in front (NPM) for `X-Forwarded-*` headers. |
| `disable_signup` | Keep `true`. The **first** account can always be created; this blocks any after it. |
| `mail_*` | Needed for reminder emails. `log` only writes them to the add-on log. |

Save, then start the add-on. The first start takes a minute or two: it creates
the database, runs Monica's migrations and generates its keys. It's ready when
the log shows `Monica v4.1.2 is set up, enjoy.`

## 2. Nginx Proxy Manager

Add a Proxy Host:

- **Domain:** the host from `app_url`
- **Scheme / Forward host / port:** `http`, your Home Assistant's LAN IP, `8181`
- **SSL:** request a Let's Encrypt certificate, enable *Force SSL* and *HTTP/2*
- **Advanced:** `client_max_body_size 50M;` so photo and document uploads work

Then browse to `app_url` and register: that first account becomes the owner.
If you don't need LAN access on `8181` any more, clear the port in the add-on's
Network section and point NPM at the add-on's hostname instead (shown on its
Info page, e.g. `xxxxxxxx-monica`, port `80`).

## Data and backups

Everything lives in the add-on's `/data`, so one add-on backup holds it all:
the database (`mysql/`), uploads, avatars and OAuth keys (`storage/`), and the
generated `APP_KEY`, `HASH_SALT` and database password.

The add-on uses **cold backups**: Home Assistant stops it for the few seconds
the backup takes, so the database files are always consistent. Monica is
briefly unavailable during your nightly backup.

Uninstalling the add-on deletes `/data`. Make a backup first, or export from
Monica (Settings → Export) if you want your data elsewhere.

## Notes

- The database only listens on a socket inside the add-on; it isn't reachable
  from your network or from other add-ons.
- Ingress (the HA sidebar) isn't supported: Monica can't run under a sub-path.
- Reminders run from the scheduler inside the add-on, once a minute.
- To move to a newer 4.x image later, change the `FROM` line in the Dockerfile
  and bump `version` in `config.yaml`; HA rebuilds it on update.
