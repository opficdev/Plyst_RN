//
//  ClipboardService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import PlystCore

enum ClipboardSaveResult: Equatable, Sendable {
    case saved(Clip)
    /// 이미지 원본과 클립 기록은 저장됐지만 pending 표시 파일을 제거하지 못했음
    /// recoverPendingCleanup()을 호출해야 정리를 다시 시도
    case savedWithPendingCleanup(Clip, fileID: UUID)
    case empty
    case unsupported
    case accessFailed
    case invalidImage
}

/// 사용자 요청에 따라 클립을 저장하거나 다시 복사
/// 초기화 시에는 클립보드에 접근하지 않음
/// 순서와 결과 판정은 코어의 ClipboardOperations가 맡고 이 타입은 읽기, 실행 위치, 값 변환을 담당
/// 같은 클립보드를 사용하는 호출부는 이 서비스 하나와 이미지 루트별 ClipImageService 하나를 공유해야 함
actor ClipboardService {
    private let queue = DispatchSerialQueue(label: "opfic.Plyst.ClipboardService")
    private let core: ClipboardOperations
    private let reader: any ClipboardReader
    private let writer: any ClipboardWriter

    /// 코어 잠금 대기가 협력 스레드를 막지 않도록 전용 직렬 큐에서 실행
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(
        images: ClipImageService,
        reader: any ClipboardReader = SystemClipboardReader(),
        writer: any ClipboardWriter = SystemClipboardWriter(localOnly: true, expirationDate: nil)
    ) {
        core = ClipboardOperations(images: images.core)
        self.reader = reader
        self.writer = writer
    }

    /// 저장소 오류와 CancellationError는 그대로 전파
    /// 저장 확정 이후에는 취소를 다시 확인하지 않음
    func saveCurrentClipboard() throws -> ClipboardSaveResult {
        switch try reader.read() {
        case .text(let text):
            let saved = try clipCoreCall(fallback: ClipStorageError.writeFailed) {
                try core.saveText(text: text, cancellation: $0)
            }
            return try Self.saveResult(saved)
        case .image(let data):
            do {
                let properties = try ClipImageCodec.validated(data)
                let saved = try clipCoreCall(fallback: ClipImageFileError.writeFailed) {
                    try core.saveImage(data: data, properties: properties, cancellation: $0)
                }
                return try Self.saveResult(saved)
            } catch let error as ClipImageFileError {
                switch error {
                case .invalidImage:
                    return .invalidImage
                case .unsupportedImage:
                    return .unsupported
                default:
                    throw error
                }
            }
        case .empty:
            return .empty
        case .unsupported:
            return .unsupported
        case .accessFailed:
            return .accessFailed
        }
    }

    /// 쓰기 전 오류는 전파
    /// 쓰기가 확인된 이후의 사용 시각 저장 실패는 부분 성공으로 반환
    func copy(id: Clip.ID) throws -> ClipboardCopyResult {
        let copied = try clipCoreCall(fallback: ClipImageFileError.readFailed) {
            try core.copy(id: id.uuidString, writer: writer, cancellation: $0)
        }
        switch copied {
        case .copied(let clip):
            return .copied(try Self.clip(clip))
        case .writeNotObserved:
            return .writeNotObserved(id)
        case let .copiedWithoutLastUsedAt(clip, copiedAt, failure):
            return .copiedWithoutLastUsedAt(
                clip: try Self.clip(clip),
                copiedAt: Date(timeIntervalSinceReferenceDate: copiedAt),
                failure: ClipboardUsageUpdateFailure(coreValue: failure)
            )
        }
    }

    private static func saveResult(_ value: ClipboardSaveValue) throws -> ClipboardSaveResult {
        switch value {
        case .saved(let clip):
            return .saved(try Self.clip(clip))
        case let .savedWithPendingCleanup(clip, fileId):
            guard let fileID = UUID(uuidString: fileId) else { throw ClipStorageError.corruptedData }
            return .savedWithPendingCleanup(try Self.clip(clip), fileID: fileID)
        case .empty:
            return .empty
        }
    }

    /// 코어가 검사한 식별자라 변환은 실패하지 않음
    private static func clip(_ value: ClipValue) throws -> Clip {
        guard let clip = Clip(coreValue: value) else { throw ClipStorageError.corruptedData }
        return clip
    }
}
