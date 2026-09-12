import SwiftUI

struct ShoppingView: View {
    @Bindable var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var addPanelPresented = false
    @State private var managing = false
    @State private var pendingManagement = false
    @State private var editing: ListItem?
    @State private var pendingEdit: ListItem?
    private var remaining: Int { store.list.items.filter { !$0.purchased }.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UN PEU D’ORDRE,\nLES COURSES EN PLUS SIMPLE.")
                            .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                        Text(remaining == 0 ? "L’esprit tranquille." : "\(remaining) produit\(remaining > 1 ? "s" : "") à trouver.")
                            .font(.system(.title2, design: .serif, weight: .medium)).monospacedDigit()
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)

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
                        Button("Supprimer les éléments cochés", role: .destructive) {
                            store.update { $0.items.removeAll(where: \.purchased) }
                        }.font(.subheadline)
                    } header: {
                        Label("Achetés · \(purchased.count)", systemImage: "checkmark.circle")
                    }
                }
            }
                .contentMargins(.bottom, 112, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Mes courses")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Gérer les rayons", systemImage: "slider.horizontal.3") { showManagement() }
                    }
                }
                .disabled(store.loadFailed)
                .sheet(isPresented: $managing, onDismiss: restoreAddPanel) { AislesView(store: store) }
                .sheet(item: $editing, onDismiss: restoreAddPanel) { item in EditProductView(store: store, item: item) }
                .fullScreenCover(
                    isPresented: Binding(get: { !store.list.onboarded && !store.loadFailed }, set: { _ in }),
                    onDismiss: restoreAddPanel
                ) {
                    WelcomeView { store.update { $0.onboarded = true } }
                }
                .alert("Mes courses", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("Compris", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
                .onAppear { restoreAddPanel() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshAvailability() } }
            }

            if addPanelPresented {
                AddProductDrawer(store: store) { item in
                    pendingEdit = item
                    addPanelPresented = false
                }
                .onDisappear(perform: presentPendingDestination)
                .zIndex(1)
            }
        }
    }

    private func showManagement() {
        if addPanelPresented {
            pendingManagement = true
            addPanelPresented = false
        } else {
            managing = true
        }
    }

    private func showEditor(_ item: ListItem) {
        if addPanelPresented {
            pendingEdit = item
            addPanelPresented = false
        } else {
            editing = item
        }
    }

    private func presentPendingDestination() {
        if pendingManagement {
            pendingManagement = false
            managing = true
        } else if let pendingEdit {
            self.pendingEdit = nil
            editing = pendingEdit
        }
    }

    private func restoreAddPanel() {
        guard store.list.onboarded, !store.loadFailed, !managing, editing == nil else { return }
        addPanelPresented = true
    }

    @ViewBuilder private func aisleSection(id: UUID?, title: String, symbol: String) -> some View {
        let items = store.list.items.filter { !$0.purchased && $0.aisleID == id }
        if !items.isEmpty {
            Section {
                ForEach(items) { row($0) }
            } header: {
                HStack { Label(title, systemImage: symbol); Spacer(); Text("\(items.count)").monospacedDigit() }
            }
        }
    }
    private func row(_ item: ListItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { store.update { $0.toggle(item.id) } } label: {
                    Image(systemName: item.purchased ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(item.purchased ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(item.purchased ? "Remettre à acheter" : "Marquer acheté")
                    .accessibilityValue(store.list.product(item.productID)?.name ?? "Produit")
                Button { showEditor(item) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.list.product(item.productID)?.name ?? "Produit")
                            .font(.body.weight(.medium)).strikethrough(item.purchased)
                        if !item.note.isEmpty { Text(item.note).font(.subheadline).foregroundStyle(.secondary) }
                        if store.classifying.contains(item.id) { Text("Recherche du rayon…").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .foregroundStyle(item.purchased ? .secondary : .primary)
                }.buttonStyle(.plain)
            }
            if let suggestion = item.suggestion, !item.purchased {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Un nouveau rayon pour ce produit ?").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Créer « \(suggestion) »") { store.acceptSuggestion(item.id) }
                            .buttonStyle(.bordered).font(.subheadline)
                        Spacer()
                        Button("Ignorer", systemImage: "xmark") { store.update { $0.dismissSuggestion(item.id) } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).frame(width: 44, height: 44)
                    }
                }.padding(.leading, 52)
            }
        }.padding(.vertical, 3)
            .swipeActions { Button("Supprimer", role: .destructive) { store.update { $0.items.removeAll { $0.id == item.id } } } }
    }
}

struct AddProductDrawer: View {
    @Bindable var store: Store
    var openExisting: (ListItem) -> Void
    @FocusState private var focused: Bool
    @State private var name = ""
    @State private var note = ""
    @State private var expanded = false
    @State private var focusAfterExpansion = false
    @State private var focusTask: Task<Void, Never>?
    @GestureState private var dragTranslation: CGFloat = 0
    private let compactHeight: CGFloat = 104
    private let topCornerRadius: CGFloat = 38
    private var existing: ListItem? {
        guard let product = store.list.matching(name) else { return nil }
        return store.list.items.first { $0.productID == product.id }
    }

