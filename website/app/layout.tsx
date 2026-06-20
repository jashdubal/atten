import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Atten | Local TTS for Mac",
  description: "A native, fully offline text-to-speech studio for Apple Silicon Macs.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
