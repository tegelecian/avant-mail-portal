# Avant Mail Portal

An internal web portal for Avant Real Estate: upload a contact list (CSV or
Excel), write one email with merge fields like `{{FirstName}}`, attach the
flyer, and the portal sends an **individual, personalized email to each
contact** through your own Microsoft 365 account.

Because every message goes out through Microsoft Graph as a normal email from
the sender's mailbox:

- each recipient gets a one-to-one email addressed only to them,
- replies land straight in the sender's inbox,
- a copy of every send appears in the sender's **Sent Items**,
- no third-party email service is involved.

Other features: a saved **contact database** with named groups (upload once,
reuse forever — duplicates and invalid addresses are cleaned automatically),
**open and click tracking**, **reply detection** straight from the sender's
inbox (replies containing "unsubscribe" are added to the do-not-email list for
you, and bounces are flagged and suppressed), one-click **follow-up campaigns**
to everyone who hasn't responded, **scheduled launches**, a permanent
unsubscribe list, live progress with pause/resume, a "send myself a test"
button, per-recipient results export, automatic pacing under Microsoft's
sending limits, and a practice **dry-run mode** that simulates everything
without sending real email.

---

## 1. Quick start (practice mode — no email is sent)

Requirements: Python 3.10+ on any Windows / Mac / Linux machine.

```bash
pip install -r requirements.txt
cp .env.example .env        # on Windows: copy .env.example .env
python app.py
```

Open http://localhost:8080 — the team password is whatever `PORTAL_PASSWORD`
says in `.env` (change it!). The `.env.example` ships with `DRY_RUN=true`, so
you can create campaigns with `sample_contacts.csv` and `sample_body.txt`,
launch them, and watch the queue run without a single real email going out.

## 2. Connect Microsoft 365 (one-time, ~10 minutes, needs an M365 admin)

This registers the portal as an app in your Microsoft tenant so it can send
mail as your chosen mailbox.

1. Go to **entra.microsoft.com** → *App registrations* → **New registration**.
   Name it `Avant Mail Portal`, leave "single tenant" selected, no redirect
   URI needed. Register.
2. On the app's Overview page, copy **Application (client) ID** into
   `CLIENT_ID` and **Directory (tenant) ID** into `TENANT_ID` in `.env`.
3. *Certificates & secrets* → **New client secret** → copy the secret
   **Value** (not the ID) into `CLIENT_SECRET`. Note the expiry date and set a
   calendar reminder to renew it.
4. *API permissions* → **Add a permission** → *Microsoft Graph* →
   **Application permissions** → check **Mail.Send** and **Mail.Read** → Add.
   Then click **Grant admin consent** for your organization.
   (`Mail.Send` sends the campaigns; `Mail.Read` lets the portal spot replies,
   bounce notices, and "unsubscribe" requests in the sender's inbox. Skip
   `Mail.Read` if you don't want reply detection — everything else still works.)
5. **Important — limit which mailbox the app can use.** By default,
   application-level `Mail.Send` can send as *any* mailbox in the company.
   Restrict it to the sending mailbox with Exchange Online PowerShell:

   ```powershell
   Connect-ExchangeOnline
   New-ApplicationAccessPolicy -AppId <CLIENT_ID> `
     -PolicyScopeGroupId <mail-enabled security group containing the sender> `
     -AccessRight RestrictAccess -Description "Mail portal - sender only"
   ```

6. In `.env`, set `SENDER_EMAIL` (e.g. `dberdin@avantrealestate.com`),
   `SENDER_NAME`, and flip `DRY_RUN=false`. Restart `python app.py`.
7. Create a small campaign and use **Send yourself a test** before launching
   anything real.

## 3. Contacts: groups, checking and deduping

The **Contacts** page is the team's shared address book. Upload any CSV/Excel
file into a named group ("Gas & c-store prospects", "QSR tenants", …). Every
upload is validated, de-duplicated, and *merged* — uploading the same or an
overlapping list twice never creates doubles. When composing a campaign you
can either upload a one-off file or pick a saved group. Unsubscribed and
bounced addresses stay stored but are automatically excluded from every send.

## 4. Contact file format

CSV or Excel. The parser is flexible about headers — any of these work:

| Name            | Email              | Company (optional) |
|-----------------|--------------------|--------------------|
| Gill Berdin     | gill@example.com   | Avant Real Estate  |

or split names:

| First Name | Last Name | E-mail Address       |
|------------|-----------|----------------------|
| Tony       | Ramos     | tony@example.com     |

The portal automatically removes duplicates, skips invalid addresses, fixes
ALL-CAPS names, and excludes anyone on the unsubscribe list. You'll see the
counts on the review screen before anything sends.

**Merge fields** you can use in the subject or body:
`{{FirstName}}` `{{Name}}` `{{Company}}` `{{Email}}`
(If a contact has no name, `{{FirstName}}` falls back to "there".)

Plain-text bodies are formatted automatically — lines starting with `*` or
`-` become bullet points, exactly like the current listing emails.

## 5. Open & click tracking — how it works and its limits

Every email gets an invisible 1-pixel image and rewritten links that point
back at the portal, so opens and clicks can be recorded per contact.

- **This only works if the portal is reachable from the internet** (the
  recipient's mail app has to load the pixel from somewhere). Set `PUBLIC_URL`
  in `.env` to that address. The easy, free way without exposing your office
  network: a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
  pointing a hostname like `mail.avantrealestate.com` at the portal machine.
  Leave `PUBLIC_URL` blank and tracking simply stays off — sending, replies
  and follow-ups all still work.
- **Treat open rates as a rough signal, not truth.** Outlook often blocks
  images until the reader clicks "download pictures" (missed opens), while
  Apple Mail's privacy feature auto-loads images (fake opens). Clicks are much
  more reliable, and replies are the most reliable of all.

## 6. Replies, bounces and follow-ups

With `Mail.Read` granted, the portal checks the sender's inbox every
`REPLY_SCAN_MINUTES` (and on demand via the "Check inbox for replies now"
button). It matches messages to campaign contacts and:

- marks who **replied** (shown per contact and in the campaign stats),
- adds anyone whose reply contains **"unsubscribe"** to the do-not-email list
  automatically,
- detects **bounce notices**, flags the contact, and suppresses the dead
  address so future campaigns skip it.

Then use **"Follow up with the quiet ones"** on any campaign: it drafts a new
campaign targeting only the contacts who haven't replied (optionally: who also
never opened / never clicked). Bounced and unsubscribed contacts are always
excluded. You write a fresh subject and body, preview, test, and launch it
like any campaign. A polite follow-up 5–7 business days later is the sweet
spot — more than two follow-ups to a silent contact starts to hurt the
sender's reputation.

Campaigns can also be **scheduled**: pick a date and time on the campaign page
and the portal launches it automatically (the portal must be running at that
moment — another reason to keep it on an always-on machine).

## 7. Sending pace, limits and deliverability

- Microsoft 365 allows roughly **30 messages/minute** and **10,000
  recipients/day** per mailbox. The portal's defaults (`RATE_PER_MINUTE=20`,
  `DAILY_SEND_CAP=8000`) stay safely under both. If a campaign hits the daily
  cap it pauses itself and resumes after midnight automatically.
