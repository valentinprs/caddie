import SwiftUI
import UIKit

private enum AddPanelLayout {
    static let compact: PresentationDetent = .height(76)
}

struct ShoppingView: View {
    @Bindable var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var addPanelPresented = false
    @State private var addPanelDetent: PresentationDetent = AddPanelLayout.compact
    @State private var managing = false
    @State private var managementRequested = false
    @State private var editing: ListItem?
    @State private var editingFromDrawer: ListItem?
    @State private var editingAisleIcon: Aisle?
    var body: some View {
        NavigationStack {
            List {
                if let status = store.intelligenceStatus {
                    Section {
                        Label(status, systemImage: "hand.tap").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if store.list.items.isEmpty {
                    ContentUnavailableView {
                        Label("Qu’est-ce qu’on prend ?", systemImage: "basket")
                    } description: {
                        Text("Ajoutez votre premier produit.\nChaque chose trouvera son rayon.")
                    }.listRowBackground(Color.clear)
                }
                aisleSection(id: nil, title: "À classer", symbol: "tray")
                ForEach(store.list.aisles) { aisle in
                    aisleSection(id: aisle.id, title: aisle.name, symbol: aisle.symbol)
                }
                let purchased = store.list.items.filter(\.purchased)
                if !purchased.isEmpty {
                    Section {
                        ForEach(purchased) { item in row(item) }
                        Button(role: .destructive) {
                            store.update { $0.items.removeAll(where: \.purchased) }
                        } label: {
                            Label("Supprimer les éléments cochés", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .background(Color(uiColor: .systemRed).opacity(0.10), in: Capsule())
                        .overlay { Capsule().stroke(Color(uiColor: .systemRed).opacity(0.16), lineWidth: 1) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 2, trailing: 10))
                    } header: {
                        ListSectionHeader(title: "Achetés", symbol: "checkmark.circle", count: purchased.count)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listRowSeparator(.hidden)
            .listSectionSpacing(16)
            .contentMargins(.bottom, addPanelPresented ? 112 : 0, for: .scrollContent)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gérer les rayons", systemImage: "slider.horizontal.3") { showManagement() }
                }
            }
            .disabled(store.loadFailed)
            .sheet(isPresented: $addPanelPresented, onDismiss: dismissAddPanel) {
                AddProductDrawer(
                    store: store,
                    selectedDetent: $addPanelDetent,
                    managementPresented: $managementRequested,
                    iconEditingAisle: $editingAisleIcon,
                    productEditingItem: $editingFromDrawer
                ) { item in
                    editingFromDrawer = item
                }
                .presentationSizing(.form)
                .presentationDetents([AddPanelLayout.compact, .large], selection: $addPanelDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(38)
                .presentationBackground(Color(.systemBackground))
                .background(SheetVisualCentering())
                // Keep the compact add bar visible without making the list modal.
                // At the compact detent, taps should pass through to list rows;
                // the expanded sheet remains modal while the user is editing.
                .presentationBackgroundInteraction(.enabled(upThrough: AddPanelLayout.compact))
                .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $managing, onDismiss: restoreAddPanel) { AislesView(store: store) }
            .sheet(item: $editing, onDismiss: restoreAddPanel) { item in EditProductView(store: store, item: item) }
            .fullScreenCover(
                isPresented: Binding(get: { !store.list.onboarded && !store.loadFailed }, set: { _ in }),
                onDismiss: restoreAddPanel
            ) {
                WelcomeView { store.update { $0.onboarded = true } }
            }
            .alert("Caddie", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Compris", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .onAppear { restoreAddPanel() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshAvailability() } }
        }
    }

    private func showManagement() {
        if addPanelPresented {
            // The compact drawer remains mounted; its nested sheet presents the
            // management view directly above it, avoiding a dismissal gap.
            managementRequested = true
        } else {
            managing = true
        }
    }

    private func showEditor(_ itemID: UUID) {
        guard let item = store.list.items.first(where: { $0.id == itemID }) else { return }
        if addPanelPresented {
            editingFromDrawer = item
        } else {
            editing = item
        }
    }

    private func showAisleIconEditor(_ aisle: Aisle) {
        editingAisleIcon = aisle
    }

    private func dismissAddPanel() {
        addPanelDetent = AddPanelLayout.compact
    }

    private func restoreAddPanel() {
        guard store.list.onboarded, !store.loadFailed, !managing, editing == nil else { return }
        addPanelDetent = AddPanelLayout.compact
        addPanelPresented = true
    }

    @ViewBuilder private func aisleSection(id: UUID?, title: String, symbol: String) -> some View {
        let items = store.list.items.filter { !$0.purchased && $0.aisleID == id }
        if !items.isEmpty {
            Section {
                ForEach(items) { row($0) }
            } header: {
                if let id {
                    if let aisle = store.list.aisles.first(where: { $0.id == id }) {
                        EditableAisleHeader(store: store, aisleID: id, count: items.count) {
                            showAisleIconEditor(aisle)
                        }
                    }
                } else {
                    ListSectionHeader(title: title, symbol: symbol, count: items.count)
                }
            }
        }
    }
    private func row(_ item: ListItem) -> some View {
        ProductRow(store: store, item: item, edit: { showEditor(item.id) })
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            .swipeActions {
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    store.update { $0.items.removeAll { $0.id == item.id } }
                }
                .tint(Color(uiColor: .systemRed))
            }
    }
}

private struct ListSectionHeader: View {
    let title: String
    let symbol: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
            Text(title)
                .font(.body.weight(.semibold))
                .frame(minHeight: 40, alignment: .leading)
            Spacer(minLength: 4)
            Text("\(count)").monospacedDigit()
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 0, trailing: 10))
    }
}

private struct EditableAisleHeader: View {
    @Bindable var store: Store
    let aisleID: UUID
    let count: Int
    let editIcon: () -> Void
    @FocusState private var nameFocused: Bool
    @State private var draftName = ""

    private var aisle: Aisle? { store.list.aisles.first { $0.id == aisleID } }

    var body: some View {
        HStack(spacing: 8) {
            if let aisle {
                Button(action: editIcon) {
                    Image(systemName: aisle.symbol)
                        .foregroundStyle(aisle.iconColor.color)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifier l’icône de \(aisle.name)")

                TextField("Nom du rayon", text: $draftName)
                    .focused($nameFocused)
                    .font(.body.weight(.semibold))
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
                    .layoutPriority(1)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                    .onChange(of: aisle.name) { _, name in if !nameFocused { draftName = name } }
                Spacer(minLength: 4)
                Text("\(count)").monospacedDigit()
            }
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 0, trailing: 10))
        .onAppear { draftName = aisle?.name ?? "" }
    }

    private func commitName() {
        guard let aisle, draftName != aisle.name else { return }
        store.error = nil
        store.update { try $0.renameAisle(aisleID, name: draftName) }
        if store.error != nil { draftName = aisle.name }
    }
}

private struct ProductRow: View {
    @Bindable var store: Store
    let item: ListItem
    let edit: () -> Void
    @FocusState private var nameFocused: Bool
    @FocusState private var noteFocused: Bool
    @State private var draftName: String
    @State private var draftNote: String

    init(store: Store, item: ListItem, edit: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.edit = edit
        _draftName = State(initialValue: store.list.product(item.productID)?.name ?? "")
        _draftNote = State(initialValue: item.note)
    }

    private var currentItem: ListItem? {
        store.list.items.first { $0.id == item.id }
    }

    private var currentProductName: String {
        guard let currentItem else { return "Produit" }
        return store.list.product(currentItem.productID)?.name ?? "Produit"
    }

    private var isEditing: Bool {
        nameFocused || noteFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Button { store.update { $0.toggle(item.id) } } label: {
                    Image(systemName: item.purchased ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.purchased ? Color.primary : Color.secondary)
                        // The product field uses the same fixed height, which
                        // keeps the visible name optically centered on this icon.
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.purchased ? "Remettre à acheter" : "Marquer acheté")
                .accessibilityValue(store.list.product(item.productID)?.name ?? "Produit")

                // Bring the secondary line closer without tying its position
                // to either focus state.
                VStack(alignment: .leading, spacing: -6) {
                    HStack(spacing: 8) {
                        TextField("Produit", text: $draftName)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(item.purchased)
                            .foregroundStyle(item.purchased ? .secondary : .primary)
                            .focused($nameFocused)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit(commitName)
                            .onChange(of: nameFocused) { _, focused in
                                if !focused { commitName() }
                            }
                            .onChange(of: currentProductName) { _, name in
                                if !nameFocused { draftName = name }
                            }
                            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)

                        // Reserve this slot in every state. Showing the icon
                        // must not change the row's width or height.
                        Button {
                            commitName()
                            edit()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isEditing ? 1 : 0)
                        .allowsHitTesting(isEditing)
                        .accessibilityHidden(!isEditing)
                        .accessibilityLabel("Modifier le produit")
                    }

                    TextField("Quantité ou précision", text: $draftNote)
                        .focused($noteFocused)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .submitLabel(.done)
                        .onSubmit(commitNote)
                        .onChange(of: noteFocused) { _, focused in if !focused { commitNote() } }
                        .onChange(of: item.note) { _, note in if !noteFocused { draftNote = note } }
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                }

                if store.classifying.contains(item.id) {
                    ProgressView().controlSize(.small)
                }
            }
            if let suggestion = item.suggestion, !item.purchased {
                HStack(spacing: 8) {
                    Button("Créer « \(suggestion) »") { store.acceptSuggestion(item.id) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    Spacer()
                    Button("Ignorer", systemImage: "xmark") { store.update { $0.dismissSuggestion(item.id) } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .frame(width: 34, height: 34)
                }
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 0)
        .animation(.smooth(duration: 0.2), value: isEditing)
    }

    private func commitName() {
        guard let currentItem,
              let currentProduct = store.list.product(currentItem.productID) else { return }
        let cleanedName = ShoppingList.clean(draftName)
        guard !cleanedName.isEmpty else {
            draftName = currentProduct.name
            return
        }
        guard cleanedName != currentProduct.name else { return }
        store.error = nil
        store.update { try $0.edit(item.id, name: cleanedName, note: currentItem.note) }
        if store.error != nil { draftName = currentProduct.name }
    }

    private func commitNote() {
        guard draftNote != item.note else { return }
        store.update { try $0.updateNote(item.id, note: draftNote) }
    }
}

private struct SheetVisualCentering: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let controller = view.parentViewController?.presentationController as? UISheetPresentationController else { return }
            let presenter = controller.presentingViewController.view
            controller.sourceView = presenter
            // The compact drawer already has a clear surface boundary; removing
            // the system drop shadow keeps it visually part of the list.
            controller.presentedView?.layer.shadowOpacity = 0
            controller.presentedView?.layer.shadowRadius = 0
        }
    }
}

private extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}

struct AddProductDrawer: View {
    @Bindable var store: Store
    @Binding var selectedDetent: PresentationDetent
    @Binding var managementPresented: Bool
    @Binding var iconEditingAisle: Aisle?
    @Binding var productEditingItem: ListItem?
    var openExisting: (ListItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Field: Hashable { case name }
    @FocusState private var focused: Field?
    @State private var name = ""
    private var isCompact: Bool { selectedDetent == AddPanelLayout.compact }
    private var transitionAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0) }
    private var existing: ListItem? {
        guard let product = store.list.matching(name) else { return nil }
        return store.list.items.first { $0.productID == product.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                primaryField
                if !isCompact {
                    Button("Replier", systemImage: "xmark") { collapse() }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 52, height: 52)
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                if isCompact {
                    focused = .name
                }
            }

            // Keep the content in place while the presentation controller is dragged.
            // The sheet clips it at the compact detent, then reveals it continuously as
            // its height grows. Conditional creation here made it pop in only after the
            // large detent had been selected.
            sheetContent
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused != nil {
                withAnimation(transitionAnimation) { selectedDetent = .large }
            }
        }
        .onChange(of: selectedDetent) { _, detent in
            if detent == AddPanelLayout.compact {
                focused = nil
            }
        }
        .sheet(isPresented: $managementPresented) {
            AislesView(store: store)
        }
        .sheet(item: $iconEditingAisle) { aisle in
            EditAisleIconView(store: store, aisle: aisle)
        }
        .sheet(item: $productEditingItem) { item in
            EditProductView(store: store, item: item)
        }
    }

    private var primaryField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            TextField("Ajouter un produit", text: $name,
                      prompt: Text("Ajouter un produit").foregroundStyle(Color.primary.opacity(0.55)))
                .font(.system(size: 18, weight: .medium))
                .focused($focused, equals: .name)
                .submitLabel(.done)
                .onSubmit { addProduct() }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        // The search affordance lives directly on the sheet surface in both detents.
        .contentShape(Rectangle())
    }

    private var sheetContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !ShoppingList.clean(name).isEmpty {
                    Button("Ajouter « \(name) »", systemImage: "plus.circle.fill") { addProduct() }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .disabled(existing != nil)
                }
                HStack {
                    Text(name.isEmpty ? "Pour vous inspirer" : "Suggestions")
                        .font(.title2.bold()).foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)

                let suggestions = store.list.suggestions(name)
                LazyVStack(spacing: 0) {
                    ForEach(suggestions) { product in
                        let item = store.list.items.first { $0.productID == product.id }
                        let aisleID = item?.aisleID ?? product.preferredAisle
                        let aisleSymbol = aisleID.flatMap { id in
                            store.list.aisles.first { $0.id == id }?.symbol
                        } ?? "basket"
                        Button {
                            if let item {
                                focused = nil
                                openExisting(item)
                            } else {
                                addProduct(named: product.name)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: aisleSymbol)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(product.name).foregroundStyle(.primary)
                                Spacer()
                                if let item {
                                    Text(item.purchased ? "Acheté" : "Déjà dans la liste")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "plus.circle").foregroundStyle(.primary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if product.id != suggestions.last?.id {
                            Divider().padding(.leading, 58).padding(.trailing, 20)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 16)

                if let existing {
                    Button("Retrouver le produit déjà présent") { focused = nil; openExisting(existing) }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                if let error = store.error {
                    Text(error).foregroundStyle(.red).font(.footnote).padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.top)
    }

    private func addProduct(named productName: String? = nil) {
        let submittedName = productName ?? name
        guard !ShoppingList.clean(submittedName).isEmpty else { return }
        guard store.add(name: submittedName, note: "") else { return }
        name = ""
        collapse()
    }

    private func collapse() {
        focused = nil
        withAnimation(transitionAnimation) { selectedDetent = AddPanelLayout.compact }
    }
}

struct EditProductView: View {
    @Bindable var store: Store
    let item: ListItem
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var aisle: UUID?
    @State private var changedAisle = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Produit") {
                    TextField("Nom", text: $name)
                    TextField("Quantité ou précision", text: $note).font(.subheadline)
                }
                Section {
                    Picker("Rayon", selection: Binding(get: { aisle }, set: { aisle = $0; changedAisle = true })) {
                        Text("À classer").tag(nil as UUID?)
                        ForEach(store.list.aisles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Mémoriser ce rayon") { changedAisle = true }
                        .disabled(changedAisle)
                } footer: { Text(changedAisle ? "Ce choix sera mémorisé après enregistrement." : "Votre choix de rayon sera prioritaire pour les prochains achats de ce produit.") }
                if item.purchased {
                    Button("Remettre à acheter") { store.update { $0.toggle(item.id) }; dismiss() }
                }
                if item.aisleID == nil && !changedAisle && store.list.product(item.productID)?.hasPreference == false {
                    Button("Réessayer le classement automatique") { store.classify(item.id); dismiss() }
                        .disabled(store.intelligenceStatus != nil || store.classifying.contains(item.id))
                }
                Button("Supprimer le produit de la liste", role: .destructive) {
                    store.update { $0.items.removeAll { $0.id == item.id } }; dismiss()
                }.tint(Color(uiColor: .systemRed))
                if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if store.edit(item.id, name: name, note: note, manualAisle: aisle, changedAisle: changedAisle) { dismiss() }
                    }.disabled(ShoppingList.clean(name).isEmpty)
                }
            }
            .onAppear { name = store.list.product(item.productID)?.name ?? ""; note = item.note; aisle = item.aisleID }
        }
    }
}

