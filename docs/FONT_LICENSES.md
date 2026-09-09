# Arabic font license records

F2 introduced the `arabicFont` preference contract. R4 bundled the three
licensed faces below on both platforms. This file records the license status
of every candidate id so bundling never ships an unlicensed font. A font may
not be bundled in either app until its record here reads `verified` with a
re-check date.

| Font id | Family | Source | License | Redistribution | Status | Verified |
| --- | --- | --- | --- | --- | --- | --- |
| `amiri` | Amiri | https://github.com/aliftype/amiri (bundled from google/fonts `ofl/amiri`, Amiri-Regular.ttf, sha-256 `ab391c41…70cfcd7`) | SIL Open Font License 1.1 with font exception intent per upstream | Permitted with OFL terms; reserved names apply (no derivatives under the Amiri name) | bundled (iOS + Android) | 2026-09-09 (OFL.txt downloaded with the font and attached beside the binary) |
| `scheherazade-new` | Scheherazade New | https://software.sil.org/scheherazade/ (bundled from google/fonts `ofl/scheherazadenew`, ScheherazadeNew-Regular.ttf, sha-256 `794bac8d…3d283b3`) | SIL Open Font License 1.1 | Permitted with OFL terms; reserved names apply | bundled (iOS + Android) | 2026-09-09 (OFL.txt downloaded with the font and attached beside the binary) |
| `noto-naskh-arabic` | Noto Naskh Arabic | https://fonts.google.com/noto (bundled from google/fonts `ofl/notonaskharabic`, NotoNaskhArabic variable, sha-256 `67b5a525…e6fab72f`) | SIL Open Font License 1.1 | Permitted with OFL terms; reserved names apply | bundled (iOS + Android) | 2026-09-09 (OFL.txt downloaded with the font and attached beside the binary) |
| `system` | Platform default | iOS / Android system fonts | Platform license, no redistribution | Ship as-is | verified | 2026-09-07 |

Bundled license text locations:

- iOS: `ios/Hadithly/Resources/Fonts/{Amiri,ScheherazadeNew,NotoNaskhArabic}-OFL.txt`
- Android: `android/app/src/main/assets/font-licenses/{amiri,scheherazade-new,noto-naskh-arabic}-OFL.txt`

Rules carried forward from `docs/PLAN.md` and `docs/REFERENCE_AUDIT.md`:

1. Only fonts with verified redistribution licenses may be offered.
2. Accessing a font online does not count as permission to bundle it.
3. R4 must attach the actual license text next to the font files and re-verify
   each record above before the first release build ships a bundled face.
4. The preference contract accepts unknown font ids and falls back to
   `system`, so a future licensed addition never breaks older clients.
