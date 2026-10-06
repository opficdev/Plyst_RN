//
//  ClipImageDownloadError.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

/// 요청 URL이나 응답 내용을 포함하지 않는 오류입니다.
enum ClipImageDownloadError: Error, Equatable, Sendable {
    case unsupportedURL
    case invalidResponse
    case notImage
    case tooLarge
    case requestFailed
}
