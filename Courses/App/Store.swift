import SwiftUI

@MainActor @Observable
final class Store {
    private(set) var list: ShoppingList
    var error: String?
    private(set) var loadFailed = false
    private(set) var classifying: Set<UUID> = []
    var intelligenceStatus: String?
    private let repository: LocalRepository
    private let intelligence = Intelligence()

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Courses", isDirectory: true)
        repository = LocalRepository(url: directory.appendingPathComponent("list.json"))
        do { list = try repository.load() }
        catch {
            list = .initial()
            loadFailed = true
            self.error = "Impossible de lire votre liste. Vos données ont été conservées. Fermez puis relancez l’app."
        }
        refreshAvailability()
    }
    func refreshAvailability() { intelligenceStatus = intelligence.status }
    func update(_ operation: (inout ShoppingList) throws -> Void) {
        guard !loadFailed else { return }
        do {
            var next = list
            try operation(&next)
            try repository.save(next)
            list = next
        } catch { self.error = error.localizedDescription }
    }
    func add(name: String, note: String) -> Bool {
        var id: UUID?
        update { id = try $0.add(name: name, note: note) }
        guard let id, list.items.contains(where: { $0.id == id }) else { return false }
        classify(id)
        return true
    }
    func edit(_ id: UUID, name: String, note: String, manualAisle: UUID?, changedAisle: Bool) -> Bool {
        error = nil
        var changedProduct = false
        update {
            changedProduct = try $0.edit(id, name: name, note: note)
            if changedAisle { $0.assign(id, aisle: manualAisle) }
        }
        guard error == nil else { return false }
        if changedProduct && !changedAisle { classify(id) }
        return true
    }
    func classify(_ id: UUID) {
        refreshAvailability()
        guard intelligenceStatus == nil,
              let item = list.items.first(where: { $0.id == id }),
              let product = list.product(item.productID), !product.hasPreference, !product.hasClassification,
              !classifying.contains(id) else { return }
        let snapshot = list.aisles
        classifying.insert(id)
        Task {
            defer {
                classifying.remove(id)
                // Renaming while a request runs needs a fresh request for the new product.
                if let current = list.items.first(where: { $0.id == id }), current.productID != item.productID {
                    classify(id)
                }
            }
            do {
                let result = try await intelligence.classify(name: product.name, aisles: snapshot)
                update { $0.applyClassification(id, revision: item.revision, aisles: snapshot, aisle: result.aisle, suggestion: result.suggestion) }
            } catch {
                // Manual classification and newer edits always take precedence, even over an error.
                if list.items.contains(where: { $0.id == id && $0.revision == item.revision }) {
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
}
