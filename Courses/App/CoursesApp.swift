import SwiftUI

@main
struct CoursesApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup { ShoppingView(store: store).tint(Color(red: 0.16, green: 0.39, blue: 0.28)) }
    }
}
