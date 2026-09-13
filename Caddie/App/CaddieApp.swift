import SwiftUI

@main
struct CaddieApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { ShoppingView(store: store).tint(Color.primary) }
    }
}
