//
//  ImageDetailViewLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol ImageDetailViewLike: UIView {
    func setContent(meta: String)
    func setPreview(
        _ image: UIImage?,
        isLoading: Bool,
        didFail: Bool
    )
    func setDraft(
        name: String,
        isPinned: Bool
    )
    func setDates(
        saved: String,
        lastUsed: String
    )
    func setSaveEnabled(_ isEnabled: Bool)
    func setBusy(_ isBusy: Bool)
    func setSavingToPhotos(_ isSaving: Bool)
}
