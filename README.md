# rTorrent + Flood — Install & Compile from Source for Ubuntu

A set of bash scripts to install and configure **rTorrent** (BitTorrent client) with **Flood** (modern web UI) on Ubuntu 20.04 / 22.04 / 24.04 VPS. Supports both a quick apt-based install and a full compile-from-source build using the latest rTorrent releases.

---

## Requirements

- Ubuntu 20.04, 22.04, or 24.04
- Root or sudo access
- VPS with a public IP
- Port **3000** open in your provider's firewall (DigitalOcean, Hetzner, Vultr, etc.)

---

## Scripts

| Script | Purpose |
|--------|---------|
| `install_rtorrent_flood.sh` | Quick install using `apt` (rTorrent 0.9.8) |
| `compile_rtorrent.sh` | Compile rTorrent + libtorrent from source (recommended) |
| `fix3.sh` | Fix connection refused, crashed services, socket issues |

---

## Option A — Compile from Source (recommended)

Compiles the latest rTorrent and libtorrent directly from the official GitHub releases. Gives you a much newer version than `apt` (0.15.x / 0.16.x vs the ancient 0.9.8 from 2019).

```bash
sudo bash compile_rtorrent.sh
```
or
```bash
curl -fsSL https://raw.githubusercontent.com/NamasteIndia/rtorrent-flood/refs/heads/main/compile_rtorrent.sh | sudo bash
```

On startup the script shows a version picker:

```
  Select a version to compile:

  Stable (recommended)
   1) 0.15.7  — Sep 2025  [latest stable] Most compatible with Flood
   2) 0.15.6  — Aug 2025  IPv4/6 handling improvements
   ...

  Development (bleeding edge)
   7) 0.16.6  — Jan 2026  [dev latest] Multi-threaded HTTP/session
   ...

  Enter number [1-10] (default: 1):
```

Press Enter to accept the default (0.15.7) or enter a number. The script then compiles both `libtorrent` and `rtorrent` from source using all available CPU threads.

### What gets compiled and installed

| Component | Version | Method |
|-----------|---------|--------|
| libtorrent (rakshasa) | same as rTorrent | compiled from source |
| rTorrent | your choice (default 0.15.7) | compiled from source |
| Node.js LTS | latest | NodeSource |
| Flood | latest | `npm -g` |
| screen | system | `apt` |

### Build dependencies installed automatically

`build-essential`, `automake`, `autoconf`, `libtool`, `pkg-config`, `libssl-dev`, `libcurl4-openssl-dev`, `libncurses5-dev`, `libsigc++-2.0-dev`, `libxmlrpc-c3-dev`, `screen`, `mediainfo`

### Build time

Approximately 3–6 minutes on a 2 vCPU VPS. Uses all available cores (`nproc`).

---

## Option B — Quick apt Install

Installs rTorrent 0.9.8 from the Ubuntu package repos. Faster but outdated.

```bash
sudo bash install_rtorrent_flood.sh
```

Prompts for a Flood username and password, then handles everything automatically.

---

## After Installation

1. Open your browser and go to `http://YOUR_SERVER_IP:3000`
2. On the Flood setup page, enter:
   - **Client type** → rTorrent
   - **Connection** → Socket
   - **Socket path** → `/var/run/rtorrent/rtorrent.sock`
3. Create your Flood account and click Connect

> **Note:** Do not use the `--rtorrent` or `--socket` flags when starting Flood. Let Flood connect to the existing rTorrent process via the browser setup page instead. This avoids the crash loop caused by Flood trying to spawn its own rTorrent.

---

## File Structure

```
/home/rtorrent/
├── downloads/          # Downloaded files
├── .session/           # rTorrent session data
└── .rtorrent.rc        # rTorrent configuration

/usr/local/bin/
└── rtorrent            # Compiled binary (compile_rtorrent.sh)

/usr/bin/
└── rtorrent            # apt binary (install_rtorrent_flood.sh)

/var/run/rtorrent/
└── rtorrent.sock       # SCGI socket — Flood connects here

/var/log/rtorrent/
└── rtorrent.log        # rTorrent log
```

---

## Service Management

```bash
# Check status
sudo systemctl status rtorrent
sudo systemctl status flood

# Restart
sudo systemctl restart rtorrent
sudo systemctl restart flood

# Stop
sudo systemctl stop flood
sudo systemctl stop rtorrent

# View live logs
journalctl -u rtorrent -f
journalctl -u flood -f
```

