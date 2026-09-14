import CloudKit
import Foundation
import OSLog

@MainActor
final class CloudSyncCoordinator {
    private weak var store: Store?
    private let privateDriver: CloudSyncDriver
    private let sharedDriver: CloudSyncDriver

    init(store: Store, initialSnapshot: LocalStoreSnapshot) {
        self.store = store
        let container = CKContainer(identifier: CloudSchema.containerIdentifier)
        privateDriver = CloudSyncDriver(
            scope: .privateCloud, database: container.privateCloudDatabase,
            stateData: initialSnapshot.cloud.privateState, store: store
        )
        sharedDriver = CloudSyncDriver(
            scope: .shared, database: container.sharedCloudDatabase,
            stateData: initialSnapshot.cloud.sharedState, store: store
        )
    }

    func start() {
        privateDriver.start()
        sharedDriver.start()
    }

    func schedule(snapshot: LocalStoreSnapshot) {
        privateDriver.schedule(snapshot: snapshot)
        sharedDriver.schedule(snapshot: snapshot)
    }

    func fetchNow() {
        privateDriver.fetchNow()
        sharedDriver.fetchNow()
    }

    func accept(_ metadata: CKShare.Metadata) {
        Task {
            do {
                try await CloudSharingController.accept(metadata)
                sharedDriver.fetchNow()
            } catch {
                store?.setSyncStatus(.error("L’invitation iCloud n’a pas pu être acceptée."))
            }
        }
    }
}

