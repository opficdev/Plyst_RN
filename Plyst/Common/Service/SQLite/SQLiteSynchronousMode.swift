//
//  SQLiteSynchronousMode.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import GRDB

/// SQLite의 디스크 동기화 수준입니다. 저장값은 SQLite가 정의한 PRAGMA 값과 같습니다.
enum SQLiteSynchronousMode: Int, Sendable {
    case off = 0
    case normal = 1
    case full = 2
    case extra = 3
}

extension Database {

    /// 활성 트랜잭션 밖에서 호출하여 현재 연결의 동기화 수준을 설정합니다.
    func setSynchronousMode(_ mode: SQLiteSynchronousMode) throws {
        try execute(sql: "PRAGMA synchronous = \(mode.rawValue)")
    }
}
