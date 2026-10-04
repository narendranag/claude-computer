import { defineCloudflareConfig } from "@opennextjs/cloudflare";

// OpenNext's Cloudflare adapter: how a Next.js app runs on Workers (`just deploy`).
// Plain `wrangler deploy` cannot run Next.js on Workers. The default configuration has
// no incremental cache, tag cache or queue; add them when a page is slow enough to measure.
export default defineCloudflareConfig({});
