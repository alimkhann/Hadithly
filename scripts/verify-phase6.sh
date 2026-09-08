#!/usr/bin/env bash
set -euo pipefail

hadithly_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$hadithly_root/scripts/check-app-store-metadata.sh"

echo "Backend: typecheck"
(cd "$hadithly_root/backend" && npm run typecheck)

echo "Android: unit tests and debug build"
hadithly_java_home="${HADITHLY_JAVA_HOME:-}"
if [[ -z "$hadithly_java_home" ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
  hadithly_java_home="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
fi
if [[ -n "$hadithly_java_home" ]]; then
  (cd "$hadithly_root/android" && JAVA_HOME="$hadithly_java_home" ./gradlew testDebugUnitTest assembleDebug assembleRelease)
else
  (cd "$hadithly_root/android" && ./gradlew testDebugUnitTest assembleDebug assembleRelease)
fi

echo "iOS: regenerate project, build, and unit tests"
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required" >&2; exit 1; }
(cd "$hadithly_root/ios" && xcodegen generate)
hadithly_simulator_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/{print $2; exit}')"
test -n "$hadithly_simulator_id"
(cd "$hadithly_root/ios" && xcodebuild -quiet \
  -project Hadithly.xcodeproj \
  -scheme Hadithly \
  -destination "platform=iOS Simulator,id=$hadithly_simulator_id" \
  CODE_SIGNING_ALLOWED=NO \
  test)
(cd "$hadithly_root/ios" && xcodebuild -quiet \
  -project Hadithly.xcodeproj \
  -scheme Hadithly \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$hadithly_simulator_id" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build)

echo "Phase 6 local verification passed."
