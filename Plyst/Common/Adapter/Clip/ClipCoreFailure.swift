//
//  ClipCoreFailure.swift
//  Plyst
//
//  Created by opfic on 11/7/26.
//

import Foundation
import OSLog
import PlystCore

/// 코어 오류의 기록과 어댑터 오류 변환
enum ClipCoreFailure {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst",
        category: String(describing: ClipCoreAdapter.self)
    )

    /// 코어 저장소 오류를 어댑터 저장소 오류로 변환
    static func storageError(
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
    static func log(
        _ error: any Error,
        operation: String
    ) {
        if let error = error as? ClipOperationError {
            switch error {
            case .Cancelled:
                Self.logger.debug("\(operation, privacy: .public) 취소")
            case .CorruptedImage:
                Self.logger.error("\(operation, privacy: .public) 실패: corruptedImage")
            case .ClipboardWriteFailed:
                Self.logger.error("\(operation, privacy: .public) 실패: clipboardWrite")
            case .Storage(let error):
                log(error, operation: operation)
            case .Files(let error):
                let reason = switch error {
                case .InvalidRoot: "invalidRoot"
                case .UnsafePath: "unsafePath"
                case .ReadFailed: "readFailed"
                case .WriteFailed: "writeFailed"
                case .DeleteFailed: "deleteFailed"
                case .NotFound: "notFound"
                case .SizeMismatch: "sizeMismatch"
                }
                Self.logger.error("\(operation, privacy: .public) 실패: \(reason, privacy: .public)")
            }
            return
        }
        if error is CancellationError {
            Self.logger.debug("\(operation, privacy: .public) 취소")
            return
        }
        if let error = error as? ClipStoreError {
            switch error {
            case let .ReadFailed(code, extendedCode), let .WriteFailed(code, extendedCode), let .CorruptedData(code, extendedCode):
                Self.logger.error("\(operation, privacy: .public) 실패: SQLite 코드 \(code, privacy: .public), 확장 코드 \(extendedCode, privacy: .public)")
            case .DuplicateId:
                Self.logger.error("\(operation, privacy: .public) 실패: duplicateID")
            case .NotFound:
                Self.logger.error("\(operation, privacy: .public) 실패: notFound")
            case .InvalidContent:
                Self.logger.error("\(operation, privacy: .public) 실패: invalidContent")
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
            Self.logger.error("\(operation, privacy: .public) 실패: \(reason, privacy: .public)")
            return
        }
        let error = error as NSError
        Self.logger.error("\(operation, privacy: .public) 실패: 오류 영역 \(error.domain, privacy: .public), 코드 \(error.code, privacy: .public)")
    }

    static func operationError(
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
            return storageError(error, fallback: fallback)
        case .Files(let error):
            return imageFileError(error, fallback: fallback)
        }
    }

    private static func imageFileError(
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
}
