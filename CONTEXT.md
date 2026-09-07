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
