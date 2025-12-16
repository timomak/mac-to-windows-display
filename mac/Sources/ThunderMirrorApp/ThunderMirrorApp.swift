import SwiftUI

/// ThunderMirror macOS App
///
/// A beautiful SwiftUI interface for streaming Mac display to Windows over Thunderbolt.
@main
struct ThunderMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var streamingState = StreamingState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(streamingState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

/// App delegate for handling app lifecycle and permissions
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Style the window
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

