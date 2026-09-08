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
