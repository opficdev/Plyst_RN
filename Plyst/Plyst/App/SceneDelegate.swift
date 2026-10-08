//
//  SceneDelegate.swift
//  Plyst
//
//  Created by opfic on 9/28/26.
//

import OSLog
import PlystBridge
import UIKit

@MainActor
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "opfic.PlystRN",
        category: String(describing: SceneDelegate.self)
    )

    var window: UIWindow?
    private var toastWindow: ToastWindow?
    private var toastHostWindow: ToastHostWindow?
    private var composition: HomeSceneComposition?
    private var isClipboardSaveRequested = false
    #if DEBUG
    private var isReactNativeDebugRequested = false
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        toastWindow = ToastWindow(windowScene: windowScene)
        configureRoot(in: window)
        window.makeKeyAndVisible()
        toastHostWindow = ToastHostWindow(windowScene: windowScene)
        toastHostWindow?.isHidden = false
        request(from: connectionOptions.urlContexts)
    }

    func scene(
        _ scene: UIScene,
        openURLContexts contexts: Set<UIOpenURLContext>
    ) {
        request(from: contexts)
        if scene.activationState == .foregroundActive {
            saveClipboardIfRequested()
            #if DEBUG
            presentReactNativeDebugScreenIfRequested()
            #endif
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        composition?.importSharedClips()
        saveClipboardIfRequested()
        #if DEBUG
        presentReactNativeDebugScreenIfRequested()
        #endif
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        toastHostWindow?.isHidden = true
        toastHostWindow = nil
        toastWindow?.hide()
        toastWindow = nil
        window = nil
        ClipBridge.unregister()
        composition = nil
    }

    private func request(from contexts: Set<UIOpenURLContext>) {
        if contexts.contains(where: { AppLink(url: $0.url) == .saveClipboard }) {
            isClipboardSaveRequested = true
        }
        #if DEBUG
        if contexts.contains(where: { isReactNativeDebugURL($0.url) }) {
            isReactNativeDebugRequested = true
        }
        #endif
    }

    /// 클립보드 읽기는 앱이 활성 상태일 때만 가능하므로 활성화된 뒤에 요청을 처리합니다.
    /// 처리할 수 없는 상태에서 요청이 남아 이후 활성화에 실행되지 않도록 항상 요청을 비웁니다.
    private func saveClipboardIfRequested() {
        guard isClipboardSaveRequested else { return }
        isClipboardSaveRequested = false
        composition?.saveCurrentClipboard()
    }

    #if DEBUG
    private func isReactNativeDebugURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "plystrn"
            && components.host == "debug"
            && components.path == "/react-native"
    }

    private func presentReactNativeDebugScreenIfRequested() {
        guard isReactNativeDebugRequested else { return }
        isReactNativeDebugRequested = false
        guard let rootViewController = window?.rootViewController,
              rootViewController.presentedViewController == nil else { return }
        rootViewController.present(ReactNativeRuntime.makeDebugViewController(), animated: true)
    }
    #endif

    private func configureRoot(in window: UIWindow) {
        guard let toastWindow else { return }
        do {
            let composition = try HomeSceneComposition(toastWindow: toastWindow)
            let root = composition.makeRootViewController()
            self.composition = composition
            ClipBridge.register(ClipBridgeAdapter(storage: composition.storage, images: composition.images))
            window.rootViewController = root
            composition.startPendingCleanupRecovery()
            // 시작 실패 후 다시 시도해 성공하면 Scene이 이미 활성 상태라 sceneDidBecomeActive가 오지 않습니다.
            composition.importSharedClips()
        } catch {
            Self.logger.error("기록 화면 초기화 실패: \(String(describing: type(of: error)), privacy: .public)")
            composition = nil
            window.rootViewController = StartupFailureViewController { [weak self] in
                guard let self, let window = self.window else { return }
                self.configureRoot(in: window)
            }
        }
    }
}
