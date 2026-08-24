import AppKit
import SwiftUI

/// Opt-in visual QA hook. It is inert in normal launches. A snapshot build can
/// pass --snapshot PATH plus optional --appearance/--width/--height arguments.
struct SnapshotCaptureView: View {
    var body: some View {
        Color.clear.frame(width: 0, height: 0).task { await captureIfRequested() }
    }

    @MainActor
    private func captureIfRequested() async {
        let arguments = CommandLine.arguments
        guard let outputIndex = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(outputIndex + 1) else { return }
        let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
        try? await Task.sleep(for: .seconds(1))
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let content = window.contentView else {
            try? "No visible window; windows=\(NSApp.windows.count); args=\(arguments)".write(to: outputURL.appendingPathExtension("log"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil); return
        }
        let width = argument("--width", in: arguments).flatMap(Double.init) ?? 1180
        let height = argument("--height", in: arguments).flatMap(Double.init) ?? 780
        window.setContentSize(NSSize(width: width, height: height))
        if argument("--appearance", in: arguments) == "dark" { window.appearance = NSAppearance(named: .darkAqua) }
        if argument("--appearance", in: arguments) == "light" { window.appearance = NSAppearance(named: .aqua) }
        try? await Task.sleep(for: .milliseconds(600))
        guard let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { NSApp.terminate(nil); return }
        content.cacheDisplay(in: content.bounds, to: representation)
        if let data = representation.representation(using: .png, properties: [:]) {
            do { try data.write(to: outputURL, options: .atomic) }
            catch { try? "PNG write failed: \(error)".write(to: outputURL.appendingPathExtension("log"), atomically: true, encoding: .utf8) }
        } else {
            try? "PNG representation failed".write(to: outputURL.appendingPathExtension("log"), atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }

    private func argument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
