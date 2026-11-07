//
//  ClipCoreCall.swift
//  Plyst
//
//  Created by opfic on 11/6/26.
//

import Foundation
import OSLog
import PlystCore

/// 실행 중인 Task의 취소 상태를 코어 판정 지점에 전달
final class ClipTaskCancellation: ClipCancellationSource {
    func isCancelled() -> Bool { Task.isCancelled }
}

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
    category: "ClipCoreCall"
)

/// 코어 작업을 호출하고 오류를 Service 오류로 변환
/// 패닉은 호출별 대체 오류로 전달
func clipCoreCall<Value>(
    _ name: String = #function,
    fallback: any Error,
    operation: (ClipTaskCancellation) throws -> Value
) throws -> Value {
    do {
        return try operation(ClipTaskCancellation())
    } catch {
        logClipCoreFailure(error, operation: name)
        throw clipServiceError(error, fallback: fallback)
    }
}

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
    if let error = error as? ClipOperationError {
        switch error {
        case .Cancelled:
            logger.debug("\(operation, privacy: .public) 취소")
        case .CorruptedImage:
            logger.error("\(operation, privacy: .public) 실패: corruptedImage")
        case .ClipboardWriteFailed:
            logger.error("\(operation, privacy: .public) 실패: clipboardWrite")
        case .Storage(let error):
            logClipCoreFailure(error, operation: operation)
        case .Files(let error):
            logger.error("\(operation, privacy: .public) 실패: \(String(describing: error), privacy: .public)")
        }
        return
    }
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

private func clipServiceError(
    _ error: any Error,
    fallback: any Error
) -> any Error {
    guard let error = error as? ClipOperationError else { return fallback }
    switch error {
    case .Cancelled:
        return CancellationError()
    case .CorruptedImage(let fileId):
        return UUID(uuidString: fileId).map(ClipImageFileError.corruptedImage) ?? fallback
    case .ClipboardWriteFailed:
        return fallback
    case .Storage(let error):
        return clipStorageError(error, fallback: fallback)
    case .Files(let error):
        return clipImageFileError(error, fallback: fallback)
    }
}

private func clipImageFileError(
    _ error: ClipImageFilesError,
    fallback: any Error
) -> any Error {
    switch error {
    case .InvalidRoot: ClipImageFileError.invalidRoot
    case .UnsafePath: ClipImageFileError.unsafePath
    case .ReadFailed: ClipImageFileError.readFailed
    case .WriteFailed: ClipImageFileError.writeFailed
    case .DeleteFailed: ClipImageFileError.deleteFailed
    case .NotFound(let fileId): UUID(uuidString: fileId).map(ClipImageFileError.notFound) ?? fallback
    case .SizeMismatch(let fileId): UUID(uuidString: fileId).map(ClipImageFileError.corruptedImage) ?? fallback
    }
}
