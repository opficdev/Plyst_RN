//
//  ClipShareSaveResult.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

/// 공유 항목 저장 결과입니다. 이미지 검증 오류와 저장소 오류와 취소는 결과가 아니라 예외로 전달합니다.
enum ClipShareSaveResult: Equatable, Sendable {
    case saved(Clip)
    /// 지원하는 첨부가 없거나 공백뿐인 텍스트입니다. 기록을 남기지 않습니다.
    case empty
    /// 지원하는 첨부에서 값을 읽지 못했습니다. 기록을 남기지 않습니다.
    case loadFailed
}
