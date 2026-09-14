import SwiftUI

@main
struct CaddieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { ShoppingView(store: store).tint(Color.primary) }
    }
}
