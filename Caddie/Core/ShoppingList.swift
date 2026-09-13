import Foundation

enum AisleIconColor: String, Codable, CaseIterable, Identifiable {
    case monochrome
    case amber
    case blue
    case cyan
    case emerald
    case fuchsia
    case green
    case indigo
    case lime
    case orange
    case pink
    case purple
    case red
    case rose
    case sky
    case teal
    case violet
    case yellow

    var id: Self { self }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "primary": self = .monochrome
        case "mint": self = .emerald
        default:
            guard let color = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Couleur d’icône inconnue : \(value)")
            }
            self = color
        }
    }
}

enum AisleIcon: String, Codable, CaseIterable, Identifiable {
    case carrot
    case beef
    case ham
    case milk
    case eggFried = "egg-fried"
    case fish
    case wheat
    case croissant
    case snowflake
    case soapDispenserDroplet = "soap-dispenser-droplet"

    var id: Self { self }

    static func migrated(from symbol: String?, aisleName: String) -> Self {
        if let symbol, let icon = Self(rawValue: symbol) { return icon }
        switch symbol {
        case "carrot", "leaf": return .carrot
        case "fork.knife": return aisleName == "Charcuterie" ? .ham : .beef
        case "fish": return .fish
        case "refrigerator": return .eggFried
        case "birthday.cake": return .croissant
        case "cabinet": return .wheat
        case "waterbottle", "cup.and.saucer", "wineglass": return .milk
        case "bubbles.and.sparkles", "shower", "washer": return .soapDispenserDroplet
        case "snowflake": return .snowflake
        default: return .wheat
        }
    }
}

struct Aisle: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var icon: AisleIcon = .wheat
    var iconColor: AisleIconColor = .monochrome

    // Keep the legacy "symbol" key so existing local files remain readable.
    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, iconColor
    }

    init(id: UUID = UUID(), name: String, icon: AisleIcon = .wheat, iconColor: AisleIconColor = .monochrome) {
        self.id = id
        self.name = name
        self.icon = icon
        self.iconColor = iconColor
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        icon = AisleIcon.migrated(from: try values.decodeIfPresent(String.self, forKey: .symbol), aisleName: name)
        iconColor = try values.decodeIfPresent(AisleIconColor.self, forKey: .iconColor) ?? .monochrome
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(icon.rawValue, forKey: .symbol)
        try values.encode(iconColor, forKey: .iconColor)
    }
}

