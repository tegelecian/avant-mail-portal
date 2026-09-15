# Moving the portal from Render to a VPS

Why: Render's network-attached persistent disk drops out for 30–75 min at a
time (six incidents Aug 20 – Sep 2 2026). SQLite on a VPS's local SSD does
not have that failure mode.

## 0. Before touching anything (Gary, in the browser)
1. Log in to https://avant-mail-portal.onrender.com and open
   https://avant-mail-portal.onrender.com/backup.zip — save the file.
   This is the full database + attachments. Keep it.
2. Render dashboard → avant-mail-portal → Environment: you'll copy these
   values into the server's `.env` (TENANT_ID, CLIENT_ID, CLIENT_SECRET,
   PORTAL_PASSWORD, PORTAL_USERS, FLASK_SECRET).

## 1. Buy / point a domain
Any registrar. Create an **A record** for the hostname (e.g.
`portal.yourdomain.com`) → the VPS's public IPv4. Caddy issues the HTTPS
certificate automatically once the record resolves.

## 2. Create the box
Any Ubuntu 24.04 VPS with 2 vCPU / 4 GB is plenty. **Done 2026-09-15:** Avant
provisioned a GoDaddy self-managed VPS (208.109.33.246, login `avantadmin`
with passwordless sudo — so prefix the commands below with `sudo` instead of
logging in as root). Weekly snapshots are on GoDaddy's side.

No domain yet? Use `208-109-33-246.sslip.io` as DOMAIN — sslip.io resolves
it to the IP for free and Caddy gets a real Let's Encrypt cert. Swap to the
real hostname later (see "Changing the domain").

## 3. Install
```
ssh root@<IP>
git clone https://github.com/tegelecian/avant-mail-portal.git /opt/portal
DOMAIN=portal.yourdomain.com bash /opt/portal/deploy/setup.sh
nano /opt/portal/.env        # paste the Render values; set PUBLIC_URL=https://portal.yourdomain.com
systemctl restart portal
```

## 4. Restore the data
Unzip the backup and drop its contents into `/opt/portal/data/`:
```
scp portal-backup-*.zip root@<IP>:/tmp/
ssh root@<IP> 'systemctl stop portal && cd /opt/portal/data && unzip -o /tmp/portal-backup-*.zip && chown -R portal:portal /opt/portal && systemctl start portal'
```
Then log in at https://portal.yourdomain.com and confirm campaigns,
contacts and templates are all there.

## 5. Prove it works
- Compose → "Send yourself a test" → real email arrives (TEST_SEND_REAL=true).
- Check `journalctl -u portal -n 50` shows `[watchdog] DB watchdog armed` and
  no tracebacks.
- Point UptimeRobot at https://portal.yourdomain.com/healthz with SMS/email
  alerts to Gary.

## 6. Cut over
- Tell Denise the new address (and update her bookmark).
- Suspend the Render service (Settings → Suspend) rather than deleting it
  for a week, in case anything was missed. Then delete.

## Changing the domain (e.g. when portal.avantrealestate.com exists)
```
sudo sed -i 's/^[^ ]* {/portal.avantrealestate.com {/' /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo sed -i 's#^PUBLIC_URL=.*#PUBLIC_URL=https://portal.avantrealestate.com#' /opt/portal/.env
sudo systemctl restart portal
```
Caddy issues the new certificate within seconds once the A record resolves.

## Day-to-day
- Logs: `journalctl -u portal -f`
- Update code: `sudo git -C /opt/portal pull && sudo systemctl restart portal`
- Nightly backups already land in `/opt/portal/data/backups/` (7 kept);
  the host's weekly snapshot covers the whole machine. A 2 GB swapfile was
  added by hand (not in setup.sh).