struct AislesView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editingAisle: Aisle?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Nouveau rayon", text: $name)
                        Button("Ajouter", systemImage: "plus.circle.fill") {
                            store.error = nil
                            store.update { _ = try $0.addAisle(name) }
                            if store.error == nil { name = "" }
                        }.labelStyle(.iconOnly).disabled(ShoppingList.clean(name).isEmpty).frame(width: 44, height: 44)
                    }
                }
                Section {
                    ForEach(store.list.aisles) { aisle in
                        Button { editingAisle = aisle } label: {
                            HStack(spacing: 12) {
                                Image(systemName: aisle.symbol)
                                    .foregroundStyle(aisle.iconColor.color)
                                    .frame(width: 24)
                                Text(aisle.name).foregroundStyle(.primary)
                                Spacer()
                            }
                            .frame(minHeight: 36)
                        }
                    }
                    .onMove { source, destination in store.update { $0.aisles.move(fromOffsets: source, toOffset: destination) } }
                    .onDelete { offsets in
                        let ids = offsets.map { store.list.aisles[$0].id }
                        store.update { list in ids.forEach { list.deleteAisle($0) } }
                    }
                } header: { Text("Votre parcours") } footer: {
                    Text("Glissez les poignées pour suivre votre parcours en magasin. Touchez un rayon pour modifier son nom ou son icône. Supprimer un rayon conserve ses produits dans « À classer » et oublie ses classements mémorisés.")
                }
                if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Mes rayons").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
            .sheet(item: $editingAisle) { aisle in
                EditAisleView(store: store, aisle: aisle)
            }
        }
    }
}

