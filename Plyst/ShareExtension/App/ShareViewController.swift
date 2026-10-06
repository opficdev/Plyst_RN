//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by opfic on 10/1/26.
//

import OSLog
import ReactorKit
import RxSwift
import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.Plyst.ShareExtension",
        category: String(describing: ShareViewController.self)
    )

    private lazy var statusView = ShareStatusView(
        frame: .zero,
        send: { [weak self] in self?.handle($0) }
    )
    /// 저장 완료를 보여 준 뒤 요청을 종료하기까지의 시간입니다.
    private static let completionDelay = Duration.seconds(2)

    /// 이미지 URL 내려받기에 쓰는 세션입니다. 화면이 해제될 때 진행 중인 전송과 함께 무효화합니다.
    private let downloadSession = URLSession(configuration: ClipImageDownloadService.configuration)
    private var reactor: ShareReactor?
    private var task: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var didFinish = false

    deinit {
        task?.cancel()
        finishTask?.cancel()
        recoveryTask?.cancel()
        downloadSession.invalidateAndCancel()
    }

    override func loadView() {
        view = statusView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        prepare()
    }

    /// 시스템이 principal class를 직접 생성하므로 저장소를 열 수 없는 경우를 고려해 viewDidLoad에서 조립합니다.
    private func prepare() {
        do {
            let directory = try ClipAppGroupDirectory()
            let storage = try SQLiteClipStorageService(databaseURL: directory.shareInboxDatabaseURL)
            let files = try ClipImageFileStore(rootURL: directory.shareInboxImagesURL)
            let images = ClipImageService(storage: storage, files: files)
            startPendingCleanupRecovery(images)
            let item = ClipShareItem(item: extensionContext?.inputItems.first as? NSExtensionItem)
            let service = ClipShareService(
                storage: storage,
                images: images,
                downloads: ClipImageDownloadService(session: downloadSession)
            )
            bind(ShareReactor(item: item, service: service))
        } catch {
            Self.logger.error("공유 저장소 준비 실패: \(String(describing: type(of: error)), privacy: .public)")
            statusView.setStatus(.failed)
        }
    }

    /// 이전 실행에서 중단된 저장이 남긴 불완전한 이미지 파일을 정리합니다.
    /// 같은 ClipImageService 안에서는 정리와 저장이 직렬화됩니다. 화면이 해제되면 정리를 중단하고 다음 실행에서 다시 시도합니다.
    private func startPendingCleanupRecovery(_ images: ClipImageService) {
        recoveryTask?.cancel()
        recoveryTask = Task {
            do {
                let pending = try await images.recoverPendingCleanup()
                if !pending.isEmpty {
                    Self.logger.warning("이미지 정리 보류: \(pending.count, privacy: .public)개")
                }
            } catch is CancellationError {
                // 화면 생명주기에 따른 정상적인 중단입니다.
            } catch {
                Self.logger.error("이미지 정리 재시도 실패: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private func bind(_ reactor: ShareReactor) {
        task?.cancel()
        self.reactor = reactor
        // 값을 기다리는 동안에는 Reactor나 ViewController가 아니라 스트림만 캡처합니다.
        let values = reactor.state.values
        task = Task { [weak self] in
            do {
                for try await state in values {
                    guard !Task.isCancelled else { return }
                    self?.render(state.status)
                }
            } catch is CancellationError {
                // 관찰 취소는 화면 생명주기의 정상적인 일부입니다.
            } catch {
                Self.logger.error("상태 구독 실패: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        reactor.action.onNext(.save)
    }

    private func render(_ status: ShareStatus) {
        statusView.setStatus(status)
        guard status == .completed, !didFinish else { return }
        didFinish = true
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: Self.completionDelay)
            guard !Task.isCancelled else { return }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func handle(_ action: ShareStatusViewAction) {
        switch action {
        case .cancel:
            // 진행 중인 저장을 먼저 중단한 뒤 요청을 종료합니다.
            reactor?.action.onNext(.cancel)
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        case .retry:
            if let reactor {
                reactor.action.onNext(.save)
            } else {
                prepare()
            }
        }
    }
}
