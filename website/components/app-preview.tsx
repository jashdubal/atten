"use client";

import { motion } from "framer-motion";
import { useEffect, useRef, useState } from "react";

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function AppPreview() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [isPlaying, setIsPlaying] = useState(true);

  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reducedMotion.matches) {
      videoRef.current?.pause();
      setIsPlaying(false);
    }
  }, []);

  function togglePlayback() {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      void video.play();
    } else {
      video.pause();
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 34, rotateX: 8 }}
      animate={{ opacity: 1, y: 0, rotateX: 0 }}
      transition={{ duration: .9, delay: .2, ease: [0.22, 1, 0.36, 1] }}
      className="group relative mx-auto min-w-0 w-full max-w-6xl [perspective:1400px]"
    >
      <div className="absolute -inset-12 -z-10 bg-[radial-gradient(ellipse,rgba(93,219,255,.16),rgba(126,60,255,.12),transparent_66%)] blur-2xl" />
      <div className="relative aspect-[1920/1184] overflow-hidden rounded-xl border border-[#5ddbff]/20 bg-black shadow-[0_45px_110px_rgba(0,0,0,.7),0_0_60px_rgba(93,219,255,.08)] sm:rounded-[18px]">
        <video
          ref={videoRef}
          autoPlay
          muted
          loop
          playsInline
          preload="metadata"
          poster={`${basePath}/atten-demo-poster.jpg`}
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          className="size-full object-cover"
          aria-label="Demonstration of Atten's Studio, Playground, Voices, Projects, and Exports"
        >
          <source src={`${basePath}/atten-demo.mp4`} type="video/mp4" />
        </video>
        <button
          type="button"
          onClick={togglePlayback}
          aria-label={isPlaying ? "Pause Atten demonstration" : "Play Atten demonstration"}
          aria-pressed={!isPlaying}
          className="absolute bottom-3 right-3 flex size-9 items-center justify-center rounded-full border border-white/15 bg-[#080c14]/80 text-xs text-white opacity-100 shadow-lg backdrop-blur-md transition hover:border-[#5ddbff]/40 hover:bg-[#101826] sm:bottom-5 sm:right-5 sm:opacity-0 sm:group-hover:opacity-100 sm:focus-visible:opacity-100"
        >
          <span aria-hidden="true">{isPlaying ? "Ⅱ" : "▶"}</span>
        </button>
      </div>
    </motion.div>
  );
}

export function LogoMark({ small = false }: { small?: boolean }) {
  return <span className={`relative inline-flex items-center justify-center rounded-[22%] border border-[#273852] bg-[#080c14] ${small ? "size-7" : "size-9"}`}><span className="absolute left-[21%] top-[30%] h-px w-[58%] bg-[#5ddbff]"/><span className="mono mt-2 text-[9px] font-bold text-[#e7eef8]">_</span></span>;
}
