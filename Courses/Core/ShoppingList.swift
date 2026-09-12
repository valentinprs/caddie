import Foundation

struct Aisle: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String = "basket"
}

struct Product: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var aliases: [String] = []
    var uses: Int = 0
    // A nil aisle with hasPreference=true means an explicit choice of À classer.
    var hasPreference = false
    var preferredAisle: UUID?
}

struct ListItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var productID: UUID
    var note: String = ""
    var aisleID: UUID?
    var purchased = false
    var suggestion: String?
    var revision = UUID()
}

enum ListError: LocalizedError {
    case emptyName, duplicate, duplicateAisle, missing
    var errorDescription: String? {
        switch self {
        case .emptyName: "Saisissez un nom."
        case .duplicate: "Ce produit est déjà dans votre liste, y compris parmi les achats cochés."
        case .duplicateAisle: "Ce rayon existe déjà."
        case .missing: "Cet élément n’existe plus."
        }
    }
}

struct ShoppingList: Codable, Equatable {
    var version = 1
    var aisles: [Aisle] = []
    var products: [Product] = []
    var items: [ListItem] = []
    var onboarded = false

    static func key(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
    static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func product(_ id: UUID) -> Product? { products.first { $0.id == id } }
    func matching(_ name: String) -> Product? {
        let query = Self.key(name)
        return products.first { Self.key($0.name) == query || $0.aliases.contains { Self.key($0) == query } }
    }
    func suggestions(_ query: String) -> [Product] {
        let query = Self.key(query)
        return products.filter { query.isEmpty || Self.key($0.name).contains(query) || $0.aliases.contains { Self.key($0).contains(query) } }
            .sorted { $0.uses == $1.uses ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.uses > $1.uses }.prefix(8).map { $0 }
    }
    mutating func resolve(_ name: String) throws -> Product {
        let name = Self.clean(name)
        guard !name.isEmpty else { throw ListError.emptyName }
        if let existing = matching(name) { return existing }
        let product = Product(name: name)
        products.append(product)
        return product
    }
    @discardableResult mutating func add(name: String, note: String) throws -> UUID {
        let product = try resolve(name)
        guard !items.contains(where: { $0.productID == product.id }) else { throw ListError.duplicate }
        let item = ListItem(productID: product.id, note: note.trimmingCharacters(in: .whitespacesAndNewlines), aisleID: product.preferredAisle)
        items.append(item)
        if let index = products.firstIndex(where: { $0.id == product.id }) { products[index].uses += 1 }
        return item.id
    }
    @discardableResult mutating func edit(_ id: UUID, name: String, note: String) throws -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw ListError.missing }
        // Check before resolving so rejected edits cannot pollute the catalog.
        if let target = matching(name), items.contains(where: { $0.id != id && $0.productID == target.id }) { throw ListError.duplicate }
        let product = try resolve(name)
        let changed = items[index].productID != product.id
        items[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if changed {
            items[index].productID = product.id
            items[index].aisleID = product.preferredAisle
            items[index].suggestion = nil
            items[index].revision = UUID()
        }
        return changed
    }
    mutating func assign(_ id: UUID, aisle: UUID?) {
        guard aisle == nil || aisles.contains(where: { $0.id == aisle }),
              let index = items.firstIndex(where: { $0.id == id }),
              let productIndex = products.firstIndex(where: { $0.id == items[index].productID }) else { return }
        items[index].aisleID = aisle
        items[index].suggestion = nil
        items[index].revision = UUID()
        products[productIndex].hasPreference = true
        products[productIndex].preferredAisle = aisle
    }
    // Apply only to the unchanged item and unchanged aisle configuration used for inference.
    mutating func applyClassification(_ id: UUID, revision: UUID, aisles snapshot: [Aisle], aisle: UUID?, suggestion: String?) {
        guard aisles == snapshot, let index = items.firstIndex(where: { $0.id == id && $0.revision == revision }),
              product(items[index].productID)?.hasPreference == false,
              aisle == nil || aisles.contains(where: { $0.id == aisle }) else { return }
        items[index].aisleID = aisle
        items[index].suggestion = aisle == nil ? suggestion : nil
    }
    @discardableResult mutating func addAisle(_ name: String) throws -> UUID {
        let name = Self.clean(name)
        guard !name.isEmpty else { throw ListError.emptyName }
        guard Self.key(name) != Self.key("À classer"), !aisles.contains(where: { Self.key($0.name) == Self.key(name) }) else { throw ListError.duplicateAisle }
        let aisle = Aisle(name: name)
        aisles.append(aisle)
        return aisle.id
    }
    mutating func renameAisle(_ id: UUID, name: String) throws {
        let name = Self.clean(name)
        guard !name.isEmpty else { throw ListError.emptyName }
        guard Self.key(name) != Self.key("À classer"), !aisles.contains(where: { $0.id != id && Self.key($0.name) == Self.key(name) }) else { throw ListError.duplicateAisle }
        guard let index = aisles.firstIndex(where: { $0.id == id }) else { return }
        aisles[index].name = name
    }
    mutating func deleteAisle(_ id: UUID) {
        aisles.removeAll { $0.id == id }
        for index in items.indices where items[index].aisleID == id {
            items[index].aisleID = nil
            items[index].suggestion = nil
            items[index].revision = UUID()
        }
        for index in products.indices where products[index].preferredAisle == id {
            products[index].hasPreference = false
            products[index].preferredAisle = nil
        }
    }
    mutating func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].purchased.toggle()
    }
    mutating func dismissSuggestion(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].suggestion = nil
    }
    static func initial() -> Self {
        let names = ["Fruits et légumes", "Boucherie", "Poissonnerie", "Charcuterie", "Produits laitiers et œufs", "Boulangerie", "Épicerie", "Surgelés", "Boissons", "Hygiène et entretien"]
        let symbols = ["carrot", "fork.knife", "fish", "fork.knife", "refrigerator", "birthday.cake", "cabinet", "snowflake", "waterbottle", "bubbles.and.sparkles"]
        let seeds: [(String, [String])] = [
            ("Bavette", ["bavettes"]), ("Tomates", ["tomate"]), ("Tomates en conserve", ["tomate en conserve"]),
            ("Pommes", ["pomme"]), ("Bananes", ["banane"]), ("Carottes", ["carotte"]), ("Courgettes", ["courgette"]),
            ("Poulet", ["poulets"]), ("Saumon", []), ("Jambon", []), ("Lait", []), ("Œufs", ["œuf", "oeuf", "oeufs"]),
            ("Beurre", []), ("Comté", []), ("Yaourts", ["yaourt"]), ("Pain", ["pains"]), ("Riz", []), ("Pâtes", []),
            ("Huile d’olive", ["huile d'olive"]), ("Café", []), ("Petits pois surgelés", []), ("Eau", []),
            ("Jus d’orange", ["jus d'orange"]), ("Savon", ["savons"]), ("Dentifrice", []), ("Lessive", []), ("Papier toilette", [])
        ]
        return Self(aisles: zip(names, symbols).map { Aisle(name: $0, symbol: $1) }, products: seeds.map { Product(name: $0.0, aliases: $0.1) })
    }
}

struct LocalRepository {
    let url: URL
    func load() throws -> ShoppingList {
        guard FileManager.default.fileExists(atPath: url.path) else { return .initial() }
        return try JSONDecoder().decode(ShoppingList.self, from: Data(contentsOf: url))
    }
    func save(_ list: ShoppingList) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
    }
}
