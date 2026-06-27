"use client";

import { useState } from "react";

export function CommandBlock({ children }: { children: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    await navigator.clipboard.writeText(children);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1500);
  }

  return <div className="group relative overflow-hidden rounded-xl border border-white/10 bg-[#070b12] shadow-[inset_0_1px_0_rgba(255,255,255,.03)]">
    <div className="flex h-9 items-center gap-1.5 border-b border-white/[.07] px-3" aria-hidden="true">
      <i className="size-1.5 rounded-full bg-[#ff6b6b]/70"/><i className="size-1.5 rounded-full bg-[#ffd166]/70"/><i className="size-1.5 rounded-full bg-[#8fb996]/70"/>
    </div>
    <pre className="whitespace-pre-wrap break-words px-4 py-4 pr-16 text-left"><code className="mono text-[12px] leading-6 text-[#c8d6e8] sm:text-[13px]">{children}</code></pre>
    <button type="button" onClick={() => void copy()} className="mono absolute right-2.5 top-11 rounded-md border border-white/10 bg-[#101826] px-2 py-1 text-[9px] tracking-[.08em] text-[#8fa2ba] transition hover:border-[#5ddbff]/35 hover:text-[#91e8ff]" aria-label="Copy command">
      {copied ? "COPIED" : "COPY"}
    </button>
  </div>;
}
