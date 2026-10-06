//
//  ClipContent.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import Foundation

enum ClipContent: Equatable, Sendable {

    /// URL을 포함한 원본 문자열을 정규화하지 않고 저장합니다.
    case text(String)
    case image(ClipImageMetadata)

    /// 앞뒤 공백을 제외한 전체가 공백 없는 단일 http 또는 https URL인지 여부입니다.
    /// 저장 형식은 그대로 텍스트이며, 화면에서 아이콘을 고를 때만 사용합니다. 문장 안에 섞인 URL은 링크로 보지 않습니다.
    var isWebLink: Bool {
        guard case .text(let text) = self else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(),
              !host.isEmpty else { return false }
        return true
    }

    /// 이미지의 메타데이터만 검증합니다. 이미지 디코딩과 파일 존재 여부 검사는 이미지 파일 서비스의 책임입니다.
    var isValid: Bool {
        switch self {
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image(let image):
            return image.isValid
        }
    }
}
