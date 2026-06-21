# 🧳 Trip Planner

A cozy, self-hosted website for planning trips with your friends. You run it on
your own Windows PC, log in, and add trips with itineraries, packing lists,
budgets, and booking links. **Only people you give an account to can see it.**

![editions](https://img.shields.io/badge/runs%20on-Node.js-339933) ![auth](https://img.shields.io/badge/access-friends%20only-ff8a5b)

---

## ✨ What you get

- **Pretty trip board** — each trip is a card with a colour theme, emoji, dates, and a live countdown.
- **Rich trip pages** — overview, day-by-day itinerary, packing checklist (tick items off live), budget, who's coming, links/bookings, and free-form notes.
- **Add / edit everything in the browser** — no code needed once it's running.
- **Friends-only login** — passwords are hashed; the first account is the owner (you); friends join with an invite code.
- **On / off buttons** — `Start Trip Planner.bat` and `Stop Trip Planner.bat`.
- **No database to install** — everything saves to a single `data/db.json` file.

---

## 🚀 Quick start (Windows)

1. **Install Node.js** (one time): get the **LTS** version from <https://nodejs.org> and run the installer.
2. **Double-click `Start Trip Planner.bat`.**
   - The first run installs dependencies automatically (needs internet).
   - A server window opens and your browser pops up at **http://localhost:4040**.
3. **Create your owner account.** The first account you make becomes the **owner** — no invite code needed.
4. Start adding trips with the **＋ New trip** button.
5. **To turn it off:** double-click **`Stop Trip Planner.bat`** (or just close the server window).

> Mac/Linux: run `npm install` then `npm start` in this folder.

---

## 👯 Letting your friends in

Your friends need two things:

1. **The invite code.** The default is `letmein` — **change it!** Edit (or create) a file
   called `.env` next to `server.js` containing:
   ```
   INVITE_CODE=our-secret-2026
   ```
   (See `.env.example`.) Then restart the server.
2. **Your computer's address on the network.** When the server starts, the window prints something like:
   ```
   On your network:   http://192.168.1.50:4040
   ```
   Give your friends that link. They open it, click **Create account**, and enter the invite code.

### Friends connecting from the same Wi-Fi
That `http://192.168.x.x:4040` link works for anyone on your home Wi-Fi.
The **first time**, Windows may ask to allow Node.js through the firewall — click **Allow** (Private networks).

### Friends connecting over the internet (optional)
To reach it from outside your home you'd need to forward port `4040` on your
router to your PC, or use a tunnel like [Tailscale](https://tailscale.com) or
[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).
A tunnel is the safer, easier option and doesn't expose your home IP.

---

## ✍️ Want me (Claude) to add your trips for you?

Just give me the trip details and I'll drop them straight into the site. Under the
hood that uses the importer:

```sh
node scripts/import-trips.js my-trips.json
```

See `trips.sample.json` for the format (a single trip object or an array of them).
Re-running is safe — trips with the same title + start date are skipped. You can
always tweak them afterwards in the browser.

---

## ⚙️ Configuration

Everything has sensible defaults. To override, create a `.env` file (see `.env.example`):

| Variable      | Default   | What it does                              |
|---------------|-----------|-------------------------------------------|
| `PORT`        | `4040`    | Port the website runs on.                 |
| `INVITE_CODE` | `letmein` | Code friends enter once when registering. |

---

## 🗂️ Where your data lives

Everything is stored locally in the **`data/`** folder (which is git-ignored, so it
never gets committed or shared):

- `data/db.json` — your accounts and all trips.
- `data/sessions/` — keeps you logged in across restarts.
- `data/session.secret`, `data/server.pid` — internal.

**To back up**, copy the `data/` folder somewhere safe. To start fresh, delete it.

---

## 🔒 A note on security

This is a personal app for you and friends, not a hardened public service. It uses
hashed passwords, http-only session cookies, and an invite code, which is plenty for
a home setup. If you ever expose it to the open internet, put it behind HTTPS (a
tunnel or reverse proxy) rather than opening your router straight to it.

---

## 🛠️ Project layout

```
trip-planner/
├─ Start Trip Planner.bat   # on button
├─ Stop Trip Planner.bat    # off button
├─ server.js                # Express app
├─ lib/                     # config, JSON store, auth middleware
├─ routes/                  # /api/auth and /api/trips
├─ public/                  # the website (HTML/CSS/JS)
├─ scripts/import-trips.js  # bulk-add trips from JSON
└─ data/                    # your saved data (auto-created, git-ignored)
```
