# opencode on Cloudflare Containers (with R2 persistence)

Deploy opencode as a Cloudflare Container fronted by a Worker, with configuration,
API keys and sessions persisted to **R2** (because the container's local disk is
ephemeral and wiped on every restart/sleep/redeploy).

```
Browser / mobile ──HTTPS──> Worker ──> Container (opencode serve :4096)
                                              │  restore on boot / sync every 60s / flush on SIGTERM
                                              ▼
                                          R2 bucket  (config + data)
```

## Why R2 is required

Unlike the Docker Compose setup (which bind-mounts `./config` and `./data`),
Cloudflare Containers have **no durable local disk**. Without external storage,
you'd lose your API keys and sessions on every cold start. `entrypoint.sh`
mirrors `~/.config/opencode` and `~/.local/share/opencode` to R2:

- **on boot** → restore from R2,
- **every `SYNC_INTERVAL` seconds** → push changes,
- **on `SIGTERM`** (before sleep/redeploy) → final flush.

A single instance runs (`max_instances: 1` + one `"main"` name), so there is one
writer and no sync conflicts.

## Prerequisites

- A Cloudflare account on the **Workers Paid** plan ($5/mo — required for Containers).
- `node` + `npm`, and Docker running locally (Wrangler builds the image).
- Wrangler logged in: `npx wrangler login`.

## 1. Install deps

```bash
cd cloudflare
npm install
```

## 2. Create the R2 bucket + credentials

```bash
npx wrangler r2 bucket create opencode-state
```

Then create an **R2 API token** (S3 credentials) in the Cloudflare dashboard:
R2 → Manage R2 API Tokens → Create (Object Read & Write). Note the
**Access Key ID**, **Secret Access Key**, and your account's S3 endpoint
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`.

## 3. Set secrets

```bash
npx wrangler secret put OPENCODE_SERVER_PASSWORD    # protects the web UI
npx wrangler secret put R2_BUCKET                   # e.g. opencode-state
npx wrangler secret put R2_ENDPOINT                 # https://<ACCOUNT_ID>.r2.cloudflarestorage.com
npx wrangler secret put R2_ACCESS_KEY_ID
npx wrangler secret put R2_SECRET_ACCESS_KEY

# Optional: bake in provider keys instead of `opencode auth login`
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put OPENAI_API_KEY
```

## 4. Deploy

```bash
npm run deploy
```

Wrangler builds the image, pushes it, and deploys the Worker. Open the printed
`*.workers.dev` URL (or attach a custom domain). Log in with user `opencode`
(or `OPENCODE_SERVER_USERNAME`) + your password.

To configure providers after deploy, use the web UI's auth flow, or run
`opencode auth login` locally, then upload the resulting files once:

```bash
rclone copy ~/.local/share/opencode r2:opencode-state/data
rclone copy ~/.config/opencode      r2:opencode-state/config
```

## Tuning

- **Cost vs responsiveness**: `sleepAfter` in `src/index.ts` (default `15m`).
  Shorter = cheaper, more cold starts. See the cost analysis in the parent README.
- **Instance size**: `instance_type` in `wrangler.jsonc` (`basic` = 1 GiB / 0.25 vCPU).
  Bump to `standard-1` for heavier tool use (builds/tests), at higher cost.
- **Sync frequency**: `SYNC_INTERVAL` var (seconds).

## Caveats

- **Cold starts**: after sleeping, the next request restores state from R2 and
  boots opencode (a few seconds; more if `opencode.db` is large).
- **0.25 vCPU** is weak for running builds/tests inside the agent's tools.
- **LLM token costs are separate** and paid to the model provider.
- For stronger auth than basic-auth, put **Cloudflare Access** in front of the Worker.
- Robust SQLite replication: consider swapping the whole-file rclone sync for
  [Litestream](https://litestream.io) on `opencode.db` if you write heavily.

## Files

```
cloudflare/
├── wrangler.jsonc     # Worker + container + Durable Object config
├── src/index.ts       # Worker: routes to the container; injects secrets
├── Dockerfile         # image: node + opencode + rclone
├── entrypoint.sh      # R2 restore / periodic sync / flush on SIGTERM
├── package.json
└── tsconfig.json
```
