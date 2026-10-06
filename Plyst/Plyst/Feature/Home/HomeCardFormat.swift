//
//  HomeCardFormat.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

enum HomeCardFormat {
    /// 웹 링크 클립에서 따옴표 대신 표시하는 아이콘입니다.
    static func linkIcon(pointSize: CGFloat) -> UIImage? {
        UIImage(
            systemName: "globe",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        )
    }

    /// 이미지 클립의 썸네일을 표시하지 못할 때 대신 표시하는 숨겨진 아이콘입니다.
    @MainActor
    static func makeFailureIcon(pointSize: CGFloat) -> UIImageView {
        let icon = UIImageView(image: UIImage(
            systemName: "exclamationmark.triangle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        ))
        icon.tintColor = UIColor(resource: .homePlaceholder)
        icon.contentMode = .scaleAspectFit
        icon.isHidden = true
        return icon
    }

    static func time(
        for date: Date,
        now: Date
    ) -> String {
        let age = now.timeIntervalSince(date)
        if 0 <= age, age < 60 { return "지금" }
        if 0 <= age, age < 5 * 60 { return "\(Int(age / 60))분 전" }
        if Calendar.current.isDate(date, inSameDayAs: now)
            || Calendar.current.isDate(date, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    /// 강조 서식이 들어간 문자열의 높이입니다. 문자열의 모든 구간에 글꼴이 지정돼 있어야 정확합니다.
    static func height(
        for text: NSAttributedString,
        font: UIFont,
        width: CGFloat,
        lines: Int
    ) -> CGFloat {
        let bounds = text.boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return min(ceil(font.lineHeight * CGFloat(lines)), max(ceil(font.lineHeight), ceil(bounds.height)))
    }

    static func height(
        for text: String,
        font: UIFont,
        width: CGFloat,
        lines: Int
    ) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(ceil(font.lineHeight * CGFloat(lines)), max(ceil(font.lineHeight), ceil(bounds.height)))
    }
}
