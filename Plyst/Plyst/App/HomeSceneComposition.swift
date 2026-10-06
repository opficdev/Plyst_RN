//
//  HomeSceneComposition.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import OSLog
import ReactorKit
import RxSwift
import UIKit

@MainActor
final class HomeSceneComposition {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.PlystRN",
        category: String(describing: HomeSceneComposition.self)
    )

    private let toastWindow: ToastWindow
    private let storage: SQLiteClipStorageService
    private let images: ClipImageService
    private let clipboard: ClipboardService
    private let photos: ClipPhotoLibraryService
    /// App Group 컨테이너를 찾지 못하면 nil입니다. 본 저장소가 정상이므로 시작은 계속하고 반입만 건너뜁니다.
    private let imports: ClipShareImportService?
    private var importTask: Task<Void, Never>?
    private weak var home: HomeViewController?

    deinit {
        importTask?.cancel()
    }

    init(toastWindow: ToastWindow) throws {
        self.toastWindow = toastWindow
        var directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directory.appendPathComponent("Plyst", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)

        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clipboard = ClipboardService(storage: storage, images: images)
        self.storage = storage
        self.images = images
        self.clipboard = clipboard
        photos = ClipPhotoLibraryService(storage: storage, images: images)
        imports = Self.makeImportService(storage: storage, images: images)
    }

    private static func makeImportService(
        storage: SQLiteClipStorageService,
        images: ClipImageService
    ) -> ClipShareImportService? {
        do {
            let directory = try ClipAppGroupDirectory()
            return ClipShareImportService(
                inboxDatabaseURL: directory.shareInboxDatabaseURL,
                inboxImagesURL: directory.shareInboxImagesURL,
                storage: storage,
                images: images
            )
        } catch {
            logger.error("공유 저장소 위치 확인 실패: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    func makeRootViewController() -> UIViewController {
        // 상세 화면은 같은 저장소와 서비스 인스턴스를 공유합니다.
        let makeDetail: @MainActor (Clip) -> UIViewController = { [storage, clipboard, images, photos, toastWindow] clip in
            switch clip.content {
            case .text:
                TextDetailViewController(
                    reactor: TextDetailReactor(
                        clip: clip,
                        storage: storage,
                        clipboard: clipboard
                    ),
                    toastWindow: toastWindow,
                    makeTextDetailView: { TextDetailView(frame: .zero, send: $0) }
                )
            case .image:
                ImageDetailViewController(
                    reactor: ImageDetailReactor(
                        clip: clip,
                        storage: storage,
                        clipboard: clipboard,
                        images: images,
                        photos: photos
                    ),
                    toastWindow: toastWindow,
                    makeImageDetailView: { ImageDetailView(frame: .zero, send: $0) }
                )
            }
        }
        let reactor = HomeReactor(
            storage: storage,
            clipboard: clipboard,
            images: images
        )
        // 검색 화면은 같은 저장소와 서비스 및 토스트 창을 공유합니다. 클로저는 Composition을 캡처하지 않습니다.
        let controller = HomeViewController(
            reactor: reactor,
            toastWindow: toastWindow,
            makeHomeView: { HomeView(frame: .zero, send: $0) },
            makeSearchViewController: { [storage, clipboard, images, makeDetail, toastWindow] cancel in
                SearchViewController(
                    reactor: SearchReactor(
                        storage: storage,
                        history: storage,
                        clipboard: clipboard,
                        images: images
                    ),
                    toastWindow: toastWindow,
                    makeSearchView: { SearchView(frame: .zero, send: $0) },
                    makeDetailViewController: makeDetail,
                    cancel: cancel
                )
            },
            makeDetailViewController: makeDetail
        )
        home = controller
        return controller
    }

    /// 기록 화면의 저장 버튼과 같은 Action으로 현재 클립보드를 저장합니다. 화면이 로드된 뒤에 호출해야 합니다.
    func saveCurrentClipboard() {
        home?.reactor.action.onNext(.saveCurrentClipboard)
    }

    /// Share Extension이 저장한 클립을 본 저장소로 옮깁니다. 이미 실행 중이면 새로 시작하지 않습니다.
    /// 실패해도 화면 상태와 Inbox는 유지되며 다음 활성화에서 다시 시도합니다. 해제되면 진행 중인 반입을 취소합니다.
    func importSharedClips() {
        guard importTask == nil, let imports else { return }
        importTask = Task { [weak self, imports] in
            do {
                let result = try await imports.importPendingClips()
                if 0 < result.remainingCount {
                    Self.logger.warning("공유 클립 반입 보류: \(result.remainingCount, privacy: .public)개")
                }
                if result.hasPendingCleanup { self?.startPendingCleanupRecovery() }
            } catch is CancellationError {
                // 해제에 따른 정상적인 중단입니다.
            } catch {
                Self.logger.error("공유 클립 반입 실패: \(String(describing: type(of: error)), privacy: .public)")
            }
            self?.importTask = nil
        }
    }

    func startPendingCleanupRecovery() {
        Task { [images] in
            do {
                let pending = try await images.recoverPendingCleanup()
                if !pending.isEmpty {
                    Self.logger.warning("이미지 정리 보류: \(pending.count, privacy: .public)개")
                }
            } catch {
                Self.logger.error("이미지 정리 재시도 실패: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }
}
