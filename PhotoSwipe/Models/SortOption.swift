import Foundation

/// 浏览顺序。
///
/// 默认顺序就是系统相册的顺序（拍摄时间倒序，最新的在最前）。
/// 按文件大小排序时会先遍历一遍资源元数据，所以第一次切换会算几秒，
/// 算完的结果会缓存，再切回去是瞬间的。
enum SortOption: String, CaseIterable, Identifiable {
    case newest
    case largest
    case smallest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:   return "默认顺序（最新在前）"
        case .largest:  return "文件从大到小"
        case .smallest: return "文件从小到大"
        }
    }

    var shortTitle: String {
        switch self {
        case .newest:   return "默认顺序"
        case .largest:  return "从大到小"
        case .smallest: return "从小到大"
        }
    }

    var symbol: String {
        switch self {
        case .newest:   return "clock.arrow.circlepath"
        case .largest:  return "arrow.down.circle"
        case .smallest: return "arrow.up.circle"
        }
    }

    var needsSize: Bool { self != .newest }
}