private enum AisleSymbolCatalog {
    static let choices: [(symbol: String, label: String)] = [
        ("basket", "Panier"), ("carrot", "Légumes"), ("leaf", "Feuille"),
        ("fork.knife", "Couverts"), ("fish", "Poisson"), ("refrigerator", "Réfrigérateur"),
        ("birthday.cake", "Gâteau"), ("cabinet", "Épicerie"), ("snowflake", "Surgelés"),
        ("waterbottle", "Bouteille"), ("cup.and.saucer", "Café"), ("wineglass", "Verre"),
        ("bubbles.and.sparkles", "Entretien"), ("shower", "Hygiène"),
        ("pawprint", "Animaux"), ("heart", "Santé"), ("tshirt", "Vêtements"),
        ("car", "Voiture"), ("house", "Maison"), ("gift", "Cadeaux"),
        ("takeoutbag.and.cup.and.straw", "À emporter"), ("cart", "Panier"),
        ("pills", "Pharmacie"), ("cross.case", "Premiers secours"),
        ("book", "Librairie"), ("gamecontroller", "Loisirs"),
        ("camera", "Photo"), ("paintpalette", "Créatif"),
        ("washer", "Linge"), ("shippingbox", "Colis")
    ]
}

private extension AisleIconColor {
    var color: Color {
        switch self {
        case .primary: .primary
        case .orange: Color(uiColor: .systemOrange)
        case .yellow: Color(uiColor: .systemYellow)
        case .green: Color(uiColor: .systemGreen)
        case .mint: Color(uiColor: .systemMint)
        case .teal: Color(uiColor: .systemTeal)
        case .cyan: Color(uiColor: .systemCyan)
        case .blue: Color(uiColor: .systemBlue)
        case .indigo: Color(uiColor: .systemIndigo)
        case .purple: Color(uiColor: .systemPurple)
        case .pink: Color(uiColor: .systemPink)
        case .red: Color(uiColor: .systemRed)
        }
    }

