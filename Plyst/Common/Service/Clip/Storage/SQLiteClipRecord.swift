//
//  SQLiteClipRecord.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import GRDB
import SQLiteData

/// 영구 저장 필드와 도메인 값을 분리합니다. 날짜는 기준 시각으로부터의 간격을 저장하여 정밀도를 보존합니다.
@Table("clips")
struct SQLiteClipRecord: Sendable {
    let id: UUID
    var kind: ContentKind
    var text: String?
    var imageFileID: UUID?
    var imageContentType: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int?
    var name: String?
    var isPinned: Int
    var memo: String?
    var createdAt: Double
    var lastUsedAt: Double?

    enum ContentKind: String, QueryBindable, Sendable {
        case text
        case image
    }
}

extension SQLiteClipRecord {

    init(_ clip: Clip) {
        self.init(
            id: clip.id, kind: .text, name: clip.name, isPinned: clip.isPinned ? 1 : 0,
            memo: clip.memo, createdAt: clip.createdAt.timeIntervalSinceReferenceDate,
            lastUsedAt: clip.lastUsedAt?.timeIntervalSinceReferenceDate
        )
        switch clip.content {
        case .text(let value):
            text = value
        case .image(let image):
            kind = .image
            imageFileID = image.fileID
            imageContentType = image.contentType
            pixelWidth = image.pixelWidth
            pixelHeight = image.pixelHeight
            byteCount = image.byteCount
        }
    }

    func clip() throws -> Clip {
        let content: ClipContent
        switch kind {
        case .text:
            guard let text, imageFileID == nil, imageContentType == nil,
                  pixelWidth == nil, pixelHeight == nil, byteCount == nil else {
                throw ClipStorageError.corruptedData
            }
            content = .text(text)
        case .image:
            guard text == nil, let imageFileID, let imageContentType, let pixelWidth, let pixelHeight, let byteCount else {
                throw ClipStorageError.corruptedData
            }
            content = .image(ClipImageMetadata(
                fileID: imageFileID, contentType: imageContentType,
                pixelWidth: pixelWidth, pixelHeight: pixelHeight, byteCount: byteCount
            ))
        }
        guard content.isValid, createdAt.isFinite, lastUsedAt?.isFinite != false, isPinned == 0 || isPinned == 1 else {
            throw ClipStorageError.corruptedData
        }
        return Clip(
            id: id, content: content, name: name, isPinned: isPinned == 1, memo: memo,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            lastUsedAt: lastUsedAt.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }

    /// clips.sqlite의 모든 스키마 마이그레이션을 이 마이그레이터 하나에 등록합니다.
    /// 별도의 DatabaseMigrator를 만들면 hasBeenSuperseded 판정으로 기존 저장소가 corruptedData가 되므로, 새 마이그레이션은 이 목록 끝에 추가합니다.
    static func migrate(_ database: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("CreateClips") { connection in
            try createTable(in: connection)
        }
        migrator.registerMigration("CreateClipSearchTerms") { connection in
            try SQLiteClipSearchTermRecord.createTable(in: connection)
        }
        if try database.read({ try migrator.hasBeenSuperseded($0) }) {
            throw ClipStorageError.corruptedData
        }
        try migrator.migrate(database)
    }

    private static func createTable(in connection: Database) throws {
        let columns = Self.columns
        try connection.create(table: tableName, options: .strict) { table in
            table.column(columns.id.name, .text).primaryKey().notNull()
            table.column(columns.kind.name, .text).notNull().check {
                $0 == ContentKind.text.rawValue || $0 == ContentKind.image.rawValue
            }
            table.column(columns.text.name, .text)
            table.column(columns.imageFileID.name, .text)
            table.column(columns.imageContentType.name, .text)
            table.column(columns.pixelWidth.name, .integer)
            table.column(columns.pixelHeight.name, .integer)
            table.column(columns.byteCount.name, .integer)
            table.column(columns.name.name, .text)
            table.column(columns.isPinned.name, .integer).notNull().check { $0 == 0 || $0 == 1 }
            table.column(columns.memo.name, .text)
            table.column(columns.createdAt.name, .real).notNull()
            table.column(columns.lastUsedAt.name, .real)

            let kind = Column(columns.kind.name)
            let text = Column(columns.text.name)
            let imageFileID = Column(columns.imageFileID.name)
            let imageContentType = Column(columns.imageContentType.name)
            let pixelWidth = Column(columns.pixelWidth.name)
            let pixelHeight = Column(columns.pixelHeight.name)
            let byteCount = Column(columns.byteCount.name)
            let textContent = kind == ContentKind.text.rawValue && text != nil
                && imageFileID == nil && imageContentType == nil
                && pixelWidth == nil && pixelHeight == nil && byteCount == nil
            let imageContent = kind == ContentKind.image.rawValue && text == nil
                && imageFileID != nil && imageContentType != nil
                && pixelWidth != nil && 0 < pixelWidth
                && pixelHeight != nil && 0 < pixelHeight
                && byteCount != nil && 0 < byteCount
            table.check(textContent || imageContent)
        }
    }
}
