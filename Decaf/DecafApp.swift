import SwiftUI

@main
struct DecafApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "cup.and.saucer.fill")
        }
    }
}
