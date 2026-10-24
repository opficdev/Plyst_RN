//
//  DeviceModel.swift
//  PlystBridge
//
//  Created by opfic on 10/20/26.
//

import Foundation

/// 기기 모델 식별자로 기기 종류를 판별함
/// 상태가 없으므로 어느 스레드에서나 읽을 수 있음
enum DeviceModel {
    /// iPhone Duo이면 true
    /// 프로세스가 끝날 때까지 바뀌지 않음
    static let isDuo = ["iPhone19,4"].contains(identifier)

    private static var identifier: String {
        #if targetEnvironment(simulator)
        // 시뮬레이터의 uname()은 Mac 기종을 돌려주므로 시뮬레이터가 넘기는 기기 식별자를 읽음
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
        } ?? ""
        #endif
    }
}