---

## Troubleshooting

### Browser shows "ERR_CONNECTION_REFUSED"

**Step 1 — Check services are running:**
```bash
systemctl is-active rtorrent flood
```

**Step 2 — Check Flood is listening on the right address:**
```bash
ss -tlnp | grep 3000
# Good: 0.0.0.0:3000
# Bad:  127.0.0.1:3000  (only accessible locally)
```

**Step 3 — Check your VPS provider's firewall.**
UFW alone is not enough. Open port **3000 TCP** in your provider's control panel:
- DigitalOcean → Networking → Firewalls → Inbound Rules
- Hetzner → Firewalls
- Vultr → Firewall Groups

**Step 4 — Run the fix script:**
```bash
sudo bash fix3.sh
```

---

### Flood crashes — "Address already in use"

Flood was launched with `--rtorrent --socket` flags, which tells it to manage rTorrent itself. It tries to start a second rTorrent, hits a port conflict, then kills everything and loops. `fix3.sh` removes those flags so Flood connects to the existing rTorrent via the browser setup page instead.

---

### rTorrent stuck on "activating"

The systemd service type was mismatched. `fix3.sh` rewrites it as `Type=forking` backed by `screen`, which is the most reliable method for rTorrent on Ubuntu.

---

### Flood says it cannot read `/home/rtorrent/downloads`

Fix ownership + directory permissions, then restart both services:

```bash
sudo chown -R rtorrent:rtorrent /home/rtorrent
sudo chmod 755 /home/rtorrent
sudo chmod 775 /home/rtorrent/downloads
sudo chmod 700 /home/rtorrent/.session
sudo systemctl restart rtorrent flood
```

---

### xmlrpc-c warning during compile

```
[!] --with-xmlrpc-c failed, compiling without xmlrpc-c...
```

This means `libxmlrpc-c3-dev` was not installed before the configure step ran. The updated `compile_rtorrent.sh` installs it automatically and detects the correct package name for your Ubuntu version. Re-running the script will pick it up.

---

### Version detection shows "invalid option"

```
/usr/local/bin/rtorrent: invalid option -- '-'
```

This is cosmetic — rTorrent does not support a `--version` flag. The binary is working correctly. The script falls back to reading the version from the compiled binary string table and reports the build version instead.

---

## Fix Script — fix3.sh

Fixes all known post-install issues in one run:

```bash
sudo bash fix3.sh
```

- Stops and kills any stuck rTorrent/Flood processes
- Rewrites `~/.rtorrent.rc` with correct socket and port config
- Rewrites the rTorrent systemd service (`Type=forking` + screen)
- Rewrites the Flood systemd service (correct `--host 0.0.0.0`, no `--rtorrent` flag)
- Waits for the SCGI socket before starting Flood
- Opens port 3000 in UFW and iptables
- Verifies Flood is listening on port 3000 before exiting

---

## Configuration

rTorrent config lives at `/home/rtorrent/.rtorrent.rc`. Key settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `network.port_range` | `50000-50000` | Incoming torrent port |
| `directory.default` | `/home/rtorrent/downloads` | Download directory |
| `throttle.global_up.max_rate` | `0` (unlimited) | Upload speed cap |
| `throttle.global_down.max_rate` | `0` (unlimited) | Download speed cap |
| `dht.mode` | `auto` | DHT for trackerless torrents |
| `network.scgi.open_local` | `/var/run/rtorrent/rtorrent.sock` | Flood socket path |

After editing, restart rTorrent:
```bash
sudo systemctl restart rtorrent
```

---

## Security Notes

- Flood runs on plain HTTP by default. For a public-facing server, put it behind Nginx with SSL (Let's Encrypt).
- The `rtorrent` system user has no login shell and owns only its own files.
- The SCGI socket is permission `770` — only the `rtorrent` user and group can access it.
- Consider changing the Flood port from 3000 to something less obvious if exposing to the internet.

---

## Tested On

- Ubuntu 22.04 LTS (2 vCPU / 8 GB Intel)
- Node.js v24 (NodeSource LTS)
- Flood v4.x (npm latest)
- rTorrent 0.15.7 compiled from source
- libtorrent 0.15.7 compiled from source