private final class CloudSyncDriver: CKSyncEngineDelegate, @unchecked Sendable {
    private let scope: ListProvenance
    private let database: CKDatabase
    private weak var store: Store?
    private let initialState: CKSyncEngine.State.Serialization?
    private let logger: Logger
    private lazy var engine: CKSyncEngine = {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: initialState, delegate: self)
        configuration.automaticallySync = true
        configuration.subscriptionID = scope == .shared ? "caddie-shared-changes" : "caddie-private-changes"
        return CKSyncEngine(configuration)
    }()

    init(scope: ListProvenance, database: CKDatabase, stateData: Data?, store: Store) {
        self.scope = scope
        self.database = database
        self.store = store
        logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Caddie", category: "CloudSync")
        initialState = stateData.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    }

    func start() {
        Task {
            if let snapshot = await MainActor.run(body: { self.store?.snapshot }) {
                schedule(snapshot: snapshot)
            }
            await synchronize(fetch: true)
        }
    }

    func schedule(snapshot: LocalStoreSnapshot) {
        let entries = snapshot.library.lists.filter { handles($0.provenance) }
        if scope == .privateCloud {
            let zones = entries.map { CKRecordZone(zoneID: CloudSchema.zoneID(for: $0.id)) }
            engine.state.add(pendingDatabaseChanges: zones.map(CKSyncEngine.PendingDatabaseChange.saveZone))
        }

        var recordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
        for mutation in snapshot.pendingMutations where handles(mutation: mutation, snapshot: snapshot) {
            let zoneID = zoneID(for: mutation.listID, snapshot: snapshot)
            if mutation.recordKind == .list && mutation.action == .delete && scope == .privateCloud {
                databaseChanges.append(.deleteZone(zoneID))
                continue
            }
            let recordID = CloudSchema.recordID(name: mutation.recordID, zoneID: zoneID)
            recordChanges.append(mutation.action == .delete ? .deleteRecord(recordID) : .saveRecord(recordID))
        }
        engine.state.add(pendingDatabaseChanges: databaseChanges)
        engine.state.add(pendingRecordZoneChanges: recordChanges)
    }

    func fetchNow() {
        Task { await synchronize(fetch: true) }
    }

    private func synchronize(fetch: Bool) async {
        await MainActor.run { store?.setSyncStatus(.syncing) }
        do {
            if fetch { try await engine.fetchChanges() }
            if engine.state.pendingDatabaseChanges.isEmpty == false || engine.state.pendingRecordZoneChanges.isEmpty == false {
                try await engine.sendChanges()
            }
            await MainActor.run { store?.setSyncStatus(.idle) }
        } catch let error as CKError {
            logger.error("Synchronisation échouée (portée: \(self.scope.rawValue, privacy: .public), code: \(error.code.rawValue, privacy: .public)).")
            switch error.code {
            case .notAuthenticated, .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                await MainActor.run { store?.setSyncStatus(.offline) }
            default:
                await MainActor.run { store?.setSyncStatus(.error("La synchronisation iCloud rencontrera une nouvelle tentative.")) }
            }
        } catch {
            logger.error("Synchronisation échouée (portée: \(self.scope.rawValue, privacy: .public), erreur non-CloudKit).")
            await MainActor.run { store?.setSyncStatus(.error("La synchronisation iCloud rencontrera une nouvelle tentative.")) }
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self,
                  let snapshot = await MainActor.run(body: { self.store?.snapshot }),
                  let mutation = snapshot.pendingMutations.first(where: {
                      $0.recordID == recordID.recordName && self.zoneID(for: $0.listID, snapshot: snapshot) == recordID.zoneID
                  }), mutation.action == .save else { return nil }
            return try? CloudRecordMapper.record(for: mutation, in: snapshot)
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            guard let data = try? JSONEncoder().encode(update.stateSerialization) else { return }
            await mutateSnapshot { snapshot in
                if self.scope == .shared { snapshot.cloud.sharedState = data }
                else { snapshot.cloud.privateState = data }
            }
        case .accountChange(let change) where scope == .privateCloud:
            let identifier: String?
            switch change.changeType {
            case .signIn(let current): identifier = current.recordName
            case .signOut: identifier = nil
            case .switchAccounts(_, let current): identifier = current.recordName
            @unknown default: return
            }
            await MainActor.run { store?.handleCloudAccountChange(identifier) }
        case .fetchedDatabaseChanges(let changes):
            await mutateSnapshot { snapshot in
                for deletion in changes.deletions {
                    if let entry = snapshot.library.lists.first(where: {
                        $0.cloudLocation?.zoneName == deletion.zoneID.zoneName && $0.cloudLocation?.ownerName == deletion.zoneID.ownerName
                    }) { snapshot.library.removeInaccessible(entry.id) }
                }
            }
        case .fetchedRecordZoneChanges(let changes):
            await mutateSnapshot { snapshot in
                let records = changes.modifications.map { modification -> CKRecord in
                    let server = modification.record
                    guard let mutation = snapshot.pendingMutations.first(where: {
                        $0.recordID == server.recordID.recordName && $0.action == .save
                    }), let client = try? CloudRecordMapper.record(for: mutation, in: snapshot) else { return server }
                    return ConflictResolver.merge(client: client, server: server, changedFields: mutation.changedFields)
                }
                try CloudRecordMapper.apply(records, scope: self.scope, to: &snapshot)
                for deletion in changes.deletions {
                    CloudRecordMapper.applyDeletion(deletion.recordID, recordType: deletion.recordType, to: &snapshot)
                    snapshot.pendingMutations.removeAll { $0.recordID == deletion.recordID.recordName }
                }
            }
        case .sentDatabaseChanges(let changes):
            await mutateSnapshot { snapshot in
                for zone in changes.savedZones {
                    guard let index = snapshot.library.lists.firstIndex(where: {
                        CloudSchema.zoneID(for: $0.id).zoneName == zone.zoneID.zoneName
                    }) else { continue }
                    snapshot.library.lists[index].provenance = .privateCloud
                    snapshot.library.lists[index].cloudLocation = CloudListLocation(zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName)
                }
                for zoneID in changes.deletedZoneIDs {
                    let listIDs = snapshot.pendingMutations.filter { $0.listID.uuidString.lowercased() == zoneID.zoneName.replacingOccurrences(of: "list-", with: "") }.map(\.listID)
                    snapshot.pendingMutations.removeAll { listIDs.contains($0.listID) }
                }
            }
        case .sentRecordZoneChanges(let changes):
            await mutateSnapshot { snapshot in
                for record in changes.savedRecords {
                    snapshot.cloud.systemFields[CloudSchema.cacheKey(record.recordID)] = try CloudRecordMapper.encodeSystemFields(record)
                    let savedListID = UUID(uuidString: record.recordID.zoneID.zoneName.replacingOccurrences(of: "list-", with: ""))
                    snapshot.pendingMutations.removeAll {
                        $0.recordID == record.recordID.recordName && $0.listID == savedListID
                    }
                }
                for id in changes.deletedRecordIDs {
                    snapshot.cloud.systemFields.removeValue(forKey: CloudSchema.cacheKey(id))
                    snapshot.pendingMutations.removeAll { $0.recordID == id.recordName }
                }
                for failure in changes.failedRecordSaves where failure.error.code == .serverRecordChanged {
                    guard let server = ConflictResolver.serverRecord(from: failure.error),
                          let mutation = snapshot.pendingMutations.first(where: { $0.recordID == failure.record.recordID.recordName }) else { continue }
                    let merged = ConflictResolver.merge(client: failure.record, server: server, changedFields: mutation.changedFields)
                    snapshot.cloud.systemFields[CloudSchema.cacheKey(merged.recordID)] = try CloudRecordMapper.encodeSystemFields(merged)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(merged.recordID)])
                }
            }
        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges, .accountChange:
            break
        @unknown default:
            break
        }
    }

    private func mutateSnapshot(_ operation: @escaping @Sendable (inout LocalStoreSnapshot) throws -> Void) async {
        await MainActor.run {
            guard let store else { return }
            var snapshot = store.snapshot
            do {
                try operation(&snapshot)
                store.replaceSnapshotFromSync(snapshot)
            } catch {
                logger.error("Intégration locale d’un événement CloudKit échouée (portée: \(self.scope.rawValue, privacy: .public)).")
                store.setSyncStatus(.error("Des données iCloud reçues n’ont pas pu être intégrées."))
            }
        }
    }

    private func handles(_ provenance: ListProvenance) -> Bool {
        scope == .shared ? provenance == .shared : provenance != .shared
    }

    private func handles(mutation: RecordMutation, snapshot: LocalStoreSnapshot) -> Bool {
        guard let entry = snapshot.library.lists.first(where: { $0.id == mutation.listID }) else {
            return scope == .privateCloud
        }
        return handles(entry.provenance)
    }

    private func zoneID(for listID: ShoppingList.ID, snapshot: LocalStoreSnapshot) -> CKRecordZone.ID {
        let owner = snapshot.library.lists.first(where: { $0.id == listID })?.cloudLocation?.ownerName
        return CloudSchema.zoneID(for: listID, ownerName: owner)
    }
}
