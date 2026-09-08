# Repository and disk recovery playbook

Audit date: 2026-09-02. This is a recovery record, not authorization to delete,
commit, push, rebase, or rewrite history.

### M0 recovery record (2026-09-02)

The user approved and M0 executed three batches. Free space went from
14.2 GiB before to 18 GiB after verification builds. The df delta
under-reports the du-measured deletions because OS-update local snapshots
hold the freed bytes as purgeable; the space releases as those snapshots age
out. Nothing else was deleted.

| Executed batch | Target | Measured size | Restore |
| --- | --- | ---: | --- |
| 1 | `ios/build`, `android/app/build`, `android/build`, `android/.gradle` | 1.45 GiB | Cold builds |
| 2 | `~/Library/Developer/Xcode/DerivedData` (whole directory) | 7.61 GiB | Xcode recreated it; cold build repopulated it to 1.33 GiB |
| 3 | Simulator `09B309B0-A490-45B1-A66D-7F0495859296` ("Adat Small iPhone") | 2.16 GiB | Recreate a device on iOS 26.2 in Xcode Devices |

Verification: cold `xcodebuild` build for the iPhone 17 Pro simulator and
`./gradlew assembleDebug` (with `JAVA_HOME` set to JDK 21) both succeeded after
the deletions. Retained: iOS 26.2 runtime, iPhone 17 Pro
`C4A9F20C-C9C3-4C4A-8192-1CCAF9CC9B03`, the Android 36 system image, the
`hadithly` AVD, both JDKs, and the Gradle caches.

## Current repository state

- Repository: `/Users/alim/Developer/Projects/Apps/Hadithly`
- Active branch: `finish-real-app-wiring` at `f02ba61`
- `main` and `origin/main`: `f5268e7`
- Relationship: the active branch is nine commits ahead and zero behind both
  local and remote `main`. It is a direct continuation, not a divergent fork.
- The active branch has no configured upstream. Do not push it by guess; G0 must
  choose the intended remote branch name after the checkpoint is reviewable.
- Remote: `origin` points to `alimkhann/Hadithly`.
- Git object database: 17 MB. Git history is not the disk-space problem.
- Worktree: one large unstaged set containing Phase 6 launch implementation,
  configuration, CI, purchases, production files, and the new planning docs.
  There are no staged changes.

The safe recovery is to checkpoint the current work in reviewable commits.
History rewriting is a separate future decision. Never mix the two.

### Proposed checkpoint sequence

G0 must inspect every path again immediately before committing. The intended
groups are:

1. `launch: production wiring and account lifecycle` — backend, client auth,
   deletion, push, and release configuration that already belong to Phase 6.
2. `billing: RevenueCat clients and quota paywall` — iOS and Android purchase
   directories plus their dependency and project changes.
3. `ci: verification and release checks` — `.github/`, `scripts/`, examples,
   and ignore rules after a secret scan.
4. `docs: post-launch master plan` — `AGENTS.md` and the changed/new `docs/`
   files, including the research and this playbook.

Do not infer that every currently dirty file belongs in those commits. Compare
each diff with the Phase 6 record, run the secret scan, and leave unexplained
user work untouched.

### Clean-history options

The default is to preserve the existing history. It is short, auditable, and
contains the reason the React Native/Next.js app moved into `legacy/`.

If a clean public history still matters after the release candidate passes:

1. Tag and push the verified repository to a private archival remote.
2. Export the exact release tree into a new empty repository or an orphan
   branch with one signed baseline commit.
3. Run builds and secret/history scans against the exported tree.
4. Change the public default branch only after the user approves the exact
   target and rollback path.

Do not use force push, interactive rebase, `filter-repo`, or delete `legacy/`
merely for neatness. A history scrub is justified for a secret or licensing
incident, but exposed credentials must still be revoked because Git rewriting
cannot make them safe.

## Current disk inventory

The sizes below are the 2026-09-02 audit values. The M0 recovery record above
lists which rows were later deleted and re-verified.

The startup volume reported about 16 GiB before verification and about 14 GiB
after the cold iOS build repopulated caches. Measured rebuildable or
re-downloadable candidates are:

