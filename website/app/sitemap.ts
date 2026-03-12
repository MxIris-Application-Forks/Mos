import type { MetadataRoute } from "next";
import { SITE_URL } from "./site";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const siteOrigin = SITE_URL.toString().replace(/\/$/, "");

  return [
    {
      url: `${siteOrigin}/`,
      changeFrequency: "monthly",
      priority: 1,
    },
  ];
}
