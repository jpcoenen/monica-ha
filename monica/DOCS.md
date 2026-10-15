# Monica 4

Runs the official `monica:4.1.2-apache` image (the last 4.x release of
[monicahq/monica](https://github.com/monicahq/monica)) as a Home Assistant add-on,
with its database in the MariaDB add-on and HTTPS from Nginx Proxy Manager.

## 1. MariaDB add-on

Add a database and user to the MariaDB add-on's configuration, then restart it:

```yaml
databases:
  - monica
logins:
  - username: monica
    password: <a strong password>
rights:
  - username: monica
    database: monica
```

## 2. This add-on

| Option | What to set |
| --- | --- |
| `app_url` | The public address, e.g. `https://monica.example.nl`. Monica builds every link from it. |
| `force_url` | Keep `true` behind a proxy so links always use `app_url`, never the internal address. |
| `trusted_proxies` | `*` trusts the proxy in front (NPM) for `X-Forwarded-*` headers. |
| `disable_signup` | Keep `true`. The **first** account can always be created; this blocks any after it. |
| `db_*` | `core-mariadb`, port `3306`, and the database/user/password from step 1. |
| `mail_*` | Needed for reminder emails. `log` only writes them to the add-on log. |

Start the add-on. The first start takes a minute: it creates the tables and the
OAuth keys. Then open `http://<home-assistant-ip>:8181` once to check it's up.

## 3. Nginx Proxy Manager

Add a Proxy Host:

- **Domain:** the host from `app_url`
- **Scheme / Forward host / port:** `http`, your Home Assistant's LAN IP, `8181`
- **SSL:** request a Let's Encrypt certificate, enable *Force SSL* and *HTTP/2*
- **Advanced:** `client_max_body_size 50M;` so photo and document uploads work

Then browse to `app_url` and register: that first account becomes the owner.
If you don't need LAN access on `8181` any more, clear the port in the add-on's
Network section and point NPM at the add-on's hostname instead (shown on its
Info page, e.g. `local-monica`, port `80`).

## What's kept, and backups

`/data` (in add-on backups) holds `storage/` (uploads, avatars, logs, OAuth keys),
the generated `APP_KEY` and `HASH_SALT`. Back up the MariaDB add-on together with
this one; restoring one without the other leaves encrypted fields unreadable.

## Notes

- Ingress (the HA sidebar) isn't supported: Monica can't run under a sub-path.
- Reminders run from the scheduler inside the add-on, once a minute.
- To move to a newer 4.x image later, change the `FROM` line in the Dockerfile
  and bump `version` in `config.yaml`; HA rebuilds it on update.
