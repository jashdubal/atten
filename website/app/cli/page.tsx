import type { Metadata } from "next";
import Link from "next/link";
import { LogoMark } from "@/components/app-preview";
import { CommandBlock } from "@/components/command-block";
import { ArrowRight, GitHub, Terminal } from "@/components/icons";
import { NeuralVeil } from "@/components/neural-veil";

export const metadata: Metadata = {
  title: "Atten CLI | Local text-to-speech from your terminal",
  description: "Install and use Atten's offline text-to-speech command-line interface.",
};

const examples = [
  {
    number: "01",
    title: "Speak some text",
    copy: "Generate an MP3 in the outputs folder with the default voice.",
    command: 'uv run cli.py "Living the dream"',
  },
  {
    number: "02",
    title: "Read a document",
    copy: "Choose a voice and speed, export a WAV, then play it when finished.",
    command: "uv run cli.py -f notes.txt -v bf_emma -s 1.1 --format wav --play",
  },
  {
    number: "03",
    title: "Name the output",
    copy: "Set a filename and suppress status messages for scripts.",
    command: 'uv run cli.py "Hello" --filename greeting --silent',
  },
];

export default function CliGuide() {
  return <main className="min-h-screen overflow-hidden bg-[#080807]">
    <section className="relative overflow-hidden border-b border-white/8">
      <div className="absolute inset-0 opacity-65"><NeuralVeil/></div>
      <div className="noise pointer-events-none absolute inset-0 opacity-[.06] mix-blend-soft-light"/>
      <nav className="relative z-20 mx-auto w-full max-w-5xl px-4 pt-5 sm:px-6">
        <div className="flex h-14 items-center justify-between rounded-2xl border border-white/10 bg-[#0a101b]/72 px-3 shadow-[0_12px_45px_rgba(0,0,0,.28),inset_0_1px_0_rgba(255,255,255,.05)] backdrop-blur-xl">
          <Link href="/" className="flex items-center gap-2.5 rounded-xl px-1.5 py-1 transition-colors hover:bg-white/[.04]" aria-label="Atten home"><LogoMark small/><span className="mono text-[11px] font-bold tracking-[.25em] text-[#dce8f5]">ATTEN</span></Link>
          <div className="flex items-center gap-1">
            <Link href="/" className="rounded-xl px-3 py-2 text-[13px] text-[#8fa2ba] transition-colors hover:bg-white/[.05] hover:text-[#e7eef8]">← Back to site</Link>
            <a href="https://github.com/jashdubal/atten" aria-label="View Atten source on GitHub" className="flex items-center gap-2 rounded-xl px-2.5 py-2 text-[13px] text-[#8fa2ba] transition-colors hover:bg-white/[.05] hover:text-[#e7eef8]"><GitHub className="size-[17px]"/><span className="hidden sm:inline">Source</span></a>
          </div>
        </div>
      </nav>
      <div className="relative z-10 mx-auto max-w-4xl px-5 pb-20 pt-20 text-center sm:px-8 sm:pb-24 sm:pt-24">
        <div className="mono mx-auto flex w-fit items-center gap-2 rounded-full border border-[#5ddbff]/25 bg-[#5ddbff]/8 px-3.5 py-1.5 text-[10px] tracking-[.16em] text-[#91e8ff] backdrop-blur-md"><Terminal className="size-3.5"/> COMMAND LINE</div>
        <h1 className="text-balance mx-auto mt-7 max-w-3xl text-[clamp(3rem,8vw,6rem)] font-semibold leading-[.92] tracking-[-.06em] text-white">Atten, from your <span className="bg-gradient-to-r from-[#5ddbff] via-[#b7f2ff] to-[#9e70ff] bg-clip-text text-transparent">terminal.</span></h1>
        <p className="text-balance mx-auto mt-6 max-w-xl text-base leading-7 text-[#a7b6cc] sm:text-lg">Generate natural speech locally from scripts, automations, or a single command. No account or API key.</p>
      </div>
    </section>

    <section className="relative mx-auto max-w-4xl px-5 py-20 sm:px-8 sm:py-28">
      <div className="absolute left-1/2 top-52 -z-0 h-96 w-[44rem] -translate-x-1/2 rounded-full bg-[#5a2ec2]/8 blur-[110px]"/>
      <div className="relative">
        <p className="mono text-[10px] tracking-[.22em] text-[#5ddbff]">QUICK START</p>
        <div className="mt-4 grid gap-8 lg:grid-cols-[.82fr_1.18fr] lg:gap-14">
          <div>
            <h2 className="text-3xl font-semibold tracking-[-.04em] text-white sm:text-4xl">Set up once. Speak locally.</h2>
            <p className="mt-4 text-sm leading-6 text-[#8fa2ba]">You need <a className="text-[#91e8ff] underline decoration-[#5ddbff]/30 underline-offset-4 hover:decoration-[#5ddbff]" href="https://git-scm.com/downloads">Git</a> and <a className="text-[#91e8ff] underline decoration-[#5ddbff]/30 underline-offset-4 hover:decoration-[#5ddbff]" href="https://docs.astral.sh/uv/getting-started/installation/">uv</a>. Atten uses its own pinned Python 3.12 environment, so it will not modify your system packages.</p>
            <p className="mt-4 rounded-xl border border-[#5ddbff]/15 bg-[#5ddbff]/[.05] px-4 py-3 text-xs leading-5 text-[#9eb2ca]"><span className="font-semibold text-[#91e8ff]">First run:</span> the model and selected voice are downloaded once. After they are cached, generation works offline.</p>
          </div>
          <div>
            <CommandBlock>{`git clone https://github.com/jashdubal/atten.git
cd atten
uv python install 3.12
uv sync --frozen
uv run cli.py "Hello from Atten"`}</CommandBlock>
            <p className="mono mt-3 text-[10px] leading-5 tracking-[.04em] text-[#71849d]">macOS · Windows PowerShell · Linux</p>
          </div>
        </div>
      </div>
    </section>

    <section className="border-y border-white/8 bg-[#0a101b] px-5 py-20 sm:px-8 sm:py-24">
      <div className="mx-auto max-w-5xl">
        <div className="max-w-xl"><p className="mono text-[10px] tracking-[.22em] text-[#5ddbff]">EVERYDAY COMMANDS</p><h2 className="mt-4 text-3xl font-semibold tracking-[-.04em] text-white sm:text-4xl">Text in. Audio out.</h2></div>
        <div className="mt-10 grid gap-4 lg:grid-cols-3">{examples.map((example) => <article key={example.number} className="rounded-2xl border border-white/10 bg-[#0e1726] p-5 shadow-[inset_0_1px_0_rgba(255,255,255,.03)]">
          <span className="mono text-[9px] tracking-widest text-[#657a96]">{example.number}</span>
          <h3 className="mt-5 text-lg font-semibold text-[#e7eef8]">{example.title}</h3>
          <p className="mb-5 mt-2 min-h-12 text-sm leading-6 text-[#8fa2ba]">{example.copy}</p>
          <CommandBlock>{example.command}</CommandBlock>
        </article>)}</div>
      </div>
    </section>

    <section className="mx-auto grid max-w-5xl gap-10 px-5 py-20 sm:px-8 sm:py-24 lg:grid-cols-[.72fr_1.28fr]">
      <div><p className="mono text-[10px] tracking-[.22em] text-[#5ddbff]">DISCOVER & AUTOMATE</p><h2 className="mt-4 text-3xl font-semibold tracking-[-.04em] text-white">Useful controls.</h2><p className="mt-4 text-sm leading-6 text-[#8fa2ba]">Device selection defaults to the best available option: Metal on Mac, CUDA where supported, then CPU.</p></div>
      <div className="space-y-4">
        <CommandBlock>{`# Browse every installed voice
uv run cli.py --list-voices

# Inspect the selected accelerator
uv run cli.py --backend-info --device auto

# Emit machine-readable events
uv run cli.py "Hello" --json

# See every flag
uv run cli.py --help`}</CommandBlock>
        <p className="text-xs leading-5 text-[#71849d]">On macOS or Linux, you can use the shorter <code className="mono text-[#a7b6cc]">bin/tts</code> wrapper in place of <code className="mono text-[#a7b6cc]">uv run cli.py</code>.</p>
      </div>
    </section>

    <section className="border-t border-white/8 px-5 py-16 sm:px-8">
      <div className="mx-auto flex max-w-4xl flex-col items-center justify-between gap-5 rounded-2xl border border-[#5ddbff]/20 bg-[#0e1726] px-6 py-8 text-center shadow-[inset_0_1px_0_rgba(255,255,255,.04)] sm:flex-row sm:text-left">
        <div><h2 className="text-xl font-semibold text-white">Need the full reference?</h2><p className="mt-1 text-sm text-[#8fa2ba]">Flags, voices, development setup, and backend details live in the repository.</p></div>
        <a href="https://github.com/jashdubal/atten#command-line" className="group inline-flex shrink-0 items-center gap-2 rounded-xl bg-[#5ddbff] px-4 py-3 text-sm font-semibold text-[#061018] transition hover:bg-[#91e8ff]">Open the docs <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5"/></a>
      </div>
    </section>

    <footer className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-4 px-5 py-9 text-sm text-[#7f92aa] sm:flex-row sm:px-8"><Link href="/" className="flex items-center gap-2"><LogoMark small/><span className="mono text-[10px] tracking-[.2em]">ATTEN</span></Link><p>Local TTS, however you work.</p><a className="transition-colors hover:text-[#5ddbff]" href="https://github.com/jashdubal/atten">Source on GitHub ↗</a></footer>
  </main>;
}
