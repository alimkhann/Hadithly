#!/usr/bin/env bash
set -euo pipefail

hadithly_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hadithly_metadata="$hadithly_root/docs/app-store/en-US"

check_chars() {
  local label="$1"
  local file="$2"
  local maximum="$3"
  local count
  count="$(tr -d '\n' < "$file" | wc -m | tr -d ' ')"
  if (( count > maximum )); then
    echo "$label is $count characters; maximum is $maximum" >&2
    exit 1
  fi
}

check_chars "Name" "$hadithly_metadata/name.txt" 30
check_chars "Subtitle" "$hadithly_metadata/subtitle.txt" 30
check_chars "Promotional text" "$hadithly_metadata/promotional_text.txt" 170
check_chars "Description" "$hadithly_metadata/description.txt" 4000

hadithly_keyword_bytes="$(tr -d '\n' < "$hadithly_metadata/keywords.txt" | wc -c | tr -d ' ')"
if (( hadithly_keyword_bytes > 100 )); then
  echo "Keywords are $hadithly_keyword_bytes bytes; maximum is 100" >&2
  exit 1
fi

echo "App Store metadata limits passed."
