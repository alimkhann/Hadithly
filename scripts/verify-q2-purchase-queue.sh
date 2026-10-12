#!/usr/bin/env bash
# Real app manager, deterministic SDK/Clerk transport. This is not store sandbox proof.
set -euo pipefail
q2_root=$(cd "$(dirname "$0")/.." && pwd)
q2_dir=$(mktemp -d /tmp/hadithly-q2-purchase.XXXXXX)
trap 'rm -rf "$q2_dir"' EXIT
swiftc -emit-library -emit-module -module-name ClerkKit "$q2_root/scripts/q2-purchase-fixtures/ClerkKit.swift" -o "$q2_dir/libClerkKit.dylib" -emit-module-path "$q2_dir/ClerkKit.swiftmodule"
swiftc -emit-library -emit-module -module-name RevenueCat "$q2_root/scripts/q2-purchase-fixtures/RevenueCat.swift" -o "$q2_dir/libRevenueCat.dylib" -emit-module-path "$q2_dir/RevenueCat.swiftmodule"
swiftc -I "$q2_dir" -L "$q2_dir" -lClerkKit -lRevenueCat \
  "$q2_root/ios/Hadithly/Core/Purchases/PendingPurchaseStore.swift" \
  "$q2_root/ios/Hadithly/Core/Purchases/PurchaseAccountGate.swift" \
  "$q2_root/ios/Hadithly/Core/Purchases/PurchaseOperationQueue.swift" \
  "$q2_root/ios/Hadithly/Core/Purchases/PurchaseManager.swift" \
  "$q2_root/scripts/q2-purchase-fixtures/Verify.swift" -o "$q2_dir/verify"
DYLD_LIBRARY_PATH="$q2_dir" "$q2_dir/verify"
