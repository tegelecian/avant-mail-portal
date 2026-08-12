# Avant Mail Merge Portal

Internal web portal for Avant Real Estate (CRE brokerage, Pomona CA). Brokers
upload a contact list, write one email with merge fields, attach flyers, and
the portal sends one personalized email per contact from the broker's real
Microsoft 365 mailbox via the Graph API — so replies land in their inbox and
copies appear in Sent Items.

## Stack & layout

- Single-file Flask app: `app.py` (~1,100 lines). No JS framework — Jinja
  templates in `templates/`, one stylesheet in `static/style.css`.
- SQLite in `data/portal.db` (WAL mode). `data/` is created at boot and is
  disposable in dev.
- Background sender: one daemon thread (`worker_loop`) started at import.
  It paces sends (RATE_PER_MINUTE), enforces DAILY_SEND_CAP, promotes
  scheduled campaigns, and auto-scans the inbox for replies.
- Microsoft Graph, client-credentials flow (MSAL). Permissions: `Mail.Send`
  (send) and `Mail.Read` (reply/bounce detection). Config in `.env`.

## Running it

```
pip install -r requirements.txt
cp .env.example .env       # first time only
python app.py              # http://localhost:8080, password from .env
```

- **`DRY_RUN=true` (the default) simulates sends — no Graph calls, no email.**
  Keep it true for all development. Only flip to false with real Azure
  credentials in `.env` when actually deploying.
- `.env` holds secrets. Never commit it; never print its values.

## Key concepts

- Campaign lifecycle: draft → (scheduled) → sending → paused/completed/cancelled.
  Status lives on the `campaigns` row; the worker picks up `sending` rows.
- Recipients each get a `token` (uuid hex) used by the tracking endpoints
  `/t/<token>.gif` (open pixel) and `/c/<token>?u=` (click redirect). These
  two routes plus `/login`, `/healthz`, `/static/` are the ONLY unauthenticated
  routes — keep it that way.
- Tracking only activates when `PUBLIC_URL` is set (recipients' mail apps
  must reach it from the internet, e.g. via Cloudflare Tunnel). Previews and
  test sends must never include tracking (`with_tracking=False`).
- Suppression list (`suppression` table) is checked at parse time AND again at
  send time. Bounces and "unsubscribe" replies are auto-added by
  `apply_inbox_messages()` — that function is pure over Graph message dicts so
  it can be tested without a mailbox.
- Contact groups: `contact_groups` + `contacts` (UNIQUE(group_id, email));
  uploads merge idempotently.
- Merge fields: `{{FirstName}}`, `{{Name}}`, `{{Company}}`, `{{Email}}` via
  `personalize()`. Plain-text bodies go through `plain_to_html()` (bullets,
  autolinked URLs).

## Gotchas learned the hard way

- DB access is ONLY via the `db()` context manager (commit/rollback/close,
  busy_timeout). Never hold a connection across `time.sleep()` — that caused
  "database is locked" errors. WAL is set once at startup in `_init_wal()`.
- When restarting the dev server, kill the old process first or the new one
  dies on the busy port while the stale one keeps serving old code
  (`fuser -k 8080/tcp` or kill by PID — beware `pkill -f app.py` matching
  your own shell).
- Graph attachment limit: ~4 MB per request, so the portal caps attachments
  at 3 MB total. Bigger flyers should be links instead.
- Exchange Online limits: ~30 msgs/min, 10k recipients/day per mailbox —
  RATE_PER_MINUTE and DAILY_SEND_CAP must stay under those.

## Testing conventions

End-to-end tests are curl against a dry-run server (see README §10 for
troubleshooting). Typical smoke test: login → upload contacts to a group →
create campaign from group → launch → poll `status.json` → hit `/t/` and `/c/`
with recipient tokens → feed fake message dicts to `apply_inbox_messages()` →
create a follow-up and confirm it targets only non-repliers.

## House rules

- CAN-SPAM: every email carries the physical-address footer and an
  unsubscribe path. Don't remove or default-off the footer.
- Don't add features that mass-email people who unsubscribed or bounced —
  filters in `create_followup()` and the worker's send-time suppression check
  are load-bearing compliance code.
- Keep the UI in the existing style (pine/parcel-yellow palette, Archivo +
  IBM Plex Mono) — templates share `base.html`.
