import type { MetadataRoute } from "next";
import { SITE_URL } from "./site";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
      },
    ],
    sitemap: `${siteOrigin}/sitemap.xml`,
  };
}
