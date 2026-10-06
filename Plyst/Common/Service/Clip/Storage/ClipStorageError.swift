//
//  ClipStorageError.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

/// UI, 영구 저장 형식, 파일 경로에 의존하지 않는 저장소 오류입니다.
enum ClipStorageError: Error, Equatable, Sendable {
    case duplicateID(Clip.ID)
    case notFound(Clip.ID)
    case invalidContent
    case readFailed
    case writeFailed
    case corruptedData
}
