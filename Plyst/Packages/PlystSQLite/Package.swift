// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlystSQLite",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PlystSQLite", type: .dynamic, targets: ["PlystSQLite"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", exact: "0.39.2"),
    ],
    targets: [
        .target(
            name: "PlystSQLite",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
            ]
        ),
    ]
)
