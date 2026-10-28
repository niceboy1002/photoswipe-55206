import SwiftUI
import AVKit
import Photos

/// 全屏视频播放。
///
/// 之前视频只是一张静态封面，点不开，所以"无法播放"。
/// 这里用 PHImageManager 拿到 AVPlayerItem 交给系统的 VideoPlayer，
/// 支持 iCloud 视频（会先下载）和静音开关下出声。
struct VideoPlayerView: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if failed {
                failureState
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white.opacity(0.6))
                    Text("正在准备视频…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            VStack {
                HStack {
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
            }
        }
        .task {
            PhotoLibrary.shared.activatePlaybackAudio()
            if let item = await PhotoLibrary.shared.playerItem(for: asset) {
                let p = AVPlayer(playerItem: item)
                player = p
                p.play()
            } else {
                failed = true
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .statusBarHidden(true)
    }

    private var failureState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("这段视频暂时打不开")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("如果它存在 iCloud 里，连上网络后再试一次；\n也确认设置里本 App 可以访问全部照片。")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 40)
    }
}
