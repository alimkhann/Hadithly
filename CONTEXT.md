# Hadithly content

Hadithly identifies provider content and reports authenticity without turning a collection claim into a hadith grade.

## Language

**Canonical hadith identity**:
The stable combination of a provider, a collection slug, and the provider's hadith ID.
_Avoid_: Internal ID, database ID

**Authenticity claim**:
A sourced statement about either one hadith or a whole collection. The claim includes its scope and verification method.
_Avoid_: Authenticity metadata, confidence

**Hadith grade**:
A normalized grade that a named source assigns to one hadith.
_Avoid_: Collection grade

**Collection scope**:
A documented authenticity classification that applies to a collection. It does not assign a grade to each hadith.
_Avoid_: Hadith grade, inferred grade

**License record**:
The known reuse terms for a content source, including an explicit unverified state when permission has not been established.
_Avoid_: Assumed permission

**Daily selection**:
The eligible hadith persisted for one local date and one IANA timezone.
_Avoid_: Daily hash, UTC pick

**Reading position**:
A private, versioned location in one collection. It combines a disposable page hint with a semantic hadith anchor so the reader can recover after content or layout changes.
_Avoid_: Reading progress, page number

**Semantic hadith anchor**:
A provider, collection slug, and provider hadith ID plus an offset normalized within that hadith. It remains meaningful when page boundaries change.
_Avoid_: Database row ID, scroll position

**Raw page hint**:
A stable page key, one-based display page index, and logical scroll offset that may be reused only when the content and layout signatures still match.
_Avoid_: Authoritative position

**Saved item**:
A private record for one canonical hadith that independently records bookmark, favorite, and note facets. A Saved item appears once even when it has more than one facet.
_Avoid_: Bookmark row, favorite row, note row

**Saved folder**:
A private user-named grouping that an existing Saved item may join at most once. Deleting a folder removes membership, never the Saved item.
_Avoid_: Collection, shared folder

**Saved-removal confirmation**:
A device-local safety preference that asks before removing a bookmark, favorite, or note. It never changes another device's safety behavior.
_Avoid_: Synced reader preference, undo

**Evidence submission**:
A private proposed translation tied to one hadith and language, with one to three evidence items. Receiving evidence does not mean its claim has been checked or published.
_Avoid_: Approved translation, AI verdict

**Evidence item**:
One submitted HTTPS source link or supported file. A file is identified by its private storage record, not a public download URL.
_Avoid_: Citation, license grant

**Quarantine**:
The state of a stored file before malware scanning and extraction. A quarantined file cannot be sent to AI or served publicly.
_Avoid_: Clean evidence, published source

**Provenance**:
The trace from a translation claim to source material and exact citations, established only after safe extraction and review.
_Avoid_: An uploaded file alone

**License assessment**:
A recorded decision about specific permitted uses of a source. Ability to access a source does not establish reuse rights.
_Avoid_: Accessible URL, assumed permission
