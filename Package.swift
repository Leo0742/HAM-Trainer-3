// swift-tools-version: 5.10
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
var excludedPaths = [
    ".github",
    ".gitignore",
    "ContentAuthored",
    "ContentOverrides",
    "ContentRaw",
    "ExamSources",
    "HAMTrainer3.xcodeproj",
    "HAMTrainer/Info.plist",
    "README.md",
    "Tests",
    "Tools",
    "docs"
]
if FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("Build").path) {
    excludedPaths.append("Build")
}

let package = Package(
    name: "HAMTrainer3",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HAMTrainer3", targets: ["HAMTrainer3"])],
    targets: [
        .executableTarget(
            name: "HAMTrainer3",
            path: ".",
            exclude: excludedPaths,
            sources: ["HAMTrainer"],
            resources: [.copy("Content")]
        )
    ]
)
