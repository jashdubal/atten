"use client";

import { motion, useMotionTemplate, useMotionValue } from "framer-motion";
import { useEffect, useState, type MouseEvent } from "react";
import { Apple, ArrowDown } from "./icons";

export const DOWNLOAD_URL = "https://github.com/jashdubal/atten/releases/latest/download/Atten-macOS-arm64.dmg";
const RELEASES_API_URL = "https://api.github.com/repos/jashdubal/atten/releases?per_page=100";
const DOWNLOAD_ASSET_NAME = "Atten-macOS-arm64.dmg";

let downloadCountRequest: Promise<number | null> | undefined;

function fetchDownloadCount() {
  downloadCountRequest ??= fetch(RELEASES_API_URL, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then(async (response) => {
      if (!response.ok) return null;

      const releases: unknown = await response.json();
      if (!Array.isArray(releases)) return null;

      let foundAsset = false;
      const total = releases.reduce((releaseTotal: number, release: unknown) => {
        if (!release || typeof release !== "object" || !("assets" in release) || !Array.isArray(release.assets)) return releaseTotal;

        return release.assets.reduce((assetTotal: number, asset: unknown) => {
          if (!asset || typeof asset !== "object" || !("name" in asset) || asset.name !== DOWNLOAD_ASSET_NAME || !("download_count" in asset) || typeof asset.download_count !== "number") return assetTotal;
          foundAsset = true;
          return assetTotal + asset.download_count;
        }, releaseTotal);
      }, 0);

      return foundAsset ? total : null;
    })
    .catch(() => null);

  return downloadCountRequest;
}

export function DownloadButton({ compact = false }: { compact?: boolean }) {
  const x = useMotionValue(120), y = useMotionValue(30);
  const [downloadCount, setDownloadCount] = useState<number | null>(null);
  const glow = useMotionTemplate`radial-gradient(110px circle at ${x}px ${y}px, rgba(255,255,255,.42), transparent 72%)`;
  function track(event: MouseEvent<HTMLAnchorElement>) { const rect = event.currentTarget.getBoundingClientRect(); x.set(event.clientX - rect.left); y.set(event.clientY - rect.top); }

  useEffect(() => {
    if (!compact) void fetchDownloadCount().then(setDownloadCount);
  }, [compact]);

  const button = <motion.a href={DOWNLOAD_URL} onMouseMove={track} whileHover={{ y: -2, scale: 1.012 }} whileTap={{ scale: .98 }} className={`group relative inline-flex overflow-hidden rounded-xl bg-[#5ddbff] font-semibold text-[#061018] shadow-[0_0_0_1px_rgba(145,232,255,.5),0_16px_50px_rgba(93,219,255,.2)] ${compact ? "items-center gap-2 px-3.5 py-2 text-[13px]" : "items-center gap-3 px-5 py-3.5"}`}><motion.span className="pointer-events-none absolute inset-0" style={{ background: glow }}/><Apple className={`relative ${compact ? "size-4" : "size-5"}`}/><span className="relative">{compact ? "Download" : "Download for Mac"}</span>{!compact && <ArrowDown className="relative ml-1 size-4 transition-transform duration-300 group-hover:translate-y-0.5"/>}</motion.a>;

  if (compact) return button;

  return <span className="inline-flex flex-col items-center">
    {button}
    {downloadCount !== null && <span className="mono mt-3 rounded-full border border-white/15 bg-[#0a101b]/80 px-3 py-1 text-[12px] font-semibold tracking-[.06em] text-[#dce8f5] shadow-[0_5px_18px_rgba(0,0,0,.22)] backdrop-blur-md" aria-live="polite">{downloadCount.toLocaleString()} {downloadCount === 1 ? "download" : "downloads"}</span>}
  </span>;
}