- A 3,000-contact campaign at 20/minute takes about 2.5 hours. Leave the
  portal running; you can close the browser tab.
- **Attachments are capped at ~3 MB total per email** (a Microsoft limit).
  For big flyers, upload the PDF to your website or OneDrive and put the link
  in the email — this is also much friendlier to spam filters.
- **Warm up.** Don't jump from ~50/day to 3,000/day overnight. Start with a
  few hundred to your cleanest, most-engaged contacts and step up over a week
  or two. High bounce or spam-complaint rates can get the mailbox or domain
  throttled by Microsoft.
- Confirm **SPF, DKIM and DMARC** are set up for avantrealestate.com (Defender
  portal → Email authentication settings → enable DKIM for the domain). Most
  M365 tenants have SPF already; DKIM often needs to be switched on once.

## 8. Staying legal (CAN-SPAM basics)

The portal helps with each of these, but they're the company's obligations:

- Only email people who have a genuine business relationship with Avant or
  gave you their contact info — not purchased/scraped lists.
- Every email must include a **physical postal address** and a **working way
  to opt out** — that's the footer the portal appends by default.
- When someone replies "unsubscribe" (or asks to stop), add them on the
  **Unsubscribes** page promptly (the law allows at most 10 business days).
  They're then excluded from every future campaign automatically, even if
  they're still in an uploaded list.
- Subject lines and the From name must be truthful.

## 9. Running it for the whole team

- Put it on an always-on office PC or a small VM. Others on the office
  network reach it at `http://<that-machine's-IP>:8080`.
- **Do not expose it to the public internet.** Keep it on the office
  network/VPN. Change `PORTAL_PASSWORD` in `.env` before the first real use.
- All data lives in the `data/` folder (a SQLite database plus uploaded
  attachments). Back it up by copying that folder.

## 10. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Test send fails with an auth error | Admin consent not granted (step 4), or wrong `CLIENT_SECRET` (copy the *Value*, not the ID) |
| `ErrorAccessDenied` on send | The application access policy (step 5) doesn't include the `SENDER_EMAIL` mailbox |
| Sends slow down on their own | Microsoft throttling (HTTP 429) — the portal waits and retries automatically |
| Everything worked, then stopped months later | The client secret expired — create a new one and update `.env` |
| "Check inbox" says the app can't read the inbox | `Mail.Read` permission not added/consented (step 4) |
| Opens/clicks stay at zero | `PUBLIC_URL` not set, or that address isn't reachable from the internet (see §5) |

## Ideas for later

- Per-contact extra merge fields (e.g. a Property column).
- Per-link click breakdown (which link in the email was clicked).
- A/B testing two subject lines on a small slice before the full send.
