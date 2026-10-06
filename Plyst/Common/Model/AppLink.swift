//
//  AppLink.swift
//  Plyst
//
//  Created by opfic on 10/3/26.
//

import Foundation

/// 앱 밖에서 앱으로 진입할 때 사용하는 URL 계약입니다. 위젯이 만들고 앱이 해석합니다.
enum AppLink: Equatable, Sendable {
    case saveClipboard

    private static let scheme = "plyst"

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .saveClipboard:
            components.host = "clipboard"
            components.path = "/save"
        }
        return components.url
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme,
              components.host == "clipboard",
              components.path == "/save" else { return nil }
        self = .saveClipboard
    }
}
