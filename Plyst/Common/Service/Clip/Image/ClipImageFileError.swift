//
//  ClipImageFileError.swift
//  Plyst
//
//  Created by opfic on 9/29/26.
//

import Foundation

/// 파일 경로나 저장된 이미지 내용을 포함하지 않는 오류입니다.
enum ClipImageFileError: Error, Equatable, Sendable {
    case invalidRoot
    case unsafePath
    case unsupportedImage
    case invalidImage
    case corruptedImage(UUID)
    case notImage(Clip.ID)
    case notFound(UUID)
    case readFailed
    case writeFailed
    case deleteFailed
}
