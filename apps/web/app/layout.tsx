import type { Metadata } from "next";
import "./styles.css";

export const metadata: Metadata = {
  title: "Hadithly",
  description: "A calm hadith reader with transparent AI-assisted translations.",
  icons: {
    icon: "/brand/hadithly-logo-light.png",
    apple: "/brand/hadithly-logo-light.png"
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
