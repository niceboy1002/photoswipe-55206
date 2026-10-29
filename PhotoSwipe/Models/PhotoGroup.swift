import Foundation
import Photos

/// 一个「可以整组处理」的集合。
/// 连拍、相似照片、某个月、过期截屏、拍糊候选，都用这同一个结构，
/// 这样浏览页不需要为每种玩法各写一套逻辑。
enum GroupKind: String {
    case burst
    case similar
    case month
    case oldScreenshot
    case blurry

    var title: String {
        switch self {
        case .burst:         return "连拍"
        case .similar:       return "相似照片"
        case .month:         return "按月"
        case .oldScreenshot: return "过期截屏"
        case .blurry:        return "可能拍糊"
        }
    }

    var symbol: String {
        switch self {
        case .burst:         return "burst.fill"
        case .similar:       return "photo.stack"
        case .month:         return "calendar"
        case .oldScreenshot: return "clock.arrow.circlepath"
        case .blurry:        return "camera.filters"
        }
    }

    /// 金色 / 紫色 / 青色 / 橙色 / 粉色，给分组行做点缀
    var tintHex: String {
        switch self {
        case .burst:         return "#C9A227"
        case .similar:       return "#6B5BD2"
        case .month:         return "#2F8F9D"
        case .oldScreenshot: return "#C97B2F"
        case .blurry:        return "#C0557A"
        }
    }
}

struct PhotoGroup: Identifiable {
    let id: String
    let kind: GroupKind
    let title: String
    let subtitle: String
    let assets: [PHAsset]

    var count: Int { assets.count }
}

extension PhotoGroup {
    /// 按「年 + 月」切分。传入的列表本来就是按拍摄时间倒序的，
    /// 所以这里保持插入顺序，出来天然也是最新的月份在最前。
    static func months(from assets: [PHAsset]) -> [PhotoGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        var buckets: [Int: [PHAsset]] = [:]
        var order: [Int] = []

        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let y = parts.year, let m = parts.month else { continue }
            let key = y * 100 + m
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(asset)
        }

        var result: [PhotoGroup] = []
        result.reserveCapacity(order.count)
        for key in order {
            guard let list = buckets[key], !list.isEmpty else { continue }
            let year = key / 100
            let month = key % 100
            result.append(
                PhotoGroup(
                    id: "month:\(key)",
                    kind: .month,
                    title: "\(year) 年 \(month) 月",
                    subtitle: "\(list.count) 张",
                    assets: list
                )
            )
        }
        return result
    }

    /// 90 天前的截屏。
    /// 截屏是最典型的「拍完就忘」——文档、验证码、聊天记录截图，
    /// 过了三个月几乎没有回看价值，堆在一起却非常占地方。
    static func oldScreenshots(from assets: [PHAsset], days: Int = 90) -> PhotoGroup? {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let list = assets.filter { asset in
            guard asset.mediaType == .image else { return false }
            guard asset.mediaSubtype.contains(.photoScreenshot) else { return false }
            return (asset.creationDate ?? .distantPast) < cutoff
        }
        guard !list.isEmpty else { return nil }
        return PhotoGroup(
            id: "oldscreenshot",
            kind: .oldScreenshot,
            title: "90 天前的截屏",
            subtitle: "\(list.count) 张 · 保留最近三个月的",
            assets: list
        )
    }
}
