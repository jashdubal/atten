import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Atten | Local TTS for Mac and Windows",
  description: "A native, fully offline text-to-speech studio for Mac, Windows, and the command line.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
