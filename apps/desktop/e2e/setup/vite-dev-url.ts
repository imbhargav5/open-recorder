/**
 * Resolves the base URL for the Vite dev server.
 *
 * Defaults to http://localhost:5789 (matching vite.config.ts server.port).
 * Override with the PLAYWRIGHT_BASE_URL environment variable when needed.
 */
export const VITE_BASE_URL =
  process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:5789";
