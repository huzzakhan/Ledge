// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ledge",
            path: "Sources/Ledge",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
