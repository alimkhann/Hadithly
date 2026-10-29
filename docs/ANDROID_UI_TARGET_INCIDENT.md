# Android UI target incident, October 29

A bare Gradle connected-device test task included a newly connected SM-A325F
phone as well as the Hadithly emulator. The phone's fixture run failed with no
Compose hierarchy. It is not physical-device acceptance evidence. Gradle's task
installs and removes the test applications; a later read-only package query found
`com.hadithly.app` absent on the phone. Its pre-test installation and local-data
state are unknown. The owner was asked for that context. No reinstall, private-data
read or recovery attempt followed.

Use `scripts/run-android-ui-tests.py` for emulator UI checks. It requires one
explicit emulator serial, verifies the emulator property, rejects physical or
multiple targets and overwrites `ANDROID_SERIAL` for Gradle. Four isolated
regressions pass. The installed AGP selector was inspected, and a live two-case
run targeted only the emulator while the phone remained connected. The installed
AGP's separate `--serial` option raised an unsupported-operation error before
execution; the runner uses its verified environment selector instead.

`verification/android-ui-target-guard.json` records the bounded evidence. The
physical-device gate remains open; the emulator pass does not establish the
phone's prior state or repair any possible local-data impact.