struct Product: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var aliases: [String] = []
    var uses: Int = 0
    // A nil aisle with hasPreference=true means an explicit choice of À classer.
    var hasPreference = false
    var preferredAisle: UUID?
    // A nil aisle with hasClassification=true means the model chose À classer.
    var hasClassification = false
    var classificationSuggestion: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, uses, hasPreference, preferredAisle, hasClassification, classificationSuggestion
    }

    init(id: UUID = UUID(), name: String, aliases: [String] = [], uses: Int = 0, hasPreference: Bool = false,
         preferredAisle: UUID? = nil, hasClassification: Bool = false, classificationSuggestion: String? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.uses = uses
        self.hasPreference = hasPreference
        self.preferredAisle = preferredAisle
        self.hasClassification = hasClassification
        self.classificationSuggestion = classificationSuggestion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
        uses = try values.decodeIfPresent(Int.self, forKey: .uses) ?? 0
        hasPreference = try values.decodeIfPresent(Bool.self, forKey: .hasPreference) ?? false
        preferredAisle = try values.decodeIfPresent(UUID.self, forKey: .preferredAisle)
        hasClassification = try values.decodeIfPresent(Bool.self, forKey: .hasClassification) ?? false
        classificationSuggestion = try values.decodeIfPresent(String.self, forKey: .classificationSuggestion)
    }
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

    private static let defaultProducts: [(name: String, aliases: [String], aisle: String)] = [
        ("Bavette", ["bavettes"], "Boucherie"),
        ("Tomates", ["tomate"], "Fruits et légumes"),
        ("Tomates en conserve", ["tomate en conserve"], "Épicerie"),
        ("Pommes", ["pomme"], "Fruits et légumes"),
        ("Bananes", ["banane"], "Fruits et légumes"),
        ("Carottes", ["carotte"], "Fruits et légumes"),
        ("Courgettes", ["courgette"], "Fruits et légumes"),
        ("Poulet", ["poulets"], "Boucherie"),
        ("Saumon", [], "Poissonnerie"),
        ("Jambon", [], "Charcuterie"),
        ("Lait", [], "Produits laitiers et œufs"),
        ("Œufs", ["œuf", "oeuf", "oeufs"], "Produits laitiers et œufs"),
        ("Beurre", [], "Produits laitiers et œufs"),
        ("Comté", [], "Produits laitiers et œufs"),
        ("Yaourts", ["yaourt"], "Produits laitiers et œufs"),
        ("Pain", ["pains"], "Boulangerie"),
        ("Riz", [], "Épicerie"),
        ("Pâtes", [], "Épicerie"),
        ("Huile d’olive", ["huile d'olive"], "Épicerie"),
        ("Café", [], "Épicerie"),
        ("Petits pois surgelés", [], "Surgelés"),
        ("Eau", [], "Boissons"),
        ("Jus d’orange", ["jus d'orange"], "Boissons"),
        ("Savon", ["savons"], "Hygiène et entretien"),
        ("Dentifrice", [], "Hygiène et entretien"),
        ("Lessive", [], "Hygiène et entretien"),
        ("Papier toilette", [], "Hygiène et entretien")
    ]

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
        let item = ListItem(
            productID: product.id,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            aisleID: product.preferredAisle,
            suggestion: product.hasPreference ? nil : product.classificationSuggestion
        )
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
    mutating func updateNote(_ id: UUID, note: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw ListError.missing }
        items[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
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
        products[productIndex].hasClassification = false
        products[productIndex].classificationSuggestion = nil
    }
    // Apply only to the unchanged item and unchanged aisle configuration used for inference.
    mutating func applyClassification(_ id: UUID, revision: UUID, aisles snapshot: [Aisle], aisle: UUID?, suggestion: String?) {
        guard aisles == snapshot, let index = items.firstIndex(where: { $0.id == id && $0.revision == revision }),
              let productIndex = products.firstIndex(where: { $0.id == items[index].productID }),
              products[productIndex].hasPreference == false,
              aisle == nil || aisles.contains(where: { $0.id == aisle }) else { return }
        items[index].aisleID = aisle
        items[index].suggestion = aisle == nil ? suggestion : nil
        products[productIndex].preferredAisle = aisle
        products[productIndex].hasClassification = true
        products[productIndex].classificationSuggestion = aisle == nil ? suggestion : nil
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
    mutating func editAisle(_ id: UUID, name: String, icon: AisleIcon) throws {
        guard let index = aisles.firstIndex(where: { $0.id == id }) else { throw ListError.missing }
        try renameAisle(id, name: name)
        aisles[index].icon = icon
    }
    mutating func editAisleIcon(_ id: UUID, icon: AisleIcon, iconColor: AisleIconColor) throws {
        guard let index = aisles.firstIndex(where: { $0.id == id }) else { throw ListError.missing }
        aisles[index].icon = icon
        aisles[index].iconColor = iconColor
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
            products[index].hasClassification = false
            products[index].classificationSuggestion = nil
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
    mutating func registerDefaultProductClassifications() {
        for definition in Self.defaultProducts {
            guard let productIndex = products.firstIndex(where: { Self.key($0.name) == Self.key(definition.name) }),
                  !products[productIndex].hasPreference,
                  !products[productIndex].hasClassification,
                  let aisle = aisles.first(where: { Self.key($0.name) == Self.key(definition.aisle) }) else { continue }
            products[productIndex].preferredAisle = aisle.id
            products[productIndex].hasClassification = true
        }
    }
    static func initial() -> Self {
        let names = ["Fruits et légumes", "Boucherie", "Poissonnerie", "Charcuterie", "Produits laitiers et œufs", "Boulangerie", "Épicerie", "Surgelés", "Boissons", "Hygiène et entretien"]
        let icons: [AisleIcon] = [.carrot, .beef, .fish, .ham, .eggFried, .croissant, .wheat, .snowflake, .milk, .soapDispenserDroplet]
        var list = Self(
            aisles: zip(names, icons).map { Aisle(name: $0, icon: $1) },
            products: defaultProducts.map { Product(name: $0.name, aliases: $0.aliases) }
        )
        list.registerDefaultProductClassifications()
        return list
    }
}

struct LocalRepository {
    let url: URL
    func load() throws -> ShoppingList {
        guard FileManager.default.fileExists(atPath: url.path) else { return .initial() }
        var list = try JSONDecoder().decode(ShoppingList.self, from: Data(contentsOf: url))
        list.registerDefaultProductClassifications()
        return list
    }
    func save(_ list: ShoppingList) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
    }
}
