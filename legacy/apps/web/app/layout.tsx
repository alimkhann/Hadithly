import type { Metadata } from "next";
import { Amiri, Literata, Outfit } from "next/font/google";
import "./styles.css";

const outfit = Outfit({
  subsets: ["latin"],
  variable: "--font-outfit",
  display: "swap",
});
const literata = Literata({
  subsets: ["latin"],
  variable: "--font-literata",
  display: "swap",
});
const amiri = Amiri({
  subsets: ["arabic", "latin"],
  weight: ["400", "700"],
  variable: "--font-amiri",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Hadithly — Read hadith in your language",
  description:
    "A calm hadith reader with transparent AI-assisted translations into 30+ languages.",
  icons: {
    icon: "/brand/hadithly-logo-light.png",
    apple: "/brand/hadithly-logo-light.png",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${outfit.variable} ${literata.variable} ${amiri.variable}`}
    >
      <body>{children}</body>
    </html>
  );
}
