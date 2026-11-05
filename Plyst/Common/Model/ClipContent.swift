//
//  ClipContent.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation
import PlystCore

enum ClipContent: Equatable, Sendable {

    /// URL을 포함한 원본 문자열을 정규화하지 않고 저장
    case text(String)
    case image(ClipImageMetadata)

    /// 앞뒤 공백을 제외한 전체가 공백 없는 단일 http 또는 https URL인지 여부
    /// 저장 형식은 그대로 텍스트
    /// 화면에서 아이콘을 고를 때만 사용
    /// 문장 안에 섞인 URL은 링크로 보지 않음
    var isWebLink: Bool {
        guard case .text(let text) = self else { return false }
        return clipTextIsWebLink(text: text)
    }

    /// 이미지의 메타데이터만 검증
    /// 이미지 디코딩과 파일 존재 여부 검사는 이미지 파일 서비스의 책임
    var isValid: Bool {
        switch self {
        case .text(let text):
            return clipTextIsValid(text: text)
        case .image(let image):
            return clipImageIsValid(
                contentType: image.contentType,
                pixelWidth: Int64(image.pixelWidth),
                pixelHeight: Int64(image.pixelHeight),
                byteCount: Int64(image.byteCount)
            )
        }
    }

    var coreValue: ClipContentValue {
        switch self {
        case .text(let text):
            return .text(text: text)
        case .image(let image):
            return .image(
                fileId: image.fileID.uuidString,
                contentType: image.contentType,
                pixelWidth: Int64(image.pixelWidth),
                pixelHeight: Int64(image.pixelHeight),
                byteCount: Int64(image.byteCount)
            )
        }
    }
}
