import SwiftUI

@main
struct Pocket_DemoApp: App {
    @State private var showDictation = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fullScreenCover(isPresented: $showDictation) {
                    SwitchBackView {
                        showDictation = false
                    }
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == PKConstants.URLScheme.scheme else { return }
        if url.host == PKConstants.URLScheme.dictateHost {
            showDictation = true
        }
    }
}
