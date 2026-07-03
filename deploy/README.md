# Deploying the eyrie-flock stack to a VPS (Hetzner)

## Using Hetzner "Cloud config" (cloud-init) — fully automated

When creating the server, paste [`hetzner-cloud-init.yaml`](hetzner-cloud-init.yaml)
into the **Cloud config** field.

### Before pasting — 3 edits

Open the YAML and update these `write_files` entries at the top:

| File | What to put |
|---|---|
| `/etc/eyrie-flock-repo` | URL of your **git repo** containing the eyrie-flock project |
| `/etc/eyrie-flock-domain` | (optional) Your domain, e.g. `opencode.example.com` |
| `/etc/eyrie-flock-email` | (optional) ACME email for Let's Encrypt expiry notices |

Leave domain/email empty if you don't plan to use Caddy + HTTPS right away.
Paste the YAML and create the server.

### What happens at first boot

1. User `claw` + your SSH key, passwordless sudo, `docker` group
2. Docker Engine + compose plugin
3. SSH hardening (key-only, no root login) + `fail2ban`
4. UFW firewall (SSH only; app ports stay closed)
5. **Git clone** of eyrie-flock from your repo
6. `make setup` — generates `.env`, dirs, dedicated SSH key
7. `.env` is configured: correct PUID/PGID, random `OPENCODE_SERVER_PASSWORD`,
   domain/email (if provided)
8. Docker images are built
9. **Full stack starts**: opencode + Paperclip + OpenClaw
10. If domain was provided: Caddy starts with HTTPS, UFW opens 80/443

At the end the console prints all credentials — **copy them** (they won't be shown
again). The password is random and only ever written to `.env` on the server.

Without a domain, all services bind to `127.0.0.1` (localhost only). Reach them
via SSH tunnel:

```bash
ssh -L 4096:localhost:4096 -L 3100:localhost:3100 -L 18789:localhost:18789 claw@SERVER_IP
# then open http://localhost:4096 etc.
```

### Alternative: rsync (no git repo)

If you don't want to push a git repo, leave `/etc/eyrie-flock-repo` empty.
After the server boots, rsync the project over:

```bash
rsync -av --exclude node_modules --exclude .git \
  ./eyrie-flock/ claw@SERVER_IP:/home/claw/eyrie-flock/
```

Then SSH in and run the bootstrap manually:

```bash
ssh claw@SERVER_IP
sudo /home/claw/bootstrap-eyrie-flock.sh
```

> Do **not** put API keys or passwords in the cloud-init file — instance
> user-data is readable from metadata. All secrets are auto-generated on the
> server and printed to console once.

## Exposing the web UI for browser / mobile access

The firewall keeps port `4096` closed by default. Pick one:

1. **Caddy + automatic HTTPS (recommended)** — bundled. Caddy handles ACME
   (Let's Encrypt) certs automatically. Steps:

   ```bash
   # in .env set:  OPENCODE_DOMAIN=opencode.example.com   (and ACME_EMAIL=you@example.com)
   # DNS: point an A record for that domain at the server's IPv4.
   # Firewall: open 80/tcp and 443 (tcp+udp).
   make up-tls
   ```

   No domain? Use a wildcard-DNS hostname that maps to your IP, e.g.
   `123-200-12-34.sslip.io` — Let's Encrypt will issue for it. Caddy reaches
   opencode over the internal Docker network, so keep the default binding.
2. **Tailscale / WireGuard** — join the server to your private mesh and reach
   `http://100.x.x.x:4096`. Nothing exposed publicly.
3. **Cloudflare Tunnel** — `cloudflared` outbound tunnel, no open ports.
4. **Direct (quick, least safe)** — set `BIND_ADDR=0.0.0.0`, uncomment
   `ufw allow 4096/tcp` in the cloud-init (or run it manually), and **always**
   set `OPENCODE_SERVER_PASSWORD`. Note: plain HTTP — password travels
   unencrypted, so prefer option 1 or 2 for anything beyond a quick test.

## Note on the Hetzner Cloud Firewall

Hetzner also offers a separate **Cloud Firewall** (applied at the network edge,
configured in the console/API). It's a good extra layer on top of UFW — restrict
SSH to your IP there too.