    var label: String {
        switch self {
        case .primary: "Système"
        case .orange: "Orange"
        case .yellow: "Jaune"
        case .green: "Vert"
        case .mint: "Menthe"
        case .teal: "Turquoise"
        case .cyan: "Cyan"
        case .blue: "Bleu"
        case .indigo: "Indigo"
        case .purple: "Violet"
        case .pink: "Rose"
        case .red: "Rouge"
        }
    }
}

private struct AisleIconGrid: View {
    @Binding var symbol: String
    let iconColor: AisleIconColor

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
            spacing: 12
        ) {
            ForEach(AisleSymbolCatalog.choices, id: \.symbol) { choice in
                Button { symbol = choice.symbol } label: {
                    Image(systemName: choice.symbol)
                        .font(.title2)
                        .foregroundStyle(iconColor.color)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            symbol == choice.symbol ? iconColor.color.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(alignment: .topTrailing) {
                            if symbol == choice.symbol {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(iconColor.color)
                                    .padding(5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(symbol == choice.symbol ? .isSelected : [])
            }
        }
    }
}

private struct AisleColorPalette: View {
    @Binding var selection: AisleIconColor

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6),
            spacing: 12
        ) {
            ForEach(AisleIconColor.allCases) { color in
                Button { selection = color } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if selection == color {
                                Circle()
                                    .stroke(Color.primary, lineWidth: 2)
                                    .padding(-5)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}

struct EditAisleIconView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var symbol: String
    @State private var iconColor: AisleIconColor
    private let aisle: Aisle

    init(store: Store, aisle: Aisle) {
        self.store = store
        self.aisle = aisle
        _symbol = State(initialValue: aisle.symbol)
        _iconColor = State(initialValue: aisle.iconColor)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Icône")
                        .font(.headline)
                    AisleIconGrid(symbol: $symbol, iconColor: iconColor)

                    Text("Couleur de l’icône")
                        .font(.headline)
                        .padding(.top, 8)
                    AisleColorPalette(selection: $iconColor)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(aisle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.error = nil
                        store.update { try $0.editAisleIcon(aisle.id, symbol: symbol, iconColor: iconColor) }
                        if store.error == nil { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
}

struct EditAisleView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    private let aisle: Aisle
    init(store: Store, aisle: Aisle) {
        self.store = store
        self.aisle = aisle
        _name = State(initialValue: aisle.name)
        _symbol = State(initialValue: aisle.symbol)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom du rayon") { TextField("Nom", text: $name) }
                Section("Icône") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                        ForEach(AisleSymbolCatalog.choices, id: \.symbol) { choice in
                            Button { symbol = choice.symbol } label: {
                                Image(systemName: choice.symbol)
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(
                                        symbol == choice.symbol ? Color.primary.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if symbol == choice.symbol {
                                            Image(systemName: "checkmark.circle.fill").font(.caption)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.label)
                            .accessibilityAddTraits(symbol == choice.symbol ? .isSelected : [])
                        }
                    }.padding(.vertical, 8)
                }
                if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Modifier le rayon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.error = nil
                        store.update { try $0.editAisle(aisle.id, name: name, symbol: symbol) }
                        if store.error == nil { dismiss() }
                    }.disabled(ShoppingList.clean(name).isEmpty)
                }
            }
        }
    }
}

struct WelcomeView: View {
    var start: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image("CaddieLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                    .padding(.top, 24)
                Text("Moins d’allers-retours.\nPlus de simplicité.")
                    .font(.largeTitle.weight(.medium))
                Text("Vos courses, rangées comme vous les faites.").font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 24) {
                    example("Bavette", detail: "2 pièces · Boucherie", symbol: "fork.knife")
                    example("Tomates", detail: "500 g · Fruits et légumes", symbol: "carrot")
                    example("Dentifrice", detail: "1 tube · Hygiène et entretien", symbol: "bubbles.and.sparkles")
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 24))
                Text("Dix rayons pour commencer, à adapter à votre parcours. Le classement automatique utilise Apple Intelligence lorsqu’il est disponible. Vous gardez toujours la main.")
                    .foregroundStyle(.secondary)
                Label("Vos produits restent sur votre iPhone.", systemImage: "iphone").font(.footnote)
                Button("Commencer ma liste", action: start).font(.headline).frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
                Text("Ces exemples ne seront pas ajoutés à votre liste.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.background(Color(.systemGroupedBackground)).interactiveDismissDisabled()
    }
    private func example(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
