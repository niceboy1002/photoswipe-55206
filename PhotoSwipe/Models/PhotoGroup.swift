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
        case .burst:
            return "连拍"
        case .similar:
            return "相似照片"
        case .month:
            return "按月"
        case .oldScreenshot:
            return "过期截屏"
        case .blurry:
            return "可能拍糊"
        }
    }
}

struct PhotoGroup: Identifiable {
    let id: String
    let kind: GroupKind
    let title: String
    let subtitle: String
    let assets: [PHAsset]

    /// 显式写出来，不依赖编译器合成的成员初始化器
    init(id: String, kind: GroupKind, title: String, subtitle: String, assets: [PHAsset]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.assets = assets
    }

    var count: Int {
        return assets.count
    }
}

extension PhotoGroup {
    /// 按「年 + 月」切分。传入的列表本来就是按拍摄时间倒序的，
    /// 所以这里保持插入顺序，出来天然也是最新的月份在最前。
    static func months(from assets: [PHAsset]) -> [PhotoGroup] {
        var calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        calendar.timeZone = TimeZone.current

        var buckets: [Int: [PHAsset]] = [:]
        var order: [Int] = []

        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let parts = calendar.dateComponents([Calendar.Component.year, Calendar.Component.month], from: date)
            guard let y = parts.year, let m = parts.month else { continue }
            let key: Int = y * 100 + m
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(asset)
        }

        var result: [PhotoGroup] = []
        result.reserveCapacity(order.count)

        for key in order {
            guard let list = buckets[key] else { continue }
            let year: Int = key / 100
            let month: Int = key % 100
            let group = PhotoGroup(id: "month:\(key)",
                                   kind: GroupKind.month,
                                   title: "\(year) 年 \(month) 月",
                                   subtitle: "\(list.count) 张",
                                   assets: list)
            result.append(group)
        }

        return result
    }

    /// 90 天前的截屏。
    /// 截屏是最典型的「拍完就忘」——文档、验证码、聊天记录截图，
    /// 过了三个月几乎没有回看价值，堆在一起却非常占地方。
    static func oldScreenshots(from assets: [PHAsset], days: Int = 90) -> PhotoGroup? {
        let cutoff: Date = Date().addingTimeInterval(-Double(days) * 86400.0)

        var list: [PHAsset] = []
        for asset in assets {
            guard asset.mediaType == PHAssetMediaType.image else { continue }
            guard asset.mediaSubtypes.contains(PHAssetMediaSubtype.photoScreenshot) else { continue }
            let date: Date = asset.creationDate ?? Date.distantPast
            guard date < cutoff else { continue }
            list.append(asset)
        }

        guard !list.isEmpty else { return nil }

        return PhotoGroup(id: "oldscreenshot",
                          kind: GroupKind.oldScreenshot,
                          title: "90 天前的截屏",
                          subtitle: "\(list.count) 张 · 保留最近三个月的",
                          assets: list)
    }
}
