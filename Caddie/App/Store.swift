import SwiftUI

enum SyncStatus: Equatable {
    case idle
    case syncing
    case offline
    case error(String)

    var message: String? {
        switch self {
        case .idle: nil
        case .syncing: "Synchronisation…"
        case .offline: "iCloud indisponible — les changements restent sur cet iPhone."
        case .error(let message): message
        }
    }
}

private struct ClassificationKey: Hashable {
    var listID: ShoppingList.ID
    var itemID: UUID
}

@MainActor @Observable
final class Store {
    private(set) var snapshot: LocalStoreSnapshot
    var error: String?
    private(set) var loadFailed = false
    private var classificationKeys: Set<ClassificationKey> = []
    var intelligenceStatus: String?
    private(set) var syncStatus: SyncStatus = .idle
    private let repository: LocalStore
    private let legacyURL: URL
    private let intelligence = Intelligence()
    private var syncCoordinator: CloudSyncCoordinator?

    var library: ListLibrary { snapshot.library }
    var currentListID: ShoppingList.ID? { snapshot.library.currentList?.id }
    var currentEntry: LibraryList? { snapshot.library.currentList }
    var list: ShoppingList { currentEntry?.shoppingList ?? .initial() }
    var currentListName: String { currentEntry?.metadata.name ?? "Ma liste" }
    var onboarded: Bool { snapshot.onboarded }
    var classifying: Set<UUID> {
        guard let currentListID else { return [] }
        return Set(classificationKeys.lazy.filter { $0.listID == currentListID }.map(\.itemID))
    }

    init() {
        // Keep the legacy container path so renaming the app does not discard an
        // existing shopping list when the update is installed over Courses.
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Courses", isDirectory: true)
        legacyURL = directory.appendingPathComponent("list.json")
        repository = LocalStore(directory: directory.appendingPathComponent("store-v2", isDirectory: true))
        do {
            snapshot = try repository.load(legacyURL: legacyURL)
        } catch {
            snapshot = LocalStoreSnapshot(library: .initial())
            loadFailed = true
            self.error = "Impossible de lire vos listes. Vos données ont été conservées. Fermez puis relancez l’app."
        }
        refreshAvailability()
        syncCoordinator = CloudSyncCoordinator(store: self, initialSnapshot: snapshot)
        ShareInvitationCenter.handler = { [weak self] metadata in self?.syncCoordinator?.accept(metadata) }
        syncCoordinator?.start()
    }

    func refreshAvailability() {
        intelligenceStatus = intelligence.status
    }

    func refreshCloud() {
        refreshAvailability()
        syncCoordinator?.fetchNow()
    }

    func completeOnboarding() {
        transact { $0.onboarded = true }
    }

    func update(listID: ShoppingList.ID? = nil, _ operation: (inout ShoppingList) throws -> Void) {
        guard let listID = listID ?? currentListID else { return }
        transact { next in
            guard let index = next.library.lists.firstIndex(where: { $0.id == listID }) else { throw LibraryError.missing }
            let old = next.library.lists[index]
            try operation(&next.library.lists[index].shoppingList)
            for aisleIndex in next.library.lists[index].shoppingList.aisles.indices {
                next.library.lists[index].shoppingList.aisles[aisleIndex].orderKey = Int64(aisleIndex)
            }
            next.library.lists[index].metadata.updatedAt = Date()
            let mutations = MutationJournal.changes(from: old, to: next.library.lists[index])
            MutationJournal.enqueue(mutations, into: &next.pendingMutations)
        }
    }

    @discardableResult func createList(name: String) -> Bool {
        error = nil
        transact { next in
            let id = try next.library.createList(name: name)
            guard let entry = next.library.lists.first(where: { $0.id == id }) else { throw LibraryError.missing }
            MutationJournal.enqueue(MutationJournal.bootstrap(entry), into: &next.pendingMutations)
        }
        return error == nil
    }

    @discardableResult func renameList(_ id: ShoppingList.ID, name: String) -> Bool {
        error = nil
        transact { next in
            guard let before = next.library.lists.first(where: { $0.id == id }) else { throw LibraryError.missing }
            try next.library.rename(id, name: name)
            guard let after = next.library.lists.first(where: { $0.id == id }) else { throw LibraryError.missing }
            MutationJournal.enqueue(MutationJournal.changes(from: before, to: after), into: &next.pendingMutations)
        }
        return error == nil
    }

    func selectList(_ id: ShoppingList.ID) {
        transact { try $0.library.select(id) }
    }

    func deleteList(_ id: ShoppingList.ID) {
        transact { next in
            let removed = try next.library.remove(id)
            var deletions = MutationJournal.bootstrap(removed).map {
                RecordMutation(listID: $0.listID, recordKind: $0.recordKind, recordID: $0.recordID, action: .delete)
            }
            deletions.sort { $0.recordKind != .list && $1.recordKind == .list }
            MutationJournal.enqueue(deletions, into: &next.pendingMutations)
        }
    }

    func removeSharedList(_ id: ShoppingList.ID) {
        transact { next in
            guard next.library.lists.contains(where: { $0.id == id && $0.provenance == .shared }) else {
                throw LibraryError.missing
            }
            next.library.removeInaccessible(id)
            next.pendingMutations.removeAll { $0.listID == id }
        }
    }

