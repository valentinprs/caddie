import Foundation

enum MigrationState: String, Codable {
    case fresh
    case legacyImported
    case legacyVerified
}

struct CloudEngineCache: Codable, Equatable {
    var privateState: Data?
    var sharedState: Data?
    var systemFields: [String: Data]

    init(privateState: Data? = nil, sharedState: Data? = nil, systemFields: [String: Data] = [:]) {
        self.privateState = privateState
        self.sharedState = sharedState
        self.systemFields = systemFields
    }
}

struct LocalStoreSnapshot: Codable, Equatable {
    var version = 2
    var library: ListLibrary
    var onboarded: Bool
    var pendingMutations: [RecordMutation]
    var cloud: CloudEngineCache
    var installationID: UUID
    var cloudAccountIdentifier: String?
    var migrationState: MigrationState

    init(library: ListLibrary, onboarded: Bool = false, pendingMutations: [RecordMutation] = [],
         cloud: CloudEngineCache = .init(), installationID: UUID = UUID(),
         cloudAccountIdentifier: String? = nil, migrationState: MigrationState = .fresh) {
        self.library = library
        self.onboarded = onboarded
        self.pendingMutations = pendingMutations
        self.cloud = cloud
        self.installationID = installationID
        self.cloudAccountIdentifier = cloudAccountIdentifier
        self.migrationState = migrationState
    }
}

protocol LocalStoreProtocol {
    func load(legacyURL: URL) throws -> LocalStoreSnapshot
    func save(_ snapshot: LocalStoreSnapshot) throws
}

struct LocalStore: LocalStoreProtocol {
    let directory: URL
    var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }

    func load(legacyURL: URL) throws -> LocalStoreSnapshot {
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            return try decodeSnapshot(at: snapshotURL)
        }

        let snapshot: LocalStoreSnapshot
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            var legacy = try JSONDecoder().decode(ShoppingList.self, from: Data(contentsOf: legacyURL))
            legacy.registerDefaultProductClassifications()
            let now = Date()
            let id = ShoppingList.ID()
            let metadata = ShoppingListMetadata(id: id, name: "Ma liste", createdAt: now, updatedAt: now, lastOpenedAt: now)
            let entry = LibraryList(metadata: metadata, shoppingList: legacy, provenance: .local, cloudLocation: nil)
            snapshot = LocalStoreSnapshot(
                library: ListLibrary(currentListID: id, lists: [entry]),
                onboarded: legacy.onboarded,
                pendingMutations: MutationJournal.bootstrap(entry),
                migrationState: .legacyImported
            )
        } else {
            let library = ListLibrary.initial()
            snapshot = LocalStoreSnapshot(library: library, pendingMutations: library.lists.flatMap(MutationJournal.bootstrap))
        }

        try save(snapshot)
        var verified = try decodeSnapshot(at: snapshotURL)
        if verified.migrationState == .legacyImported {
            verified.migrationState = .legacyVerified
            try save(verified)
            verified = try decodeSnapshot(at: snapshotURL)
        }
        return verified
    }

    func save(_ snapshot: LocalStoreSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: snapshotURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func quarantine(_ snapshot: LocalStoreSnapshot, accountIdentifier: String) throws {
        let quarantine = directory.appendingPathComponent("quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let url = quarantine.appendingPathComponent("account-\(MutationJournal.digest(accountIdentifier)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func quarantinedSnapshot(accountIdentifier: String) throws -> LocalStoreSnapshot? {
        let url = directory.appendingPathComponent("quarantine", isDirectory: true)
            .appendingPathComponent("account-\(MutationJournal.digest(accountIdentifier)).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decodeSnapshot(at: url)
    }

    private func decodeSnapshot(at url: URL) throws -> LocalStoreSnapshot {
        var snapshot = try JSONDecoder().decode(LocalStoreSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.version == 2 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Version de cache Caddie inconnue."])
        }
        snapshot.library.repairSelection()
        return snapshot
    }
}
