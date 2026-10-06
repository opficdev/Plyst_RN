//
//  SQLiteClipSearchTermRecord.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation
import GRDB
import SQLiteData

/// 최근 검색어 한 건의 영구 저장 필드입니다. 클립 테이블과 관계가 없는 로컬 전용 테이블이며 동기화 대상이 아닙니다.
@Table("clipSearchTerms")
struct SQLiteClipSearchTermRecord: Sendable {
    /// 0이 가장 최근입니다. 저장할 때마다 0부터 다시 매깁니다.
    let position: Int
    var term: String
}

extension SQLiteClipSearchTermRecord {
    static func createTable(in connection: Database) throws {
        let columns = Self.columns
        try connection.create(table: tableName, options: .strict) { table in
            table.column(columns.position.name, .integer).primaryKey().notNull().check { 0 <= $0 }
            table.column(columns.term.name, .text).notNull().unique().check { $0 != "" }
        }
    }
}
