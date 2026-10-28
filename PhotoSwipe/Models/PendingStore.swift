import Foundation
import Combine

/// 待删除队列。
/// 关键设计：滑动手势只负责"标记"，真正的删除要用户回到垃圾桶里确认一次。
/// 队列持久化到 UserDefaults，所以 App 被杀掉、手机重启，攒的照片也不会丢。
final class PendingStore: ObservableObject {
    static let shared = PendingStore()

    private let storageKey = "photoswipe.pending.ids"

    @Published private(set) var ids: [String] = []

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            ids = saved
        }
    }

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func add(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.append(id)
        persist()
    }

    func add(contentsOf list: [String]) {
        for id in list where !ids.contains(id) {
            ids.append(id)
        }
        persist()
    }

    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        persist()
    }

    func clear() {
        ids.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(ids, forKey: storageKey)
    }
}
