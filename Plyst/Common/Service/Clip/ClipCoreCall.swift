//
//  ClipCoreCall.swift
//  Plyst
//
//  Created by opfic on 11/6/26.
//

import Foundation
import OSLog
import PlystCore

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
    category: "ClipCoreCall"
)

/// 코어 저장소 오류를 저장소 Service 오류로 변환
func clipStorageError(
    _ error: any Error,
    fallback: any Error
) -> any Error {
    if error is CancellationError || error is ClipStorageError { return error }
    guard let error = error as? ClipStoreError else { return fallback }
    switch error {
    case .DuplicateId(let id):
        return UUID(uuidString: id).map(ClipStorageError.duplicateID) ?? fallback
    case .NotFound(let id):
        return UUID(uuidString: id).map(ClipStorageError.notFound) ?? fallback
    case .InvalidContent:
        return ClipStorageError.invalidContent
    case .ReadFailed:
        return ClipStorageError.readFailed
    case .WriteFailed:
        return ClipStorageError.writeFailed
    case .CorruptedData:
        return ClipStorageError.corruptedData
    }
}

/// 오류 설명에는 SQL과 저장값이 포함될 수 있어 종류와 코드만 기록
func logClipCoreFailure(
    _ error: any Error,
    operation: String
) {
    if error is CancellationError {
        logger.debug("\(operation, privacy: .public) 취소")
        return
    }
    if let error = error as? ClipStoreError {
        switch error {
        case let .ReadFailed(code, extendedCode), let .WriteFailed(code, extendedCode), let .CorruptedData(code, extendedCode):
            logger.error("\(operation, privacy: .public) 실패: SQLite 코드 \(code, privacy: .public), 확장 코드 \(extendedCode, privacy: .public)")
        case .DuplicateId:
            logger.error("\(operation, privacy: .public) 실패: duplicateID")
        case .NotFound:
            logger.error("\(operation, privacy: .public) 실패: notFound")
        case .InvalidContent:
            logger.error("\(operation, privacy: .public) 실패: invalidContent")
        }
        return
    }
    if let error = error as? ClipStorageError {
        let reason = switch error {
        case .duplicateID: "duplicateID"
        case .notFound: "notFound"
        case .invalidContent: "invalidContent"
        case .readFailed: "readFailed"
        case .writeFailed: "writeFailed"
        case .corruptedData: "corruptedData"
        }
        logger.error("\(operation, privacy: .public) 실패: \(reason, privacy: .public)")
        return
    }
    let error = error as NSError
    logger.error("\(operation, privacy: .public) 실패: 오류 영역 \(error.domain, privacy: .public), 코드 \(error.code, privacy: .public)")
}
