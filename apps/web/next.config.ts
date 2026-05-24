import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: [
    "@hadithly/config",
    "@hadithly/design-tokens",
    "@hadithly/hadith-provider",
    "@hadithly/types",
    "@hadithly/validators"
  ]
};

export default nextConfig;
