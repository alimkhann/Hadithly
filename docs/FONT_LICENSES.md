# Arabic font license records

F2 introduced the `arabicFont` preference contract. No font binaries are
bundled yet — R4 selects and ships the chosen face. This file records the
license status of every candidate id so bundling never ships an unlicensed
font. A font may not be bundled in either app until its record here reads
`verified` with a re-check date.

| Font id | Family | Source | License | Redistribution | Status | Verified |
| --- | --- | --- | --- | --- | --- | --- |
| `amiri` | Amiri | https://github.com/aliftype/amiri | SIL Open Font License 1.1 with font exception intent per upstream | Permitted with OFL terms; reserved names apply (no derivatives under the Amiri name) | license-verified, bundle pending R4 | 2026-09-07 (from upstream OFL.txt; re-check before bundling) |
| `scheherazade-new` | Scheherazade New | https://software.sil.org/scheherazade/ | SIL Open Font License 1.1 | Permitted with OFL terms; reserved names apply | license-verified, bundle pending R4 | 2026-09-07 (from SIL page + bundled OFL; re-check before bundling) |
| `noto-naskh-arabic` | Noto Naskh Arabic | https://fonts.google.com/noto | SIL Open Font License 1.1 | Permitted with OFL terms; reserved names apply | license-verified, bundle pending R4 | 2026-09-07 (from Noto repo OFL.txt; re-check before bundling) |
| `system` | Platform default | iOS / Android system fonts | Platform license, no redistribution | Ship as-is | verified | 2026-09-07 |

Rules carried forward from `docs/PLAN.md` and `docs/REFERENCE_AUDIT.md`:

1. Only fonts with verified redistribution licenses may be offered.
2. Accessing a font online does not count as permission to bundle it.
3. R4 must attach the actual license text next to the font files and re-verify
   each record above before the first release build ships a bundled face.
4. The preference contract accepts unknown font ids and falls back to
   `system`, so a future licensed addition never breaks older clients.
