import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'export',
  // GitHub Pages (static hosting) serves /foo/ as /foo/index.html; avoid /foo.html URLs.
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
