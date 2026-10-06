//
//  ClipStorageService.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

/// 클립의 텍스트와 메타데이터를 저장합니다. 이미지 바이트와 파일 생명주기는 별도 서비스에서 관리합니다.
///
/// 구현체는 저장 확정과 이벤트 발행을 동일한 순서로 직렬화해야 합니다.
/// 쓰기 실패 시 기존 상태를 보존하고 이벤트를 발행하지 않아야 합니다.
/// 변경 사항이 없는 수정은 이벤트 발행 없이 현재 클립을 반환합니다.
/// 저장 방식에 종속된 오류는 ClipStorageError로 매핑하고 CancellationError는 그대로 전파합니다.
protocol ClipStorageService: Sendable {

    /// ClipSortOrder에서 정의한 결정적 순서로 반환합니다. 저장소가 비어 있으면 빈 배열을 반환합니다.
    func fetchAll(order: ClipSortOrder) async throws -> [Clip]

    /// 해당 식별자가 존재하지 않으면 nil을 반환합니다.
    func fetch(id: Clip.ID) async throws -> Clip?

    /// 호출부에서 전달한 식별자와 시각을 사용합니다. 중복 식별자와 유효하지 않은 콘텐츠는 거부합니다.
    /// 전체 쓰기 작업의 저장이 확정된 후에만 inserted 이벤트를 발행합니다.
    func insert(_ clip: Clip) async throws

    /// 저장된 최신 스냅샷에 변경 사항을 적용하고 저장이 확정된 결과를 반환합니다.
    /// 식별자, 콘텐츠, 생성 시각은 보존합니다. 해당 식별자가 존재하지 않으면 notFound 오류를 던집니다.
    func update(id: Clip.ID, change: ClipUpdate) async throws -> Clip

    /// 메타데이터를 제거하고 저장이 확정된 후 deleted 이벤트를 발행합니다. 해당 식별자가 존재하지 않으면 notFound 오류를 던집니다.
    /// 호출부는 이미지 파일 서비스와 함께 이미지 원본 파일의 삭제를 조율합니다.
    func delete(id: Clip.ID) async throws

    /// 반환 전에 독립적인 구독을 등록합니다. 각 스트림은 단일 소비자를 전제로 합니다.
    /// 모든 활성 구독자는 이 저장소 인스턴스에서 등록 이후 발생한 모든 변경을 저장 확정 순서로 전달받습니다.
    /// 버퍼 용량을 제한하지 않으며 초기 스냅샷 제공과 등록 이전 변경의 재전달은 수행하지 않습니다.
    /// 구현체는 onTermination에서 구독 등록을 제거하고 저장소가 종료되면 스트림을 종료합니다.
    /// 소비자는 자신의 Task를 취소하여 관찰을 종료합니다.
    /// 목록은 조회 전에 구독을 등록하고 이벤트 수신 시 다시 조회합니다.
    /// 버퍼에 남아 있는 이벤트 스냅샷을 최신 조회 결과에 덮어쓰지 않습니다.
    func changes() async -> AsyncStream<ClipStorageEvent>
}
