// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HAMTrainer3",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HAMTrainer3", targets: ["HAMTrainer3"])],
    targets: [
        .executableTarget(
            name: "HAMTrainer3",
            path: ".",
            exclude: [
                ".github",
                ".gitignore",
                "Build",
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
            ],
            sources: ["HAMTrainer"],
            resources: [.copy("Content")]
        )
    ]
)
