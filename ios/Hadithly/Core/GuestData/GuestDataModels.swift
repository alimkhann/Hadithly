import Foundation
import SwiftData

/// A hadith the reader wants to find again, saved while reading as a guest.
/// Stored only on-device until the user signs in, at which point it merges
/// into Convex and is cleared locally.
@Model
final class GuestBookmark {
    var hadithId: String
    var createdAt: Date
    // Display metadata captured at save time so the Saved tab renders
    // without a server round trip. Optional so older local stores migrate.
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date = .now,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

/// A note written on a hadith while reading as a guest. Same lifecycle as
/// GuestBookmark: local-only until sign-in, then merged and cleared.
@Model
final class GuestNote {
    var hadithId: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

/// A hadith marked as a favorite while reading as a guest.
@Model
final class GuestFavorite {
    var hadithId: String
    var createdAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date = .now,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

/// A private, device-local Saved folder. `localId` exists only until merge.
@Model
final class GuestSavedFolder {
    @Attribute(.unique) var localId: String
    var name: String
    var createdAt: Date

    init(localId: String = UUID().uuidString, name: String, createdAt: Date = .now) {
        self.localId = localId
        self.name = name
        self.createdAt = createdAt
    }
}

/// Membership is separate from facets so one guest target has zero or one folder.
@Model
final class GuestSavedMembership {
    @Attribute(.unique) var hadithId: String
    var folderLocalId: String
    var updatedAt: Date?

    init(hadithId: String, folderLocalId: String, updatedAt: Date? = .now) {
        self.hadithId = hadithId
        self.folderLocalId = folderLocalId
        self.updatedAt = updatedAt
    }
}

/// Private per-collection reading position. Progress is never shared or
/// ranked; it exists only so the reader can offer "continue reading".
@Model
final class GuestReadingProgress {
    var collectionSlug: String
    var collectionName: String
    var hadithId: String
    var volumeId: String?
    var hadithNumber: String?
    var referenceDisplay: String?
    /// JSON-encoded ReadingPosition V1. Optional for pre-R1 SwiftData rows.
    var positionData: Data?
    var updatedAt: Date

    init(
        collectionSlug: String,
        collectionName: String,
        hadithId: String,
        volumeId: String? = nil,
        hadithNumber: String? = nil,
        referenceDisplay: String? = nil,
        positionData: Data? = nil,
        updatedAt: Date = .now
    ) {
        self.collectionSlug = collectionSlug
        self.collectionName = collectionName
        self.hadithId = hadithId
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
        self.referenceDisplay = referenceDisplay
        self.positionData = positionData
        self.updatedAt = updatedAt
    }
}

/// Plain-value snapshots of the guest items. SwiftData models stay inside the
/// store; everything downstream (merge planning, tests, Saved tab) works on
/// these.
struct GuestBookmarkDraft: Codable, Equatable, Sendable {
    let hadithId: String
    let createdAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

struct GuestNoteDraft: Codable, Equatable, Sendable {
    let hadithId: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        content: String,
        createdAt: Date,
        updatedAt: Date,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

struct GuestFavoriteDraft: Codable, Equatable, Sendable {
    let hadithId: String
    let createdAt: Date
    var collectionName: String?
    var referenceDisplay: String?
    var volumeId: String?
    var hadithNumber: String?

    init(
        hadithId: String,
        createdAt: Date,
        collectionName: String? = nil,
        referenceDisplay: String? = nil,
        volumeId: String? = nil,
        hadithNumber: String? = nil
    ) {
        self.hadithId = hadithId
        self.createdAt = createdAt
        self.collectionName = collectionName
        self.referenceDisplay = referenceDisplay
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
    }
}

struct GuestSavedFolderDraft: Codable, Equatable, Sendable {
    let localId: String
    let name: String
    let createdAt: Date
}

struct GuestSavedMembershipDraft: Codable, Equatable, Sendable {
    let hadithId: String
    let folderLocalId: String
    var updatedAt: Date? = nil
}

struct GuestFolderDeletion: Equatable, Sendable {
    let folder: GuestSavedFolderDraft
    let hadithIds: [String]
}

struct GuestReadingProgressDraft: Codable, Equatable, Sendable {
    let collectionSlug: String
    let collectionName: String
    let hadithId: String
    var volumeId: String?
    var hadithNumber: String?
    var referenceDisplay: String?
    let updatedAt: Date
    var position: ReadingPosition?

    init(
        collectionSlug: String,
        collectionName: String,
        hadithId: String,
        volumeId: String? = nil,
        hadithNumber: String? = nil,
        referenceDisplay: String? = nil,
        updatedAt: Date,
        position: ReadingPosition? = nil
    ) {
        self.collectionSlug = collectionSlug
        self.collectionName = collectionName
        self.hadithId = hadithId
        self.volumeId = volumeId
        self.hadithNumber = hadithNumber
        self.referenceDisplay = referenceDisplay
        self.updatedAt = updatedAt
        self.position = position
    }

    var readingPosition: ReadingPosition? {
        if let position { return position }
        guard let volumeId, let hadithNumber else { return nil }
        return ReadingPosition.legacy(
            collectionSlug: collectionSlug,
            providerHadithId: hadithNumber,
            volumeId: volumeId,
            updatedAt: updatedAt.millisecondsSinceEpoch
        )
    }

