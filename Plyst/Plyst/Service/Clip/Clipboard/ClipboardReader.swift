//
//  ClipboardReader.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

enum ClipboardReadResult: Equatable, Sendable {
    case text(String)
    /// 클립보드가 제공한 이미지 표현의 바이트입니다. 검증과 파일 저장은 이미지 서비스에서 수행합니다.
    case image(Data)
    case empty
    case unsupported
    /// 지원 형식의 값을 얻지 못했거나 읽는 동안 내용이 변경되었습니다. 권한 거절 여부를 확정하지 않습니다.
    case accessFailed
}

/// 명시적인 호출에서만 클립보드를 읽고 UIKit 객체 대신 값 타입을 반환합니다.
protocol ClipboardReader: Sendable {
    func read() async throws -> ClipboardReadResult
}
