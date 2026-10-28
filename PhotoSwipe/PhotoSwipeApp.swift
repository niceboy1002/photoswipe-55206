import SwiftUI

@main
struct PhotoSwipeApp: App {
    @StateObject private var library = PhotoLibrary.shared
    @StateObject private var pending = PendingStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(pending)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
