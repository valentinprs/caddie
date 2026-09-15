import SwiftUI
import UIKit

private struct AisleIconView: View {
    let icon: AisleIcon
    var size: CGFloat = 24

    var body: some View {
        Image("lucide-\(icon.rawValue)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private enum AddPanelLayout {
    static let compactHeight: CGFloat = 76
    static let compact: PresentationDetent = .height(compactHeight)
}

#if DEBUG
private struct DevelopmentBuildBadge: View {
    var body: some View {
        Label("Développement", systemImage: "hammer.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay { Capsule().stroke(.orange.opacity(0.25), lineWidth: 1) }
            .accessibilityLabel("Build de développement")
    }
}
#endif

struct ShoppingView: View {
    @Bindable var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var addPanelPresented = false
    @State private var addPanelDetent: PresentationDetent = AddPanelLayout.compact
    @State private var managing = false
    @State private var managingLists = false
    @State private var managementRequested = false
    @State private var listsManagementRequested = false
    @State private var editing: ListItem?
    @State private var editingFromDrawer: ListItem?
    @State private var editingAisleIcon: Aisle?
    var body: some View {
        NavigationStack {
            List {
                if let status = store.syncStatus.message {
                    Section {
                        Label(status, systemImage: store.syncStatus == .syncing ? "arrow.triangle.2.circlepath" : "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
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
                    aisleSection(id: aisle.id, title: aisle.name, symbol: "tray")
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
#if DEBUG
            .overlay {
                GeometryReader { proxy in
                    if addPanelPresented, addPanelDetent == AddPanelLayout.compact {
                        VStack {
                            Spacer()
                            DevelopmentBuildBadge()
                                .padding(.bottom, AddPanelLayout.compactHeight + proxy.safeAreaInsets.bottom + 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(false)
            }
#endif
            .navigationTitle(store.currentListName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(store.library.lists) { entry in
                            Button {
                                store.selectList(entry.id)
                            } label: {
                                Label(entry.metadata.name, systemImage: entry.id == store.currentListID ? "checkmark" : (entry.provenance == .shared ? "person.2" : "list.bullet"))
                            }
                        }
                        Divider()
                        Button("Gérer les listes", systemImage: "square.grid.2x2") { showListsManagement() }
                    } label: {
                        Label("Changer de liste", systemImage: "chevron.down")
                    }
                }
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
                    listsManagementPresented: $listsManagementRequested,
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
            .sheet(isPresented: $managingLists, onDismiss: restoreAddPanel) { ListsView(store: store) }
            .sheet(item: $editing, onDismiss: restoreAddPanel) { item in EditProductView(store: store, item: item) }
            .fullScreenCover(
                isPresented: Binding(get: { !store.onboarded && !store.loadFailed }, set: { _ in }),
                onDismiss: restoreAddPanel
            ) {
                WelcomeView { store.completeOnboarding() }
            }
            .alert("Caddie", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Compris", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .onAppear { restoreAddPanel() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshCloud() } }
            .onChange(of: store.currentListID) { _, _ in
                editing = nil
                editingFromDrawer = nil
                editingAisleIcon = nil
            }
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

    private func showListsManagement() {
        if addPanelPresented {
            // Present from the compact add drawer, which is the view currently
            // presenting a sheet. A sibling presentation from the main view is
            // ignored by SwiftUI while that drawer is visible.
            listsManagementRequested = true
        } else {
            managingLists = true
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
        guard store.onboarded, !store.loadFailed, !managing, !managingLists, editing == nil else { return }
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
                    AisleIconView(icon: aisle.icon)
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
    @Binding var listsManagementPresented: Bool
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
        .sheet(isPresented: $listsManagementPresented) {
            ListsView(store: store)
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
                        let aisle = aisleID.flatMap { id in store.list.aisles.first { $0.id == id } }
                        Button {
                            if let item {
                                focused = nil
                                openExisting(item)
                            } else {
                                addProduct(named: product.name)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                if let aisle {
                                    AisleIconView(icon: aisle.icon, size: 20)
                                        .foregroundStyle(aisle.iconColor.color)
                                        .frame(width: 24)
                                } else {
                                    Image(systemName: "basket")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                }
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
                                AisleIconView(icon: aisle.icon, size: 20)
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

struct ListsView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming: LibraryList?
    @State private var sharing: LibraryList?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Nouvelle liste", text: $newName)
                            .textInputAutocapitalization(.sentences)
                        Button("Créer", systemImage: "plus.circle.fill") {
                            if store.createList(name: newName) { newName = "" }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(ShoppingList.clean(newName).isEmpty)
                        .frame(width: 44, height: 44)
                    }
                }

                listSection("Mes listes", entries: store.library.lists.filter { $0.provenance != .shared })
                listSection("Listes partagées", entries: store.library.lists.filter { $0.provenance == .shared })

                if let error = store.error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Mes listes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } }
            }
            .sheet(item: $renaming) { entry in
                RenameListView(store: store, entry: entry)
            }
            .sheet(item: $sharing) { entry in
                CloudSharingView(entry: entry) {
                    if entry.provenance == .shared { store.removeSharedList(entry.id) }
                }
            }
        }
    }

    @ViewBuilder private func listSection(_ title: String, entries: [LibraryList]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    Button {
                        store.selectList(entry.id)
                        dismiss()
                    } label: {
                        HStack {
                            Label(entry.metadata.name, systemImage: entry.provenance == .shared ? "person.2" : "list.bullet")
                                .foregroundStyle(.primary)
                            Spacer()
                            if entry.id == store.currentListID { Image(systemName: "checkmark") }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(entry.provenance == .shared ? "Quitter" : "Supprimer", systemImage: entry.provenance == .shared ? "rectangle.portrait.and.arrow.right" : "trash", role: .destructive) {
                            if entry.provenance == .shared { sharing = entry }
                            else { store.deleteList(entry.id) }
                        }
                            .disabled(store.library.lists.count == 1)
                        if entry.isOwner {
                            Button("Renommer", systemImage: "pencil") { renaming = entry }.tint(.blue)
                            Button("Partager", systemImage: "person.badge.plus") { sharing = entry }.tint(.indigo)
                        }
                    }
                }
            }
        }
    }
}

private struct RenameListView: View {
    @Bindable var store: Store
    let entry: LibraryList
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(store: Store, entry: LibraryList) {
        self.store = store
        self.entry = entry
        _name = State(initialValue: entry.metadata.name)
    }

    var body: some View {
        NavigationStack {
            Form { TextField("Nom de la liste", text: $name) }
                .navigationTitle("Renommer la liste")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            if store.renameList(entry.id, name: name) { dismiss() }
                        }
                        .disabled(ShoppingList.clean(name).isEmpty)
                    }
                }
        }
    }
}

private extension AisleIcon {
    var label: String {
        switch self {
        case .carrot: "Carotte"
        case .beef: "Viande"
        case .ham: "Jambon"
        case .milk: "Lait"
        case .eggFried: "Œuf au plat"
        case .fish: "Poisson"
        case .wheat: "Blé"
        case .croissant: "Croissant"
        case .snowflake: "Flocon"
        case .soapDispenserDroplet: "Distributeur de savon"
        }
    }
}

private extension AisleIconColor {
    var color: Color {
        switch self {
        case .monochrome: Self.adaptive(light: .init(0, 0, 0), dark: .init(1, 0, 0))
        case .amber: Self.adaptive(light: .init(0.555, 0.163, 48.998), dark: .init(0.473, 0.137, 46.201))
        case .blue: Self.adaptive(light: .init(0.488, 0.243, 264.376), dark: .init(0.424, 0.199, 265.638))
        case .cyan: Self.adaptive(light: .init(0.52, 0.105, 223.128), dark: .init(0.45, 0.085, 224.283))
        case .emerald: Self.adaptive(light: .init(0.508, 0.118, 165.612), dark: .init(0.432, 0.095, 166.913))
        case .fuchsia: Self.adaptive(light: .init(0.518, 0.253, 323.949), dark: .init(0.452, 0.211, 324.591))
        case .green: Self.adaptive(light: .init(0.527, 0.154, 150.069), dark: .init(0.448, 0.119, 151.328))
        case .indigo: Self.adaptive(light: .init(0.457, 0.24, 277.023), dark: .init(0.398, 0.195, 277.366))
        case .lime: Self.adaptive(light: .init(0.841, 0.238, 128.85), dark: .init(0.768, 0.233, 130.85))
        case .orange: Self.adaptive(light: .init(0.553, 0.195, 38.402), dark: .init(0.47, 0.157, 37.304))
        case .pink: Self.adaptive(light: .init(0.525, 0.223, 3.958), dark: .init(0.459, 0.187, 3.815))
        case .purple: Self.adaptive(light: .init(0.496, 0.265, 301.924), dark: .init(0.438, 0.218, 303.724))
        case .red: Self.adaptive(light: .init(0.505, 0.213, 27.518), dark: .init(0.444, 0.177, 26.899))
        case .rose: Self.adaptive(light: .init(0.514, 0.222, 16.935), dark: .init(0.455, 0.188, 13.697))
        case .sky: Self.adaptive(light: .init(0.5, 0.134, 242.749), dark: .init(0.443, 0.11, 240.79))
        case .teal: Self.adaptive(light: .init(0.511, 0.096, 186.391), dark: .init(0.437, 0.078, 188.216))
        case .violet: Self.adaptive(light: .init(0.491, 0.27, 292.581), dark: .init(0.432, 0.232, 292.759))
        case .yellow: Self.adaptive(light: .init(0.852, 0.199, 91.936), dark: .init(0.795, 0.184, 86.047))
        }
    }

    private static func adaptive(light: Oklch, dark: Oklch) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(oklch: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    var label: String {
        switch self {
        case .monochrome: "Noir et blanc"
        case .amber: "Ambre"
        case .blue: "Bleu"
        case .cyan: "Cyan"
        case .emerald: "Émeraude"
        case .fuchsia: "Fuchsia"
        case .green: "Vert"
        case .indigo: "Indigo"
        case .lime: "Citron vert"
        case .orange: "Orange"
        case .pink: "Rose"
        case .purple: "Pourpre"
        case .red: "Rouge"
        case .rose: "Rose foncé"
        case .sky: "Bleu ciel"
        case .teal: "Sarcelle"
        case .violet: "Violet"
        case .yellow: "Jaune"
        }
    }
}

private struct Oklch {
    let lightness: Double
    let chroma: Double
    let hue: Double

    init(_ lightness: Double, _ chroma: Double, _ hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }
}

private extension UIColor {
    convenience init(oklch color: Oklch) {
        let hue = color.hue * .pi / 180
        let a = color.chroma * cos(hue)
        let b = color.chroma * sin(hue)
        let l = pow(color.lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(color.lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(color.lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        self.init(
            red: Self.sRGB(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: Self.sRGB(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: Self.sRGB(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
            alpha: 1
        )
    }

    private static func sRGB(_ linear: Double) -> CGFloat {
        let value = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return CGFloat(min(max(value, 0), 1))
    }
}

private struct AisleIconGrid: View {
    @Binding var icon: AisleIcon
    let iconColor: AisleIconColor

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
            spacing: 12
        ) {
            ForEach(AisleIcon.allCases) { choice in
                Button { icon = choice } label: {
                    AisleIconView(icon: choice, size: 24)
                        .foregroundStyle(iconColor.color)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(icon == choice ? Color.primary.opacity(0.22) : Color.clear, lineWidth: 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if icon == choice {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(iconColor.color)
                                    .padding(5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(icon == choice ? .isSelected : [])
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
    @State private var icon: AisleIcon
    @State private var iconColor: AisleIconColor
    private let aisle: Aisle

    init(store: Store, aisle: Aisle) {
        self.store = store
        self.aisle = aisle
        _icon = State(initialValue: aisle.icon)
        _iconColor = State(initialValue: aisle.iconColor)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Icône")
                        .font(.headline)
                    AisleIconGrid(icon: $icon, iconColor: iconColor)

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
                        store.update { try $0.editAisleIcon(aisle.id, icon: icon, iconColor: iconColor) }
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
    @State private var icon: AisleIcon
    private let aisle: Aisle
    init(store: Store, aisle: Aisle) {
        self.store = store
        self.aisle = aisle
        _name = State(initialValue: aisle.name)
        _icon = State(initialValue: aisle.icon)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom du rayon") { TextField("Nom", text: $name) }
                Section("Icône") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                        ForEach(AisleIcon.allCases) { choice in
                            Button { icon = choice } label: {
                                AisleIconView(icon: choice, size: 24)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(
                                        icon == choice ? Color.primary.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if icon == choice {
                                            Image(systemName: "checkmark.circle.fill").font(.caption)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.label)
                            .accessibilityAddTraits(icon == choice ? .isSelected : [])
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
                        store.update { try $0.editAisle(aisle.id, name: name, icon: icon) }
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
                Image("CaddieAppIcon")
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
                    example("Bavette", detail: "2 pièces · Boucherie", icon: .beef)
                    example("Tomates", detail: "500 g · Fruits et légumes", icon: .carrot)
                    example("Dentifrice", detail: "1 tube · Hygiène et entretien", icon: .soapDispenserDroplet)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 24))
                Text("Dix rayons pour commencer, à adapter à votre parcours. Le classement automatique utilise Apple Intelligence lorsqu’il est disponible. Vous gardez toujours la main.")
                    .foregroundStyle(.secondary)
                Label("Vos listes restent disponibles hors connexion et se synchronisent avec iCloud lorsqu’il est disponible.", systemImage: "icloud").font(.footnote)
                Button(action: start) {
                    Text("Commencer ma liste")
                        .font(.headline)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                Text("Ces exemples ne seront pas ajoutés à votre liste.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.background(Color(.systemGroupedBackground)).interactiveDismissDisabled()
    }
    private func example(_ title: String, detail: String, icon: AisleIcon) -> some View {
        HStack(spacing: 16) {
            AisleIconView(icon: icon, size: 26).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
