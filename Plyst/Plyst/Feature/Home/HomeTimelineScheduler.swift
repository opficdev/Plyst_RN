//
//  HomeTimelineScheduler.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

@MainActor
final class HomeTimelineScheduler {
    private let onUpdate: @MainActor (Date) -> Void
    private var clips = [Clip]()
    private var timer: Timer?
    private var isVisible = false

    init(onUpdate: @escaping @MainActor (Date) -> Void) {
        self.onUpdate = onUpdate
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func appear() {
        isVisible = true
        refresh()
    }

    func disappear() {
        isVisible = false
        stop()
    }

    func update(clips: [Clip]) {
        self.clips = clips
        schedule()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        refresh()
    }

    @objc private func applicationWillResignActive(_ notification: Notification) {
        stop()
    }

    private func refresh() {
        guard isVisible, UIApplication.shared.applicationState == .active else { return }
        stop()
        let now = Date()
        onUpdate(now)
        schedule()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule() {
        stop()
        guard isVisible,
              UIApplication.shared.applicationState == .active,
              !clips.isEmpty else { return }

        let now = Date()
        var next = Calendar.current.dateInterval(
            of: .day,
            for: now
        )?.end ?? now.addingTimeInterval(86_400)
        for clip in clips {
            // HomeCardFormat의 상대 시각 문구와 HomeSection의 방금 구간이 바뀌는 시점입니다.
            for seconds in [0, 60, 120, 180, 240, 300] {
                let transition = clip.createdAt.addingTimeInterval(TimeInterval(seconds))
                if now < transition {
                    if transition < next { next = transition }
                    break
                }
            }
        }

        let timer = Timer(
            fire: next,
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
