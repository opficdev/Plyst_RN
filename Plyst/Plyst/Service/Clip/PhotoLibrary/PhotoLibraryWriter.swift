//
//  PhotoLibraryWriter.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

enum PhotoLibraryAuthorization: Equatable, Sendable {
    case authorized
    case denied
    case restricted
}

/// 사진 추가 권한과 원본 쓰기를 분리해 권한이 없을 때 파일을 읽지 않도록 합니다.
protocol PhotoLibraryWriter: Sendable {
    func requestAddAuthorization() async throws -> PhotoLibraryAuthorization

    /// 쓰기 요청 전에는 취소할 수 있습니다. 요청 후에는 확정된 쓰기의 완료 결과를 반환합니다.
    func write(
        _ data: Data,
        contentType: String
    ) async throws
}
