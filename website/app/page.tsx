"use client";

import { motion } from "framer-motion";
import { AppPreview, LogoMark } from "@/components/app-preview";
import { DownloadButton } from "@/components/download-button";
import { Bolt, GitHub, Shield, Wave } from "@/components/icons";
import { NeuralVeil } from "@/components/neural-veil";

const features = [
  { icon: Shield, number: "01", title: "Private by design", copy: "Your text and audio stay on your computer. No account, API key, or telemetry." },
  { icon: Wave, number: "02", title: "37 distinct voices", copy: "Uses Kokoro 82M to provide 37 voices across American and British English, plus eight more languages." },
  { icon: Bolt, number: "03", title: "Ready when you are", copy: "The complete engine ships inside the app. Generate MP3 or WAV without an internet connection." },
];

export default function Home() {
  return <main className="overflow-hidden bg-[#080807]">
    <section className="relative min-h-screen w-screen min-w-0 max-w-[100vw] overflow-hidden border-b border-white/8">
      <NeuralVeil/><div className="noise pointer-events-none absolute inset-0 opacity-[.07] mix-blend-soft-light"/><div className="grid-floor pointer-events-none absolute inset-x-0 bottom-0 h-[58%] opacity-70"/>
      <motion.nav initial={{ opacity: 0, y: -12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: .55, ease: [0.22, 1, 0.36, 1] }} className="relative z-20 mx-auto w-screen max-w-[min(100vw,80rem)] px-3 pt-4 sm:px-6 sm:pt-5">
        <div className="mx-auto flex h-14 max-w-4xl items-center justify-between rounded-2xl border border-white/10 bg-[#0a101b]/72 px-2.5 shadow-[0_12px_45px_rgba(0,0,0,.28),inset_0_1px_0_rgba(255,255,255,.05)] backdrop-blur-xl sm:px-3">
          <a href="#top" className="flex shrink-0 items-center gap-2.5 rounded-xl px-1.5 py-1 transition-colors hover:bg-white/[.04]" aria-label="Atten home"><LogoMark small/><span className="mono text-[11px] font-bold tracking-[.25em] text-[#dce8f5]">ATTEN</span></a>
          <div className="flex min-w-0 items-center gap-1">
            <a href="#features" className="hidden rounded-xl px-3 py-2 text-[13px] text-[#8fa2ba] transition-colors hover:bg-white/[.05] hover:text-[#e7eef8] sm:block">Features</a>
            <a href="https://github.com/jashdubal/atten" aria-label="View Atten source on GitHub" className="flex items-center gap-2 rounded-xl px-2.5 py-2 text-[13px] text-[#8fa2ba] transition-colors hover:bg-white/[.05] hover:text-[#e7eef8]"><GitHub className="size-[17px]"/><span className="hidden md:inline">Source</span></a>
            <span className="mx-1 hidden h-5 w-px bg-white/10 sm:block" aria-hidden="true"/>
            <DownloadButton compact/>
          </div>
        </div>
      </motion.nav>
      <div id="top" className="relative z-10 mx-auto min-w-0 w-screen max-w-[min(100vw,80rem)] px-5 pb-20 pt-16 text-center sm:px-8 sm:pt-20">
        <motion.div initial={{ opacity:0,y:12 }} animate={{ opacity:1,y:0 }} className="mono mx-auto mb-7 flex w-fit items-center gap-2 rounded-full border border-[#5ddbff]/25 bg-[#5ddbff]/8 px-3.5 py-1.5 text-[10px] tracking-[.16em] text-[#91e8ff] backdrop-blur-md"><i className="size-1.5 rounded-full bg-[#8fb996] shadow-[0_0_9px_#8fb996]"/> MAC · WINDOWS · COMMAND LINE</motion.div>
        <motion.h1 initial={{ opacity:0,y:20 }} animate={{ opacity:1,y:0 }} transition={{ delay:.08,duration:.7 }} className="text-balance mx-auto max-w-4xl text-[clamp(3.4rem,8vw,7.2rem)] font-semibold leading-[.9] tracking-[-.065em] text-white">Run local TTS<br/><span className="bg-gradient-to-r from-[#5ddbff] via-[#b7f2ff] to-[#9e70ff] bg-clip-text text-transparent">offline.</span></motion.h1>
        <motion.p initial={{ opacity:0 }} animate={{ opacity:1 }} transition={{ delay:.28,duration:.7 }} className="text-balance mx-auto mt-7 max-w-xl text-base leading-7 text-[#a7b6cc] sm:text-lg">Beautiful, natural text-to-speech that runs on your computer. No cloud. No subscription. Just press generate.</motion.p>
        <motion.div initial={{ opacity:0,y:15 }} animate={{ opacity:1,y:0 }} transition={{ delay:.42 }} className="mt-9"><DownloadButton/><p className="mono mt-3 text-[9px] tracking-[.12em] text-[#a3b4ca]">FREE & OPEN SOURCE · macOS 14+ APPLE SILICON · WINDOWS X64 PREVIEW</p></motion.div>
        <div className="mt-20 sm:mt-24"><AppPreview/></div>
      </div>
    </section>
    <section id="features" className="relative mx-auto max-w-7xl px-5 py-28 sm:px-8 sm:py-36"><div className="absolute left-1/2 top-1/2 -z-0 h-[500px] w-[900px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#5a2ec2]/8 blur-[120px]"/><div className="relative grid gap-12 lg:grid-cols-[.8fr_1.2fr] lg:gap-20"><div><p className="mono text-[10px] tracking-[.22em] text-[#5ddbff]">NO CLOUD REQUIRED</p><h2 className="text-balance mt-5 text-4xl font-semibold leading-tight tracking-[-.04em] text-white sm:text-5xl">A TTS studio that keeps to itself.</h2><p className="mt-5 max-w-md leading-7 text-[#8fa2ba]">Atten bundles its speech model and runs locally with Metal on Mac or CPU/CUDA-aware backend support on Windows. </p></div><div className="grid gap-px overflow-hidden rounded-2xl border border-white/10 bg-white/10 md:grid-cols-3">{features.map(({icon:Icon,number,title,copy},index) => <motion.article key={title} initial={{ opacity:0,y:24 }} whileInView={{ opacity:1,y:0 }} viewport={{ once:true,margin:"-60px" }} transition={{ delay:index*.1 }} className="group relative bg-[#0a101b] p-7 transition-colors hover:bg-[#111c2c]"><span className="mono text-[9px] tracking-widest text-[#657a96]">{number}</span><Icon className="mt-14 size-7 text-[#5ddbff] transition-transform duration-300 group-hover:-translate-y-1"/><h3 className="mt-5 text-lg font-semibold text-[#e7eef8]">{title}</h3><p className="mt-3 text-sm leading-6 text-[#8fa2ba]">{copy}</p></motion.article>)}</div></div></section>
    <section className="border-y border-white/8 bg-[#0a101b] px-5 py-24 sm:px-8"><motion.div initial={{ opacity:0,scale:.98 }} whileInView={{ opacity:1,scale:1 }} viewport={{ once:true }} className="relative mx-auto max-w-5xl overflow-hidden rounded-3xl border border-[#5ddbff]/20 bg-[#0e1726] px-6 py-16 text-center sm:px-16 sm:py-20"><div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(93,219,255,.16),transparent_52%)]"/><div className="noise absolute inset-0 opacity-[.045]"/><div className="relative"><LogoMark/><h2 className="mt-6 text-4xl font-semibold tracking-[-.04em] text-white sm:text-5xl">Keep your TTS local.</h2><p className="mx-auto mt-4 max-w-lg leading-7 text-[#8fa2ba]">Get Atten and keep your TTS workflows local.</p><div className="mt-8"><DownloadButton/></div><p className="mono mx-auto mt-5 max-w-xl text-[9px] leading-5 tracking-[.08em] text-[#8395ad]">Mac builds are ad-hoc signed and not yet Apple-notarized. Windows builds are preview packages for x64 systems.</p></div></motion.div></section>
    <footer className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-4 px-5 py-9 text-sm text-[#7f92aa] sm:flex-row sm:px-8"><div className="flex items-center gap-2"><LogoMark small/><span className="mono text-[10px] tracking-[.2em]">ATTEN</span></div><p>Local TTS for desktop and terminal.</p><a className="transition-colors hover:text-[#5ddbff]" href="https://github.com/jashdubal/atten">Source on GitHub ↗</a></footer>
  </main>;
}