    var body: some View {
        GeometryReader { proxy in
            let expandedHeight = min(proxy.size.height - 20, 720)
            let height = drawerHeight(expandedHeight: expandedHeight)

            drawerSurface(height: height, expandedHeight: expandedHeight)
                .animation(.snappy(duration: 0.32, extraBounce: 0), value: expanded)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: focused) { _, isFocused in
            if isFocused, !expanded {
                requestExpansionAndFocus()
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded, focusAfterExpansion {
                focusTask?.cancel()
                focusTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled, focusAfterExpansion, expanded else { return }
                    focused = true
                    focusAfterExpansion = false
                }
            } else {
                focusTask?.cancel()
                focusAfterExpansion = false
                focused = false
            }
        }
        .onDisappear { focusTask?.cancel() }
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: topCornerRadius
            ),
            style: .continuous
        )
    }

    @ViewBuilder
    private func drawerSurface(height: CGFloat, expandedHeight: CGFloat) -> some View {
        let surface = sheetContent(isCompact: height < compactHeight + 12)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: height, alignment: .top)
            .background(Color(.systemBackground))
            .clipShape(sheetShape)
            .contentShape(Rectangle())

        if expanded {
            surface.overlay(alignment: .top) {
                dragHandle(expandedHeight: expandedHeight)
            }
        } else {
            surface
                .overlay(alignment: .top) { dragHandleVisual }
                .highPriorityGesture(drawerDrag(expandedHeight: expandedHeight), including: .all)
        }
    }

    private var dragHandleVisual: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.38))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .allowsHitTesting(false)
    }

    private func dragHandle(expandedHeight: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { dragHandleVisual }
            .gesture(drawerDrag(expandedHeight: expandedHeight))
    }

    private var primaryField: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
            TextField("Ajouter un produit", text: $name)
                .focused($focused)
                .submitLabel(.next)
            Button("Ajouter", systemImage: "arrow.up.circle.fill") { addProduct() }
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(ShoppingList.clean(name).isEmpty || existing != nil)
                .frame(width: 40, height: 40)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        }
        .contentShape(Capsule())
        .simultaneousGesture(
            TapGesture().onEnded {
                if !expanded { requestExpansionAndFocus() }
            }
        )
        .accessibilityHint("Touchez ou faites glisser vers le haut pour ouvrir")
    }

    private func sheetContent(isCompact: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    primaryField
                    TextField("Quantité ou précision (facultatif)", text: $note)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.top, 40)
                    Text("Précisez le produit dans son nom : « Tomates en conserve ». Le rayon sera choisi à partir de ce nom.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                HStack {
                    Text(name.isEmpty ? "Pour vous inspirer" : "Suggestions")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)

                LazyVStack(spacing: 0) {
                    ForEach(store.list.suggestions(name)) { product in
                        let item = store.list.items.first { $0.productID == product.id }
                        Button {
                            if let item { focused = false; openExisting(item) } else { name = product.name }
                        } label: {
                            HStack {
                                Text(product.name).foregroundStyle(.primary)
                                Spacer()
                                if let item {
                                    Text(item.purchased ? "Acheté" : "Déjà dans la liste")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                if let existing {
                    Button("Retrouver le produit déjà présent") { focused = false; openExisting(existing) }
                        .padding(.vertical, 8)
                }
                if let error = store.error {
                    Text(error).foregroundStyle(.red).font(.footnote).padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDisabled(isCompact)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.top)
    }

    private func addProduct() {
        guard store.add(name: name, note: note) else { return }
        name = ""
        note = ""
        focused = false
        expanded = false
    }

    private func requestExpansionAndFocus() {
        guard !expanded else {
            focused = true
            return
        }
        focusAfterExpansion = true
        focused = false
        expanded = true
    }

    private func drawerHeight(expandedHeight: CGFloat) -> CGFloat {
        let settledHeight = expanded ? expandedHeight : compactHeight
        return min(max(settledHeight - dragTranslation, compactHeight), expandedHeight)
    }

    private func drawerDrag(expandedHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let settledHeight = expanded ? expandedHeight : compactHeight
                let projectedHeight = min(
                    max(settledHeight - value.predictedEndTranslation.height, compactHeight),
                    expandedHeight
                )
                expanded = projectedHeight > (compactHeight + expandedHeight) / 2
                if !expanded { focused = false }
            }
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
                }
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
    @State private var renaming: Aisle?
    @State private var renamed = ""
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
                        Button { renamed = aisle.name; renaming = aisle } label: {
                            Label(aisle.name, systemImage: aisle.symbol).foregroundStyle(.primary).frame(minHeight: 36)
                        }
                    }
                    .onMove { source, destination in store.update { $0.aisles.move(fromOffsets: source, toOffset: destination) } }
                    .onDelete { offsets in
                        let ids = offsets.map { store.list.aisles[$0].id }
                        store.update { list in ids.forEach { list.deleteAisle($0) } }
                    }
                } header: { Text("Votre parcours") } footer: {
                    Text("Glissez les poignées pour suivre votre parcours en magasin. Touchez un rayon pour le renommer. Supprimer un rayon conserve ses produits dans « À classer » et oublie ses classements mémorisés.")
                }
                if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Mes rayons").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
            .alert("Renommer le rayon", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nom du rayon", text: $renamed)
                Button("Annuler", role: .cancel) { renaming = nil }
                Button("Enregistrer") {
                    if let renaming { store.update { try $0.renameAisle(renaming.id, name: renamed) } }
                    renaming = nil
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
                Image(systemName: "basket.fill").font(.system(size: 56)).foregroundStyle(.tint).padding(.top, 40)
                Text("Moins d’allers-retours.\nPlus de simplicité.")
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
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
