import type { NextConfig } from "next";

const nextConfig = {
  turbopack: {
    root: process.cwd(),
  },
} satisfies NextConfig;

export default nextConfig;
