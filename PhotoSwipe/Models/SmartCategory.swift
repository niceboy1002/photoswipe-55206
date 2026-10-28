import Foundation
import Photos
import Combine

/// 相册的智能分类。
/// 这些全部来自 PHAsset 自带元数据，不需要扫描图片内容，所以几万张也是毫秒级。
enum SmartCategory: String, CaseIterable, Identifiable {
    case screenshots
    case livePhotos
    case videos
    case selfies
    case panoramas
    case bursts
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: return "截屏"
        case .livePhotos:  return "实况照片"
        case .videos:      return "视频"
        case .selfies:     return "自拍"
        case .panoramas:   return "全景"
        case .bursts:      return "连拍"
        case .favorites:   return "喜欢"
        }
    }

    var symbol: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .livePhotos:  return "livephoto"
        case .videos:      return "video.fill"
        case .selfies:     return "person.crop.square.fill"
        case .panoramas:   return "pano"
        case .bursts:      return "square.stack.3d.down.right.fill"
        case .favorites:   return "heart.fill"
        }
    }

    /// 卡片配色（渐变的两个端点）
    var colors: [String] {
        switch self {
        case .screenshots: return ["#2C3E63", "#16213A"]
        case .livePhotos:  return ["#5A3C6B", "#2A1A33"]
        case .videos:      return ["#1F4E5F", "#0D242C"]
        case .selfies:     return ["#6B3A3A", "#2E1717"]
        case .panoramas:   return ["#3A5C4A", "#15261E"]
        case .bursts:      return ["#4A4A2E", "#1F1F12"]
        case .favorites:   return ["#6B2740", "#2E0F1B"]
        }
    }

    /// 交给 PhotoKit 去数据库层过滤，不占用内存。
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
        case .selfies:
            // 注意：这是「前置摄像头拍摄」，不是人脸识别出的自拍
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoFrontFacingCamera.rawValue)
            )
        case .panoramas:
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoPanorama.rawValue)
            )
        case .bursts:
            options.predicate = NSPredicate(
                format: "mediaSubtype & %d != 0",
                Int(PHAssetMediaSubtype.photoBurst.rawValue)
            )
        case .favorites:
            options.predicate = NSPredicate(format: "isFavorite == YES")
        }

        return options
    }
}
