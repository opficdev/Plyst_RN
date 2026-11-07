//
//  ClipboardService.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation
import PlystCore

/// 사용자 요청에 따라 클립을 저장하거나 다시 복사
/// 초기화 시에는 클립보드에 접근하지 않음
/// 순서와 결과 판정은 코어의 ClipboardOperations가 맡고 이 타입은 읽기, 플랫폼 클립보드 직렬화, 쓰기 구현 보유를 담당
/// 같은 클립보드를 사용하는 호출부는 이 서비스 하나와 이미지 루트별 ClipCoreAdapter 하나를 공유해야 함
actor ClipboardService {
    private let queue = DispatchSerialQueue(label: "opfic.Plyst.ClipboardService")
    private let core: ClipCoreAdapter
    private let reader: any ClipboardReader
    private let writer: any ClipboardWriter

    /// 코어 잠금 대기가 협력 스레드를 막지 않도록 전용 직렬 큐에서 실행
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(
        core: ClipCoreAdapter,
        reader: any ClipboardReader = SystemClipboardReader(),
        writer: any ClipboardWriter = SystemClipboardWriter(localOnly: true, expirationDate: nil)
    ) {
        self.core = core
        self.reader = reader
        self.writer = writer
    }

    /// 저장소 오류와 CancellationError는 그대로 전파
    /// await가 없어 읽기와 저장 사이에 다른 호출이 끼어들지 않음
    func saveCurrentClipboard() throws -> ClipboardSaveResult {
        switch try reader.read() {
        case .text(let text):
            return try core.saveClipboardText(text)
        case .image(let data):
            return try core.saveClipboardImage(data)
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
        try core.copy(id: id, writer: writer)
    }
}