    func add(name: String, note: String) -> Bool {
        guard let listID = currentListID else { return false }
        var id: UUID?
        update(listID: listID) { id = try $0.add(name: name, note: note) }
        guard let id, snapshot.library.lists.first(where: { $0.id == listID })?.shoppingList.items.contains(where: { $0.id == id }) == true else { return false }
        classify(id, in: listID)
        return true
    }

    func edit(_ id: UUID, name: String, note: String, manualAisle: UUID?, changedAisle: Bool) -> Bool {
        guard let listID = currentListID else { return false }
        error = nil
        var changedProduct = false
        update(listID: listID) {
            changedProduct = try $0.edit(id, name: name, note: note)
            if changedAisle { $0.assign(id, aisle: manualAisle) }
        }
        guard error == nil else { return false }
        if changedProduct && !changedAisle { classify(id, in: listID) }
        return true
    }

    func classify(_ id: UUID) {
        guard let listID = currentListID else { return }
        classify(id, in: listID)
    }

    private func classify(_ id: UUID, in listID: ShoppingList.ID) {
        refreshAvailability()
        let key = ClassificationKey(listID: listID, itemID: id)
        guard intelligenceStatus == nil,
              let entry = snapshot.library.lists.first(where: { $0.id == listID }),
              let item = entry.shoppingList.items.first(where: { $0.id == id }),
              let product = entry.shoppingList.product(item.productID), !product.hasPreference, !product.hasClassification,
              !classificationKeys.contains(key) else { return }
        let aisleSnapshot = entry.shoppingList.aisles
        classificationKeys.insert(key)
        Task {
            defer {
                classificationKeys.remove(key)
                if let current = snapshot.library.lists.first(where: { $0.id == listID })?.shoppingList.items.first(where: { $0.id == id }),
                   current.productID != item.productID {
                    classify(id, in: listID)
                }
            }
            do {
                let result = try await intelligence.classify(name: product.name, aisles: aisleSnapshot)
                update(listID: listID) {
                    $0.applyClassification(id, revision: item.revision, aisles: aisleSnapshot, aisle: result.aisle, suggestion: result.suggestion)
                }
            } catch {
                if snapshot.library.lists.first(where: { $0.id == listID })?.shoppingList.items.contains(where: {
                    $0.id == id && $0.revision == item.revision
                }) == true {
                    self.error = "Le classement de « \(product.name) » n’a pas abouti. Vous pouvez choisir un rayon ou réessayer."
                }
            }
        }
    }

    func acceptSuggestion(_ id: UUID) {
        update { list in
            guard let item = list.items.first(where: { $0.id == id }), let name = item.suggestion else { return }
            let aisle = try list.aisles.first(where: { ShoppingList.key($0.name) == ShoppingList.key(name) })?.id ?? list.addAisle(name)
            list.assign(id, aisle: aisle)
        }
    }

    func setSyncStatus(_ status: SyncStatus) {
        syncStatus = status
    }

    func replaceSnapshotFromSync(_ next: LocalStoreSnapshot) {
        guard !loadFailed else { return }
        do {
            try repository.save(next)
            snapshot = next
        } catch {
            self.error = "Impossible d’enregistrer les changements reçus d’iCloud."
            syncStatus = .error("La synchronisation iCloud doit être relancée.")
        }
    }

    func handleCloudAccountChange(_ accountIdentifier: String?) {
        guard snapshot.cloudAccountIdentifier != accountIdentifier else { return }
        do {
            let wasOnboarded = snapshot.onboarded
            if let previous = snapshot.cloudAccountIdentifier {
                try repository.quarantine(snapshot, accountIdentifier: previous)
            }
            var next: LocalStoreSnapshot
            if let accountIdentifier,
               let restored = try repository.quarantinedSnapshot(accountIdentifier: accountIdentifier) {
                next = restored
            } else if snapshot.cloudAccountIdentifier == nil, let accountIdentifier {
                next = snapshot
                next.cloudAccountIdentifier = accountIdentifier
                for entry in next.library.lists where entry.provenance == .local {
                    MutationJournal.enqueue(MutationJournal.bootstrap(entry), into: &next.pendingMutations)
                }
            } else {
                let library = ListLibrary.initial()
                next = LocalStoreSnapshot(library: library, onboarded: wasOnboarded,
                                          pendingMutations: library.lists.flatMap(MutationJournal.bootstrap),
                                          cloudAccountIdentifier: accountIdentifier)
            }
            try repository.save(next)
            snapshot = next
            syncCoordinator?.schedule(snapshot: next)
        } catch {
            self.error = "Le changement de compte iCloud n’a pas pu être isolé en toute sécurité."
            syncStatus = .error("Reconnectez le compte iCloud précédent puis relancez Caddie.")
        }
    }

    private func transact(_ operation: (inout LocalStoreSnapshot) throws -> Void) {
        guard !loadFailed else { return }
        do {
            var next = snapshot
            try operation(&next)
            try repository.save(next)
            snapshot = next
            syncCoordinator?.schedule(snapshot: next)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
