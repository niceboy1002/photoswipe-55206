import Foundation
import Photos
import Combine

/// 相册的智能分类。
///
/// 全部来自 PHAsset 自带元数据，不需要扫描图片内容，几万张也是毫秒级。
///
/// 说明：苹果系统相册里的「自拍」相簿是通过本地人脸识别算出来的，
/// PhotoKit 没有把这一项开放给第三方，所以这里用「人像模式」替代。
enum SmartCategory: String, CaseIterable, Identifiable {
    case screenshots
    case livePhotos
    case videos
    case panoramas
    case portraits
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: return "截屏"
        case .livePhotos:  return "实况照片"
        case .videos:      return "视频"
        case .panoramas:   return "全景"
        case .portraits:   return "人像模式"
        case .favorites:   return "喜欢"
        }
    }

    var symbol: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .livePhotos:  return "livephoto"
        case .videos:      return "video.fill"
        case .panoramas:   return "pano"
        case .portraits:   return "person.crop.rectangle"
        case .favorites:   return "heart.fill"
        }
    }

    /// 卡片配色（渐变的两个端点）
    var colors: [String] {
        switch self {
        case .screenshots: return ["#2C3E63", "#16213A"]
        case .livePhotos:  return ["#5A3C6B", "#2A1A33"]
        case .videos:      return ["#1F4E5F", "#0D242C"]
        case .panoramas:   return ["#3A5C4A", "#15261E"]
        case .portraits:   return ["#6B3A3A", "#2E1717"]
        case .favorites:   return ["#6B2740", "#2E0F1B"]
        }
    }

    /// 交给 PhotoKit 在数据库层过滤，不占内存。
    var fetchOptions: PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        switch self {
        case .screenshots:
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
            )
        case .livePhotos:
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoLive.rawValue)
            )
        case .videos:
            options.predicate = NSPredicate(
                format: "mediaType == %d",
                Int(PHAssetMediaType.video.rawValue)
            )
        case .panoramas:
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoPanorama.rawValue)
            )
        case .portraits:
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoDepthEffect.rawValue)
            )
        case .favorites:
            options.predicate = NSPredicate(format: "isFavorite == YES")
        }

        return options
    }
}
