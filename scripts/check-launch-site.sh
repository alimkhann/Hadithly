#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
site_root="$repo_root/site"

if rg -n '\{\{[A-Z0-9_]+\}\}|example\.invalid|REQUIRED' "$site_root" \
  --glob '!assetlinks.template.json'; then
  echo "Launch site still contains publish-blocking placeholders." >&2
  exit 1
fi

jq -e '
  .applinks.details
  | length == 1
    and .[0].appIDs == ["6378AFQPXV.com.hadithly.app"]
    and .[0].components[0]["/"] == "/hadith/*"
' "$site_root/.well-known/apple-app-site-association" >/dev/null

if [[ ! -s "$site_root/.well-known/assetlinks.json" ]]; then
  echo "Android asset links remain blocked until a Play App Signing certificate exists." >&2
  exit 1
fi

jq -e '
  length == 1
    and .[0].relation == ["delegate_permission/common.handle_all_urls"]
    and .[0].target.namespace == "android_app"
    and .[0].target.package_name == "com.hadithly.app"
    and (.[0].target.sha256_cert_fingerprints | length) >= 1
    and (.[0].target.sha256_cert_fingerprints[] | test("^([0-9A-F]{2}:){31}[0-9A-F]{2}$"))
' "$site_root/.well-known/assetlinks.json" >/dev/null

for path in index.html privacy/index.html support/index.html delete-account/index.html terms/index.html hadith/index.html styles.css vercel.json; do
  test -s "$site_root/$path"
done

echo "Launch site checks passed."