| Candidate | Current size | Consequence | Restore |
| --- | ---: | --- | --- |
| `ios/build` | 1.1 GiB | Next iOS build is cold. | Run the normal `xcodebuild` command. |
| `android/app/build` | 427 MiB | Next Android build is cold. | Run `./gradlew assembleDebug`. |
| Xcode DerivedData | 7.6 GiB | Swift packages and indexes rebuild; first build is slow. | Xcode recreates it automatically. |
| Small iPhone simulator device | 2.2 GiB | Its installed app/data disappears. | Recreate it in Xcode Devices and Simulators. |
| iPhone 17 Pro simulator device | 2.5 GiB | Its installed app/data disappears. | Recreate it in Xcode Devices and Simulators. |
| iOS 27 physical-device support | 6.5 GiB | Debugging that physical OS may download support again. | Reconnect the device while online. |
| Android `hadithly` AVD | 2.4 GiB | Emulator apps/data/snapshots disappear. | Recreate the Pixel 7 AVD from the manifest below. |
| Android 36 system image | 4.3 GiB | No Android emulator until reinstalled. | Install the exact SDK package below. |
| Gradle caches | 5.1 GiB | All Gradle projects redownload dependencies. | Run their builds online. |

Sizes overlap only within each row as noted: the iOS simulator rows are inside
CoreSimulator's 4.6 GiB total; the Android AVD and SDK image are separate.

## Minimum reproducible toolchain

- Xcode 26.2, build 17C52
- iOS deployment target 17.0
- installed simulator runtime: iOS 26.2
- retained preferred simulator: iPhone 17 Pro,
  `C4A9F20C-C9C3-4C4A-8192-1CCAF9CC9B03`
- optional redundant simulator: Small iPhone,
  `09B309B0-A490-45B1-A66D-7F0495859296`
- Android compile/target SDK 36, min SDK 26
- Android system image: `system-images;android-36;google_apis;arm64-v8a`
- AVD: `hadithly`, Pixel 7, 1536 MB RAM, 1080 x 2400, Google APIs, no Play Store
- Gradle wrapper 9.7.1 and Android Gradle Plugin 9.3.1
- repository convention: JDK 21. JDK 21.0.1 is installed. The shell currently
  selects JDK 25.0.1, so M0 must set `JAVA_HOME=$(/usr/libexec/java_home -v 21)`
  for Android verification instead of deleting either JDK.

## Recommended cleanup order

Measure `df -h /` before and after every approved batch.

1. Delete only project build products. Expected recovery: about 1.5 GiB.
2. In Xcode Settings > Locations, delete Derived Data. Expected recovery: up to
   7.6 GiB. This is the best first large win.
3. If more is needed, delete only the Small iPhone simulator by its recorded
   device ID, retaining iOS 26.2 and the iPhone 17 Pro. Expected recovery:
   about 2.2 GiB.
4. If Android work will pause, delete the `hadithly` AVD in Android Studio Device
   Manager but retain the Android 36 image. Expected recovery: about 2.4 GiB.
5. If at least another 4 GiB is required and Android work will pause for longer,
   uninstall the exact Android 36 image in SDK Manager. Reinstall it before the
   next Android session.
6. Remove iOS DeviceSupport only if the connected iOS 27 device will not be
   debugged soon. It is a large but inconvenient re-download.
7. Prune Gradle by version only after checking other repositories. Keep 9.7.1
   for Hadithly; the 8.13, 9.2.1, Minecraft, and NeoForm caches belong to other
   work and require separate user approval.

Do not remove the sole iOS 26.2 runtime unless a physical-device-only period is
planned. Reinstalling the runtime through Xcode can require a much larger
download than deleting one simulator device saves.

### Android reinstall recipe

Run with JDK 21 and Android command-line tools on `PATH`:

```sh
sdkmanager "system-images;android-36;google_apis;arm64-v8a"
printf 'no\n' | avdmanager create avd \
  --name hadithly \
  --package "system-images;android-36;google_apis;arm64-v8a" \
  --device pixel_7
```

After creation, use Android Studio to set 1536 MB RAM if the default differs.
Then run a cold boot and `./gradlew testDebugUnitTest assembleDebug`.

## Destructive-action gate

Before deletion, show the user:

- the exact absolute path or simulator/SDK identifier;
- its measured size;
- whether app data, snapshots, or only rebuildable products will disappear;
- the exact restore path;
- the remaining retained iOS and Android test target.

One approval covers only the listed batch. It does not authorize deleting all
simulators, all SDKs, all caches, a workspace, a branch, or Git history.