    var effectiveUpdatedAt: Date {
        position.map { Date(timeIntervalSince1970: $0.updatedAt / 1_000) } ?? updatedAt
    }
}

@Model
final class GuestLibraryPartition {
    @Attribute(.unique) var ownerKey: String
    var subject: String
    var stateData: Data
    init(ownerKey: String, subject: String, stateData: Data) {
        self.ownerKey = ownerKey
        self.subject = subject
        self.stateData = stateData
    }
}

enum LibraryDeletionPhase: String, Codable, Sendable { case serverPending, identityPending }

@Model
final class GuestOutcomeClock {
    @Attribute(.unique) var key: String
    var subject: String
    var namespace: String
    var epoch: String
    var revision: Int
    var erasing: Bool
    init(subject: String, namespace: String) {
        key = LibraryOutcomeBinding.hash([namespace, subject]); self.subject = subject; self.namespace = namespace
        epoch = UUID().uuidString; revision = 0; erasing = false
    }
}

@Model
final class GuestOutcomeInventory {
    @Attribute(.unique) var key: String
    var headerKey: String
    init(binding: LibraryOutcomeBinding) {
        key = LibraryOutcomeBinding.hash([binding.owner.namespace, binding.owner.subject]) + ":" + binding.key
        headerKey = binding.key
    }
}

@Model
final class GuestOutcomeInventoryMigration {
    @Attribute(.unique) var key: String
    var stateData: Data
    init() throws {
        key = "outcome-inventory-v1"
        stateData = try JSONEncoder().encode(LibraryOutcomeInventoryProgress.scanning(after: ""))
    }
}

@Model
final class GuestLibraryExportArtifact {
    @Attribute(.unique) var id: String
    var subject: String
    var namespace: String
    init(id: String, owner: LibrarySyncOwner) { self.id = id; subject = owner.subject; namespace = owner.namespace }
}

@Model
final class GuestOutcomeScope {
    @Attribute(.unique) var key: String
    var subject: String
    var namespace: String
    var ownerKey: String
    var generation: String
    init(binding: LibraryOutcomeBinding) {
        key = binding.scopeKey; subject = binding.owner.subject; namespace = binding.owner.namespace
        ownerKey = binding.owner.storageKey; generation = UUID().uuidString
    }
}

@Model
final class GuestOutcomeHeader {
    @Attribute(.unique) var key: String
    var ownerKey: String
    var subject: String
    var namespace: String
    var generation: String
    var bindingData: Data
    var checkpointData: Data
    init(binding: LibraryOutcomeBinding, generation: String, checkpoint: LibraryOutcomeCheckpoint) throws {
        key = binding.key; ownerKey = binding.owner.storageKey; subject = binding.owner.subject; namespace = binding.owner.namespace
        self.generation = generation
        bindingData = try JSONEncoder().encode(binding)
        checkpointData = try JSONEncoder().encode(checkpoint)
    }
}

@Model
final class GuestOutcomeMember {
    @Attribute(.unique) var ordinalKey: String
    @Attribute(.unique) var memberKey: String
    @Attribute(.unique) var hadithKey: String
    var collectionKey: String
    var ownerKey: String
    var subject: String
    var namespace: String
    var ordinal: Int
    var disposition: String
    var rowData: Data
    init(binding: LibraryOutcomeBinding, row: SyncOutcomeMember) throws {
        ordinalKey = binding.ordinalKey(Int(row.ordinal)); memberKey = binding.key + ":" + row.memberId
        hadithKey = binding.key + ":" + row.hadithId
        collectionKey = binding.key; ownerKey = binding.owner.storageKey; subject = binding.owner.subject; namespace = binding.owner.namespace
        ordinal = Int(row.ordinal); disposition = row.disposition.rawValue; rowData = try JSONEncoder().encode(row)
    }
}

@Model
final class GuestAccountDeletion {
    @Attribute(.unique) var scope: String
    var subject: String
    var namespace: String
    var phase: String
    init(subject: String, namespace: String) {
        self.scope = namespace + "|" + subject
        self.subject = subject; self.namespace = namespace
        self.phase = LibraryDeletionPhase.serverPending.rawValue
    }
}

/// JSON at the portable-export boundary. User text is preserved verbatim;
/// provider passages are removed by their structural field names only.
enum LibraryExportValue: Codable, Equatable, Sendable {
    case object([String: LibraryExportValue]), array([LibraryExportValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let object = try? value.decode([String: LibraryExportValue].self) { self = .object(object) }
        else if let array = try? value.decode([LibraryExportValue].self) { self = .array(array) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else { self = .number(try value.decode(Double.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
    var withoutProviderPassages: LibraryExportValue {
        switch self {
        case .object(let fields): return .object(fields.filter { !["arabicText", "englishText", "capability"].contains($0.key) }.mapValues(\.withoutProviderPassages))
        case .array(let values): return .array(values.map(\.withoutProviderPassages))
        default: return self
        }
    }
    func containsAnyKey(_ keys: Set<String>) -> Bool {
        switch self {
        case .object(let fields): return !keys.isDisjoint(with: fields.keys) || fields.values.contains { $0.containsAnyKey(keys) }
        case .array(let values): return values.contains { $0.containsAnyKey(keys) }
        default: return false
        }
    }
    func includingLocalLibrary(_ local: LibraryExportValue) throws -> LibraryExportValue {
        guard case .object(var fields) = self else { throw LibrarySyncFailure.invalidReceipt }
        fields["localLibrary"] = local
        return .object(fields)
    }
}

@Model
final class GuestSavedAssembly {
    @Attribute(.unique) var key: String
    var subject: String
    var namespace: String
    var ownerKey: String
    var leaseData: Data
    var checkpointData: Data
    var erasing: Bool
    init(lease: LibrarySavedLease) throws {
        key = lease.key; subject = lease.owner.subject; namespace = lease.owner.namespace; ownerKey = lease.owner.storageKey
        leaseData = try JSONEncoder().encode(lease); checkpointData = try JSONEncoder().encode(LibrarySavedCheckpoint()); erasing = false
    }
}
@Model
final class GuestSavedFactRow {
    @Attribute(.unique) var key: String
    @Attribute(.unique) var sourceKey: String
    var collectionKey: String
    var subject: String
    var namespace: String
    var ownerKey: String
    var ordinal: Int
    var fingerprint: String
    var data: Data
    init(lease: LibrarySavedLease, fact: SavedFact) throws {
        let parsed = try LibrarySavedPolicy.integer(fact.ordinalValue); ordinal = parsed; key = lease.ordinalKey(parsed); sourceKey = lease.sourceKey(fact); collectionKey = lease.collection
        subject = lease.owner.subject; namespace = lease.owner.namespace; ownerKey = lease.owner.storageKey
        fingerprint = try fact.savedFingerprint(); data = try JSONEncoder().encode(fact)
    }
}
@Model
final class GuestSavedPageRow {
    @Attribute(.unique) var key: String
    @Attribute(.unique) var sequenceKey: String
    var collectionKey: String
    var subject: String
    var namespace: String
    var ownerKey: String
    var data: Data
    init(lease: LibrarySavedLease, receipt: LibrarySavedPageReceipt) throws {
        key = lease.inputKey(receipt.input); sequenceKey = lease.sequenceKey(receipt.sequence); collectionKey = lease.collection
        subject = lease.owner.subject; namespace = lease.owner.namespace; ownerKey = lease.owner.storageKey
        data = try JSONEncoder().encode(receipt)
    }
}
@Model
final class GuestSavedProjectionRow {
    @Attribute(.unique) var key: String
    var collectionKey: String
    var subject: String
    var namespace: String
    var ownerKey: String
    var fingerprint: String
    var data: Data
    init(lease: LibrarySavedLease, value: LibrarySavedProjection) throws {
        key = lease.projectionKey(value); collectionKey = lease.collection
        subject = lease.owner.subject; namespace = lease.owner.namespace; ownerKey = lease.owner.storageKey
        fingerprint = try value.savedFingerprint(); data = try JSONEncoder().encode(value)
    }
}

// MARK: - Generated library sync wire values
// Source: scripts/generate-library-sync-wire.py

enum LibrarySyncLimits {
    static let operations = 50
    static let fanoutOperations = 1
    static let bytes = 131072
    static let noteBytes = 24000
    static let folderLength = 64
    static let outcomePage = 50
    static let outcomeBytes = 65536
    static let savedFactRows = 1
    static let savedFactPageBytes = 65536
    static let savedFactSourceBytes = 32768
    static let savedFactCursorBytes = 12288
}

enum SyncFolderReference: Codable, Equatable, Sendable {
    case server(SyncFolderReferenceServer)
    case local(SyncFolderReferenceLocal)
    case none
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "server": self = .server(try SyncFolderReferenceServer(from: decoder))
        case "local": self = .local(try SyncFolderReferenceLocal(from: decoder))
        case "none": self = .none
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .server(let value):
            try values.encode("server", forKey: .kind)
            try value.encode(to: encoder)
        case .local(let value):
            try values.encode("local", forKey: .kind)
            try value.encode(to: encoder)
        case .none:
            try values.encode("none", forKey: .kind)
        }
    }
}

enum SyncCommand: Codable, Equatable, Sendable {
    case bookmarkAdd(SyncCommandBookmarkAdd)
    case bookmarkRemove(SyncCommandBookmarkRemove)
    case favoriteAdd(SyncCommandFavoriteAdd)
    case favoriteRemove(SyncCommandFavoriteRemove)
    case notePut(SyncCommandNotePut)
    case noteRemove(SyncCommandNoteRemove)
    case folderCreate(SyncCommandFolderCreate)
    case folderDelete(SyncCommandFolderDelete)
    case membershipPut(SyncCommandMembershipPut)
    case positionPut(SyncCommandPositionPut)
    case legacyPositionPut(SyncCommandLegacyPositionPut)
    case facetRestore(SyncCommandFacetRestore)
    case folderRestore(SyncCommandFolderRestore)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "bookmark_add": self = .bookmarkAdd(try SyncCommandBookmarkAdd(from: decoder))
        case "bookmark_remove": self = .bookmarkRemove(try SyncCommandBookmarkRemove(from: decoder))
        case "favorite_add": self = .favoriteAdd(try SyncCommandFavoriteAdd(from: decoder))
        case "favorite_remove": self = .favoriteRemove(try SyncCommandFavoriteRemove(from: decoder))
        case "note_put": self = .notePut(try SyncCommandNotePut(from: decoder))
        case "note_remove": self = .noteRemove(try SyncCommandNoteRemove(from: decoder))
        case "folder_create": self = .folderCreate(try SyncCommandFolderCreate(from: decoder))
        case "folder_delete": self = .folderDelete(try SyncCommandFolderDelete(from: decoder))
        case "membership_put": self = .membershipPut(try SyncCommandMembershipPut(from: decoder))
        case "position_put": self = .positionPut(try SyncCommandPositionPut(from: decoder))
        case "legacy_position_put": self = .legacyPositionPut(try SyncCommandLegacyPositionPut(from: decoder))
        case "facet_restore": self = .facetRestore(try SyncCommandFacetRestore(from: decoder))
        case "folder_restore": self = .folderRestore(try SyncCommandFolderRestore(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .bookmarkAdd(let value):
            try values.encode("bookmark_add", forKey: .kind)
            try value.encode(to: encoder)
        case .bookmarkRemove(let value):
            try values.encode("bookmark_remove", forKey: .kind)
            try value.encode(to: encoder)
        case .favoriteAdd(let value):
            try values.encode("favorite_add", forKey: .kind)
            try value.encode(to: encoder)
        case .favoriteRemove(let value):
            try values.encode("favorite_remove", forKey: .kind)
            try value.encode(to: encoder)
        case .notePut(let value):
            try values.encode("note_put", forKey: .kind)
            try value.encode(to: encoder)
        case .noteRemove(let value):
            try values.encode("note_remove", forKey: .kind)
            try value.encode(to: encoder)
        case .folderCreate(let value):
            try values.encode("folder_create", forKey: .kind)
            try value.encode(to: encoder)
        case .folderDelete(let value):
            try values.encode("folder_delete", forKey: .kind)
            try value.encode(to: encoder)
        case .membershipPut(let value):
            try values.encode("membership_put", forKey: .kind)
            try value.encode(to: encoder)
        case .positionPut(let value):
            try values.encode("position_put", forKey: .kind)
            try value.encode(to: encoder)
        case .legacyPositionPut(let value):
            try values.encode("legacy_position_put", forKey: .kind)
            try value.encode(to: encoder)
        case .facetRestore(let value):
            try values.encode("facet_restore", forKey: .kind)
            try value.encode(to: encoder)
        case .folderRestore(let value):
            try values.encode("folder_restore", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

struct SyncOperation: Codable, Equatable, Sendable {
    let id: String
    let revision: String
    let at: Double
    let command: SyncCommand
}

struct SyncBatch: Codable, Equatable, Sendable {
    let id: String
    let operations: [SyncOperation]
}

enum SyncOutcome: Codable, Equatable, Sendable {
    case batchRequiresSplit
    case preserved
    case folder(SyncOutcomeFolder)
    case folderDeleted(SyncOutcomeFolderDeleted)
    case folderDeletedManifest(SyncOutcomeFolderDeletedManifest)
    case folderRestored(SyncOutcomeFolderRestored)
    case folderRestoredManifest(SyncOutcomeFolderRestoredManifest)
    case resolvedPosition(SyncOutcomeResolvedPosition)
    case superseded(SyncOutcomeSuperseded)
    case unresolved(SyncOutcomeUnresolved)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "batch_requires_split": self = .batchRequiresSplit
        case "preserved": self = .preserved
        case "folder": self = .folder(try SyncOutcomeFolder(from: decoder))
        case "folder_deleted": self = .folderDeleted(try SyncOutcomeFolderDeleted(from: decoder))
        case "folder_deleted_manifest": self = .folderDeletedManifest(try SyncOutcomeFolderDeletedManifest(from: decoder))
        case "folder_restored": self = .folderRestored(try SyncOutcomeFolderRestored(from: decoder))
        case "folder_restored_manifest": self = .folderRestoredManifest(try SyncOutcomeFolderRestoredManifest(from: decoder))
        case "resolved_position": self = .resolvedPosition(try SyncOutcomeResolvedPosition(from: decoder))
        case "superseded": self = .superseded(try SyncOutcomeSuperseded(from: decoder))
        case "unresolved": self = .unresolved(try SyncOutcomeUnresolved(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .batchRequiresSplit:
            try values.encode("batch_requires_split", forKey: .kind)
        case .preserved:
            try values.encode("preserved", forKey: .kind)
        case .folder(let value):
            try values.encode("folder", forKey: .kind)
            try value.encode(to: encoder)
        case .folderDeleted(let value):
            try values.encode("folder_deleted", forKey: .kind)
            try value.encode(to: encoder)
        case .folderDeletedManifest(let value):
            try values.encode("folder_deleted_manifest", forKey: .kind)
            try value.encode(to: encoder)
        case .folderRestored(let value):
            try values.encode("folder_restored", forKey: .kind)
            try value.encode(to: encoder)
        case .folderRestoredManifest(let value):
            try values.encode("folder_restored_manifest", forKey: .kind)
            try value.encode(to: encoder)
        case .resolvedPosition(let value):
            try values.encode("resolved_position", forKey: .kind)
            try value.encode(to: encoder)
        case .superseded(let value):
            try values.encode("superseded", forKey: .kind)
            try value.encode(to: encoder)
        case .unresolved(let value):
            try values.encode("unresolved", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

struct SyncReceipt: Codable, Equatable, Sendable {
    let id: String
    let revision: String
    let outcome: SyncOutcome
}

struct SyncBinding: Codable, Equatable, Sendable {
    let ownerKey: String
    let subject: String
    let capability: String
    let validUntil: Double
}

struct SyncReply: Codable, Equatable, Sendable {
    let ownerKey: String
    let batchId: String
    let receipts: [SyncReceipt]
}

struct SyncDeletionAuthorization: Codable, Equatable, Sendable {
    let subject: String
    let authorization: String
    let validUntil: Double
}

struct SyncDeletionResult: Codable, Equatable, Sendable {
    let subject: String
    let deleted: Bool
}

struct SyncRevision: Codable, Equatable, Sendable {
    let saved: Double
    let position: Double
}

struct SyncHadithSummary: Codable, Equatable, Sendable {
    let _id: String
    let providerHadithId: String
    let collectionSlug: String
    let collectionName: String
    let volumeId: String?
    let arabicText: String
    let englishText: String?
    let referenceDisplay: String
}

struct SyncSavedItem: Codable, Equatable, Sendable {
    let hadithId: String
    let createdAt: Double
    let updatedAt: Double
    let bookmarkCreatedAt: Double?
    let favoriteCreatedAt: Double?
    let noteContent: String?
    let noteCreatedAt: Double?
    let noteUpdatedAt: Double?
    let folderId: String?
    let hadith: SyncHadithSummary
}

struct SyncFolderRow: Codable, Equatable, Sendable {
    let _id: String
    let name: String
    let createdAt: Double
}

struct SyncPositionRow: Codable, Equatable, Sendable {
    let collectionSlug: String
    let hadithId: String
    let updatedAt: Double
    let position: ReadingPosition?
    let hadith: SyncHadithSummary
}

struct SyncSavedSnapshot: Codable, Equatable, Sendable {
    let ownerKey: String
    let version: Double
    let folders: [SyncFolderRow]
    let items: [SyncSavedItem]
}

struct SyncPositionsSnapshot: Codable, Equatable, Sendable {
    let ownerKey: String
    let version: Double
    let rows: [SyncPositionRow]
}

struct SavedPrivateItem: Codable, Equatable, Sendable {
    let hadithId: String
    let createdAt: Double
    let updatedAt: Double
    let bookmarkCreatedAt: Double?
    let favoriteCreatedAt: Double?
    let noteContent: String?
    let noteCreatedAt: Double?
    let noteUpdatedAt: Double?
    let folderId: String?
    let folderUpdatedAt: Double?
}

enum SavedFact: Codable, Equatable, Sendable {
    case folder(SavedFactFolder)
    case item(SavedFactItem)
    case bookmark(SavedFactBookmark)
    case favorite(SavedFactFavorite)
    case note(SavedFactNote)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "folder": self = .folder(try SavedFactFolder(from: decoder))
        case "item": self = .item(try SavedFactItem(from: decoder))
        case "bookmark": self = .bookmark(try SavedFactBookmark(from: decoder))
        case "favorite": self = .favorite(try SavedFactFavorite(from: decoder))
        case "note": self = .note(try SavedFactNote(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .folder(let value):
            try values.encode("folder", forKey: .kind)
            try value.encode(to: encoder)
        case .item(let value):
            try values.encode("item", forKey: .kind)
            try value.encode(to: encoder)
        case .bookmark(let value):
            try values.encode("bookmark", forKey: .kind)
            try value.encode(to: encoder)
        case .favorite(let value):
            try values.encode("favorite", forKey: .kind)
            try value.encode(to: encoder)
        case .note(let value):
            try values.encode("note", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

enum SavedFactsReply: Codable, Equatable, Sendable {
    case page(SavedFactsReplyPage)
    case complete(SavedFactsReplyComplete)
    case restart(SavedFactsReplyRestart)
    case unavailable(SavedFactsReplyUnavailable)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "page": self = .page(try SavedFactsReplyPage(from: decoder))
        case "complete": self = .complete(try SavedFactsReplyComplete(from: decoder))
        case "restart": self = .restart(try SavedFactsReplyRestart(from: decoder))
        case "unavailable": self = .unavailable(try SavedFactsReplyUnavailable(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .page(let value):
            try values.encode("page", forKey: .kind)
            try value.encode(to: encoder)
        case .complete(let value):
            try values.encode("complete", forKey: .kind)
            try value.encode(to: encoder)
        case .restart(let value):
            try values.encode("restart", forKey: .kind)
            try value.encode(to: encoder)
        case .unavailable(let value):
            try values.encode("unavailable", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

struct SyncFrame: Codable, Equatable, Sendable {
    let clientKey: String
    let sequence: Double
    let batch: SyncBatch
}

struct SyncCommitted: Codable, Equatable, Sendable {
    let clientKey: String
    let sequence: Double
    let digest: String
    let revision: SyncRevision
    let reply: SyncReply
}

struct SyncPending: Codable, Equatable, Sendable {
    let clientKey: String
    let sequence: Double
    let batchId: String
    let digest: String
    let intentDigest: String
    let manifestId: String
    let generation: String
    let retryAfterMs: Double
}

enum SyncOutstanding: Codable, Equatable, Sendable {
    case committed(SyncOutstandingCommitted)
    case pending(SyncOutstandingPending)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "committed": self = .committed(try SyncOutstandingCommitted(from: decoder))
        case "pending": self = .pending(try SyncOutstandingPending(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .committed(let value):
            try values.encode("committed", forKey: .kind)
            try value.encode(to: encoder)
        case .pending(let value):
            try values.encode("pending", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

struct SyncOutcomePageRequest: Codable, Equatable, Sendable {
    let proof: SyncAcknowledgement
    let receiptId: String
    let manifestId: String
    let generation: String
    let phase: SyncOutcomePageRequestPhase
    let start: Double
}

struct SyncOutcomeMember: Codable, Equatable, Sendable {
    let ordinal: Double
    let memberId: String
    let hadithId: String
    let disposition: SyncOutcomeMemberDisposition
}

enum SyncOutcomePage: Codable, Equatable, Sendable {
    case page(SyncOutcomePagePage)
    case unavailable(SyncOutcomePageUnavailable)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "page": self = .page(try SyncOutcomePagePage(from: decoder))
        case "unavailable": self = .unavailable(try SyncOutcomePageUnavailable(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .page(let value):
            try values.encode("page", forKey: .kind)
            try value.encode(to: encoder)
        case .unavailable(let value):
            try values.encode("unavailable", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

struct SyncCursor: Codable, Equatable, Sendable {
    let closedThrough: Double
    let outstanding: SyncOutstanding?
}

struct SyncAcknowledgement: Codable, Equatable, Sendable {
    let clientKey: String
    let sequence: Double
    let batchId: String
    let digest: String
}

enum SyncExchange: Codable, Equatable, Sendable {
    case accepted(SyncExchangeAccepted)
    case pending(SyncExchangePending)
    case reconcile(SyncExchangeReconcile)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "accepted": self = .accepted(try SyncExchangeAccepted(from: decoder))
        case "pending": self = .pending(try SyncExchangePending(from: decoder))
        case "reconcile": self = .reconcile(try SyncExchangeReconcile(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .accepted(let value):
            try values.encode("accepted", forKey: .kind)
            try value.encode(to: encoder)
        case .pending(let value):
            try values.encode("pending", forKey: .kind)
            try value.encode(to: encoder)
        case .reconcile(let value):
            try values.encode("reconcile", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

struct SyncAckReply: Codable, Equatable, Sendable {
    let ownerKey: String
    let clientKey: String
    let cursor: SyncCursor
}

struct SyncFolderReferenceServer: Codable, Equatable, Sendable {
    let id: String
}

struct SyncFolderReferenceLocal: Codable, Equatable, Sendable {
    let key: String
}

struct SyncCommandBookmarkAdd: Codable, Equatable, Sendable {
    let hadithId: String
    let createdAt: Double
}

struct SyncCommandBookmarkRemove: Codable, Equatable, Sendable {
    let hadithId: String
}

struct SyncCommandFavoriteAdd: Codable, Equatable, Sendable {
    let hadithId: String
    let createdAt: Double
}

struct SyncCommandFavoriteRemove: Codable, Equatable, Sendable {
    let hadithId: String
}

struct SyncCommandNotePut: Codable, Equatable, Sendable {
    let hadithId: String
    let content: String
    let createdAt: Double
    let updatedAt: Double
}

struct SyncCommandNoteRemove: Codable, Equatable, Sendable {
    let hadithId: String
}

struct SyncCommandFolderCreate: Codable, Equatable, Sendable {
    let key: String
    let name: String
    let purpose: SyncCommandFolderCreatePurpose
}

struct SyncCommandFolderDelete: Codable, Equatable, Sendable {
    let folder: SyncFolderReference
}

struct SyncCommandMembershipPut: Codable, Equatable, Sendable {
    let hadithId: String
    let folder: SyncFolderReference
    let mode: String?
}

struct SyncCommandPositionPut: Codable, Equatable, Sendable {
    let position: ReadingPosition
}

struct SyncCommandLegacyPositionPut: Codable, Equatable, Sendable {
    let hadithId: String
    let updatedAt: Double
}

struct SyncCommandFacetRestore: Codable, Equatable, Sendable {
    let hadithId: String
    let deletionId: String
    let value: SyncCommandFacetRestoreValue
}

struct SyncCommandFolderRestore: Codable, Equatable, Sendable {
    let deletionId: String
    let name: String
    let hadithIds: [String]
}

struct SyncOutcomeFolder: Codable, Equatable, Sendable {
    let folderId: String
}

struct SyncOutcomeFolderDeleted: Codable, Equatable, Sendable {
    let hadithIds: [String]
    let deletedAt: Double
}

struct SyncOutcomeFolderDeletedManifest: Codable, Equatable, Sendable {
    let manifestId: String
    let generation: String
    let count: Double
    let deletedAt: Double
}

struct SyncOutcomeFolderRestored: Codable, Equatable, Sendable {
    let folderId: String
    let restored: [String]
    let superseded: [String]
    let missing: [String]
}

struct SyncOutcomeFolderRestoredManifest: Codable, Equatable, Sendable {
    let manifestId: String
    let generation: String
    let folderId: String
    let restored: Double
    let superseded: Double
    let missing: Double
}

struct SyncOutcomeResolvedPosition: Codable, Equatable, Sendable {
    let position: ReadingPosition
}

struct SyncOutcomeSuperseded: Codable, Equatable, Sendable {
    let reason: SyncOutcomeSupersededReason
}

struct SyncOutcomeUnresolved: Codable, Equatable, Sendable {
    let reason: SyncOutcomeUnresolvedReason
}

struct SavedFactFolder: Codable, Equatable, Sendable {
    let sourceId: String
    let ordinal: Double
    let value: SyncFolderRow
}

struct SavedFactItem: Codable, Equatable, Sendable {
    let sourceId: String
    let ordinal: Double
    let value: SavedPrivateItem
}

struct SavedFactBookmark: Codable, Equatable, Sendable {
    let sourceId: String
    let ordinal: Double
    let hadithId: String
    let createdAt: Double
}

struct SavedFactFavorite: Codable, Equatable, Sendable {
    let sourceId: String
    let ordinal: Double
    let hadithId: String
    let createdAt: Double
}

struct SavedFactNote: Codable, Equatable, Sendable {
    let sourceId: String
    let ordinal: Double
    let hadithId: String
    let content: String
    let createdAt: Double
    let updatedAt: Double
}

struct SavedFactsReplyPage: Codable, Equatable, Sendable {
    let ownerKey: String
    let version: Double
    let assemblyId: String
    let input: String?
    let start: Double
    let facts: [SavedFact]
    let next: String
}

struct SavedFactsReplyComplete: Codable, Equatable, Sendable {
    let ownerKey: String
    let version: Double
    let assemblyId: String
    let input: String?
    let start: Double
    let facts: [SavedFact]
    let total: Double
    let completion: String
}

struct SavedFactsReplyRestart: Codable, Equatable, Sendable {
    let reason: String
}

struct SavedFactsReplyUnavailable: Codable, Equatable, Sendable {
    let reason: SavedFactsReplyUnavailableReason
}

struct SyncOutstandingCommitted: Codable, Equatable, Sendable {
    let committed: SyncCommitted
}

struct SyncOutstandingPending: Codable, Equatable, Sendable {
    let pending: SyncPending
}

enum SyncOutcomePageRequestPhase: String, Codable, Sendable {
    case delete = "delete"
    case restore = "restore"
}

enum SyncOutcomeMemberDisposition: String, Codable, Sendable {
    case deleted = "deleted"
    case restored = "restored"
    case superseded = "superseded"
    case missing = "missing"
}

struct SyncOutcomePagePage: Codable, Equatable, Sendable {
    let ownerKey: String
    let request: SyncOutcomePageRequest
    let rows: [SyncOutcomeMember]
    let next: Double
    let done: Bool
}

struct SyncOutcomePageUnavailable: Codable, Equatable, Sendable {
    let ownerKey: String
    let request: SyncOutcomePageRequest
    let reason: SyncOutcomePageUnavailableReason
}

struct SyncExchangeAccepted: Codable, Equatable, Sendable {
    let committed: SyncCommitted
}

struct SyncExchangePending: Codable, Equatable, Sendable {
    let ownerKey: String
    let pending: SyncPending
}

struct SyncExchangeReconcile: Codable, Equatable, Sendable {
    let ownerKey: String
    let clientKey: String
    let requestedSequence: Double
    let requestedBatchId: String
    let cursor: SyncCursor
}

enum SyncCommandFolderCreatePurpose: String, Codable, Sendable {
    case guestClaim = "guest_claim"
    case create = "create"
}

enum SyncCommandFacetRestoreValue: Codable, Equatable, Sendable {
    case bookmark(SyncCommandFacetRestoreValueBookmark)
    case favorite(SyncCommandFacetRestoreValueFavorite)
    case note(SyncCommandFacetRestoreValueNote)
    private enum KindKey: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: KindKey.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "bookmark": self = .bookmark(try SyncCommandFacetRestoreValueBookmark(from: decoder))
        case "favorite": self = .favorite(try SyncCommandFacetRestoreValueFavorite(from: decoder))
        case "note": self = .note(try SyncCommandFacetRestoreValueNote(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported sync kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: KindKey.self)
        switch self {
        case .bookmark(let value):
            try values.encode("bookmark", forKey: .kind)
            try value.encode(to: encoder)
        case .favorite(let value):
            try values.encode("favorite", forKey: .kind)
            try value.encode(to: encoder)
        case .note(let value):
            try values.encode("note", forKey: .kind)
            try value.encode(to: encoder)
        }
    }
}

enum SyncOutcomeSupersededReason: String, Codable, Sendable {
    case newerCloud = "newer_cloud"
    case tieCloud = "tie_cloud"
    case changedSinceDelete = "changed_since_delete"
    case unversionedCloud = "unversioned_cloud"
}

enum SyncOutcomeUnresolvedReason: String, Codable, Sendable {
    case missingTarget = "missing_target"
    case missingFolder = "missing_folder"
    case missingSavedItem = "missing_saved_item"
    case folderNameTaken = "folder_name_taken"
    case positionUnavailable = "position_unavailable"
    case folderTooLarge = "folder_too_large"
    case preparationExpired = "preparation_expired"
    case folderRestoreUnavailable = "folder_restore_unavailable"
}

enum SavedFactsReplyUnavailableReason: String, Codable, Sendable {
    case sourceTooLarge = "source_too_large"
    case pageTooLarge = "page_too_large"
    case sourceDidNotAdvance = "source_did_not_advance"
    case sourceRequiresSplit = "source_requires_split"
}

enum SyncOutcomePageUnavailableReason: String, Codable, Sendable {
    case proofUnavailable = "proof_unavailable"
    case detailUnavailable = "detail_unavailable"
}

struct SyncCommandFacetRestoreValueBookmark: Codable, Equatable, Sendable {
    let createdAt: Double
}

struct SyncCommandFacetRestoreValueFavorite: Codable, Equatable, Sendable {
    let createdAt: Double
}

struct SyncCommandFacetRestoreValueNote: Codable, Equatable, Sendable {
    let content: String
    let createdAt: Double
    let updatedAt: Double
}

enum LibrarySyncIntentVectors {
    static let values: [(json: String, digest: String)] = [
        ("{\"id\":\"batch-1\",\"operations\":[{\"id\":\"note-1\",\"revision\":\"revision-1\",\"at\":1000,\"command\":{\"kind\":\"note_put\",\"hadithId\":\"target\",\"content\":\"private fixture\",\"createdAt\":1000,\"updatedAt\":1000}}]}", "7d639efa344ce9fa8bf9666d0d45904448dd9c7143ad06e757a97c94865d24ac"),
        ("{\"id\":\"unicode\",\"operations\":[{\"id\":\"note\",\"revision\":\"r1\",\"at\":1e-7,\"command\":{\"kind\":\"note_put\",\"hadithId\":\"target\",\"content\":\"العربية 🙂 é \\n \\\\ / \\\"\",\"createdAt\":0,\"updatedAt\":100000000000000000000}}]}", "db0c85275f1948a4b5ba1d240d3ff8155d02885f901d1ef3a80b0920fd534375"),
        ("{\"id\":\"folders\",\"operations\":[{\"id\":\"delete\",\"revision\":\"r2\",\"at\":1000,\"command\":{\"kind\":\"folder_delete\",\"folder\":{\"kind\":\"server\",\"id\":\"folder-a\"}}}]}", "6a049b18f66f123f134768983693195696440b0429c7a2b42c5f09ae13a82980"),
    ]
}

enum LibrarySavedParityVector {
    static let factsJSON = "[{\"kind\":\"item\",\"ordinal\":0,\"sourceId\":\"10004;savedItems\",\"value\":{\"bookmarkCreatedAt\":30,\"createdAt\":15,\"favoriteCreatedAt\":50,\"hadithId\":\"10002;hadiths\",\"noteContent\":\"Canonical tie wins\",\"noteCreatedAt\":15,\"noteUpdatedAt\":80,\"updatedAt\":90}},{\"createdAt\":20,\"hadithId\":\"10002;hadiths\",\"kind\":\"bookmark\",\"ordinal\":1,\"sourceId\":\"10005;bookmarks\"},{\"createdAt\":5,\"hadithId\":\"10002;hadiths\",\"kind\":\"bookmark\",\"ordinal\":2,\"sourceId\":\"10006;bookmarks\"},{\"createdAt\":12,\"hadithId\":\"10002;hadiths\",\"kind\":\"bookmark\",\"ordinal\":3,\"sourceId\":\"10007;bookmarks\"},{\"createdAt\":40,\"hadithId\":\"10002;hadiths\",\"kind\":\"favorite\",\"ordinal\":4,\"sourceId\":\"10008;favorites\"},{\"createdAt\":7,\"hadithId\":\"10002;hadiths\",\"kind\":\"favorite\",\"ordinal\":5,\"sourceId\":\"10009;favorites\"},{\"content\":\"Legacy tie loses\",\"createdAt\":2,\"hadithId\":\"10002;hadiths\",\"kind\":\"note\",\"ordinal\":6,\"sourceId\":\"10010;notes\",\"updatedAt\":80},{\"content\":\"Newer note wins\",\"createdAt\":3,\"hadithId\":\"10002;hadiths\",\"kind\":\"note\",\"ordinal\":7,\"sourceId\":\"10011;notes\",\"updatedAt\":100},{\"content\":\"Equal legacy later loses\",\"createdAt\":1,\"hadithId\":\"10002;hadiths\",\"kind\":\"note\",\"ordinal\":8,\"sourceId\":\"10012;notes\",\"updatedAt\":100}]"
    static let expectedJSON = "{\"bookmarkCreatedAt\":5,\"createdAt\":1,\"favoriteCreatedAt\":7,\"hadithId\":\"10002;hadiths\",\"noteContent\":\"Newer note wins\",\"noteCreatedAt\":3,\"noteUpdatedAt\":100,\"updatedAt\":100}"
    static let digests = ["2910f44808bac9af5ad8a4a5750d66379e10cb63078aef1051d2b314193963ff", "ba32014ba64629d8607ed10aca49525712b4557a916cafac9c5d6c230a24dc9f", "6745d688a1dae0589415eb26841d02adab8aef67bf0fe905a2fa3a3a8d4fa4a0", "d8f2d0249b52a97acf3ff2ef6444ec2d6974f1cbd1317102e235b322bf9307be", "0b9e4bd0d702fbfff91ad850722216b676891daba89a7bf18eaf1c8461dc63fe", "b7d957d6708e364a4b8429f9dcd0879b271e1dde18613a835568d52f8ae66cf2", "10045f121a89b0ce62e747eb255bd21176c8a9db0e2aa88543aa61f6ccfe79e8", "57676453fc0c865e4d4c80302075142fad2d3d0eecb6dc6504a06206024a93a8", "646fd55994ca980fb4dacbb7dcce43c2923b16ba0c5c7fbe7250ab4bd9e80337"]
}
