# Mac reading and listening overhaul — unreleased candidate

Atten now opens in Library. Add a document, read while its narration is prepared,
and listen when the whole book is ready. Preparation can be stopped and resumed;
completed chapters survive interruption. Finishing preparation never starts
playback. Listening and reading positions are saved independently.

Library and Create replace the crowded primary navigation. Create brings drafts,
saved projects, export history, and voice previews together; model management
moves into Settings. Dark appearance uses muted neutral charcoal surfaces,
subtle borders, and restrained controls. The reader retains PDF layout and
collapsible reading tools.

One synthesis job runs at a time. Replacement narration preserves the previous
playable recording until the new output commits. Books can be exported as M4A.
Missing audio and failed preparation expose repair or resume actions.

The candidate is Developer ID signed. Notarization, clean-Mac installation, and
hardware acceptance remain release gates; this candidate has not been published.
See `docs/REDESIGN_ACCEPTANCE.md` and `DEPLOYMENT.md` before distributing it.
Existing IDs, projects, exports, settings, and CLI contracts are preserved.
Windows changes are outside this candidate.

---

# Previous published release notes

Atten is a fully offline, Apple Silicon-native text-to-speech studio for macOS
14 and newer. This release includes its Python 3.12 runtime, Kokoro, eSpeak NG,
all supported voices, and the pinned Kokoro-82M model. No separate Python,
Homebrew, model download, account, or network connection is required after the
DMG is downloaded.

## Install

1. Download `Atten-macOS-arm64.dmg` and compare its SHA-256 digest with
   `SHA256SUMS.txt`.
2. Open the DMG and drag Atten to Applications.
3. This release is ad-hoc signed, not Apple-notarized, so macOS blocks the
   first launch with "Apple could not verify Atten is free of malware".
   Double-click Atten, dismiss the warning, then open **System Settings →
   Privacy & Security**, scroll to Security, and choose **Open Anyway**. You do
   this once. On macOS 15 and newer this is the only route; the older
   Control-click → **Open** shortcut no longer works for applications that are
   not notarized.

Do not remove quarantine attributes. Future releases can migrate to Developer
ID signing and notarization without changing the stable download URL.

Source, license notices, the SPDX dependency manifest, and GitHub provenance
attestations are published beside the DMG.

## macOS durability work in this release

This release comes out of a testing pass aimed at one question: if you install
Atten today, will it still turn text into speech years from now, whatever you
do to it and whatever happens around it? Testing the packaged app rather than
the source found six ways the answer was no.

**Every voice Atten offers can now speak.** Twenty of the fifty-seven listed
voices could not produce audio at all. Japanese and Chinese voices failed on
phonemizer modules that are not bundled, Hindi voices on weights that were
never in the model, and the Arabic, German, Russian, Turkish, Dutch and Polish
voices reported that Hugging Face could not be reached — advice that cannot
help, and wrong, since Atten never needs the network to speak. Those voices now
name the single model that speaks them, and Atten tells you which one to
download and that the voice works offline from then on.

**A generation that stopped for no reason now explains itself.** macOS marks
everything inside a downloaded disk image, and a bundled speech engine still
carrying that mark is killed the moment Atten runs it — which looked like a
generation that simply stopped, reported as though you had cancelled it. Atten
now clears the mark from its own bundle at launch and, when macOS will not
allow that, says what to do.

**Long narrations no longer exhaust memory.** Audio segments were joined in
memory, so memory grew with the length of the text: joining twenty minutes of
speech cost over a gigabyte, and a book-length document could exhaust the
machine. Audio is now streamed to disk as it is made, and length costs nothing.

**An update can no longer leave you without Atten.** Installing an update
deleted the working app before putting the new one in place; if that failed,
neither was there. The old copy is now kept until the new one is installed and
restored if anything goes wrong, releases without published checksums are
refused rather than installed unverified, and an update is only opened if it
carries its engine and model. Update checks can also be turned off in Settings,
which leaves an installation that never uses the network at all.

**Damaged files are no longer quietly replaced.** Project history that could
not be read was left for the next save to overwrite. It is now set aside and
you are told where it went, entries that can still be read are kept, and
history and settings written by any version of Atten load whatever still
applies.

**Unhelpful errors were replaced with useful ones.** Long titles, emoji, and
punctuation in names no longer produce failures; an export folder that is
read-only, missing, or on a disconnected disk says so and names the folder; a
full disk says the disk is full; and text with nothing pronounceable in it says
that instead of reporting an internal error.

Every release build now proves the offline promise rather than assuming it: all
37 bundled voices are synthesized in both formats with no network reachable.

## Windows installation

Download `Atten-Windows-x64-Setup.exe` and run it. The guided installer checks
that the computer has 64-bit Windows 10 version 1809 or newer (or Windows 11),
8 GB RAM, and 4 GB free disk space before installation. It includes the local
speech engine, Kokoro model, Python runtime, .NET runtime, and Windows App SDK;
no separate dependency installation or internet connection is needed after the
installer is downloaded. The public Windows build uses CPU inference.
