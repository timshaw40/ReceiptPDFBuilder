import SwiftUI

@main
struct ReceiptPDFBuilderApp: App {
    var body: some Scene {
        WindowGroup("Receipt PDF Builder") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}