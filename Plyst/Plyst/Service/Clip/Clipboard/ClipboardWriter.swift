//
//  ClipboardWriter.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

enum ClipboardWriteContent: Equatable, Sendable {
    case text(String)
    /// 검증된 이미지 원본 바이트와 해당 표현의 타입 식별자
    case image(data: Data, contentType: String)
}

enum ClipboardWriteResult: Equatable, Sendable {
    /// 쓰기 직후 첫 항목에서 요청한 표현을 확인했음
    /// 이후의 유지나 다른 앱의 붙여넣기 성공을 보장하지 않음
    case observed
    /// 요청한 표현을 확인하지 못했음
    /// 클립보드가 변경되지 않았다는 뜻은 아님
    case notObserved
}

/// UIKit 객체 대신 값 타입을 받아 명시적인 요청에서만 클립보드에 씀
/// 취소와 오류는 쓰기를 시작하기 전에만 던짐
/// 쓰기 이후에는 관찰 결과를 반환해야 함
protocol ClipboardWriter: Sendable {
    func write(_ content: ClipboardWriteContent) async throws -> ClipboardWriteResult
}
