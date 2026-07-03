import { Container, getContainer } from "@cloudflare/containers";

export interface Env {
  OPENCODE: DurableObjectNamespace<OpenCode>;

  // Non-secret vars (wrangler.jsonc [vars]).
  OPENCODE_SERVER_USERNAME?: string;
  SYNC_INTERVAL?: string;

  // Secrets (wrangler secret put ...).
  OPENCODE_SERVER_PASSWORD?: string;
  R2_BUCKET?: string;
  R2_ENDPOINT?: string;
  R2_ACCESS_KEY_ID?: string;
  R2_SECRET_ACCESS_KEY?: string;
  ANTHROPIC_API_KEY?: string;
  OPENAI_API_KEY?: string;
  OPENROUTER_API_KEY?: string;
  GEMINI_API_KEY?: string;
}

export class OpenCode extends Container<Env> {
  defaultPort = 4096;

  // Scale-to-zero: shut the instance down after this idle period. Longer = more
  // responsive but higher cost when always-on; shorter = cheaper, more cold starts.
  sleepAfter = "15m";

  // Forward Worker secrets/vars into the container process. Field initializers
  // run after super(), so `this.env` is already populated here. opencode reads
  // the provider/auth vars; entrypoint.sh reads the R2_* vars for persistence.
  envVars = {
    OPENCODE_SERVER_USERNAME: this.env.OPENCODE_SERVER_USERNAME ?? "opencode",
    OPENCODE_SERVER_PASSWORD: this.env.OPENCODE_SERVER_PASSWORD ?? "",
    SYNC_INTERVAL: this.env.SYNC_INTERVAL ?? "60",
    R2_BUCKET: this.env.R2_BUCKET ?? "",
    R2_ENDPOINT: this.env.R2_ENDPOINT ?? "",
    R2_ACCESS_KEY_ID: this.env.R2_ACCESS_KEY_ID ?? "",
    R2_SECRET_ACCESS_KEY: this.env.R2_SECRET_ACCESS_KEY ?? "",
    ANTHROPIC_API_KEY: this.env.ANTHROPIC_API_KEY ?? "",
    OPENAI_API_KEY: this.env.OPENAI_API_KEY ?? "",
    OPENROUTER_API_KEY: this.env.OPENROUTER_API_KEY ?? "",
    GEMINI_API_KEY: this.env.GEMINI_API_KEY ?? "",
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // One shared instance ("main") => single writer to R2, no sync conflicts.
    // The container enforces basic auth via OPENCODE_SERVER_PASSWORD.
    return getContainer(env.OPENCODE, "main").fetch(request);
  },
} satisfies ExportedHandler<Env>;
