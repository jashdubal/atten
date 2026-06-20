"use client";

import { motion, useMotionTemplate, useMotionValue } from "framer-motion";
import type { MouseEvent } from "react";
import { Apple, ArrowDown } from "./icons";

export const PLACEHOLDER_DOWNLOAD = "https://example.com/Atten-macOS-arm64.dmg";
export function DownloadButton({ compact = false }: { compact?: boolean }) {
  const x = useMotionValue(120), y = useMotionValue(30);
  const glow = useMotionTemplate`radial-gradient(110px circle at ${x}px ${y}px, rgba(255,255,255,.42), transparent 72%)`;
  function track(event: MouseEvent<HTMLAnchorElement>) { const rect = event.currentTarget.getBoundingClientRect(); x.set(event.clientX - rect.left); y.set(event.clientY - rect.top); }
  return <motion.a href={PLACEHOLDER_DOWNLOAD} onMouseMove={track} whileHover={{ y: -2, scale: 1.012 }} whileTap={{ scale: .98 }} className={`group relative inline-flex overflow-hidden rounded-xl bg-[#5ddbff] font-semibold text-[#061018] shadow-[0_0_0_1px_rgba(145,232,255,.5),0_16px_50px_rgba(93,219,255,.2)] ${compact ? "items-center gap-2 px-3.5 py-2 text-[13px]" : "items-center gap-3 px-5 py-3.5"}`}><motion.span className="pointer-events-none absolute inset-0" style={{ background: glow }}/><Apple className={`relative ${compact ? "size-4" : "size-5"}`}/><span className="relative">{compact ? "Download" : "Download for Mac"}</span>{!compact && <ArrowDown className="relative ml-1 size-4 transition-transform duration-300 group-hover:translate-y-0.5"/>}</motion.a>;
}
