import SwiftUI
import Photos
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch library.status {
            case .authorized:
                CategoryGridView()
            case .limited:
                CategoryGridView(limited: true)
            case .notDetermined:
                PermissionView()
            case .denied, .restricted:
                DeniedView()
            @unknown default:
                PermissionView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.refreshStatus()
            }
        }
    }
}

// MARK: - 首次进入：请求权限

struct PermissionView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 180, height: 180)
                Image(systemName: "photo.stack")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }

            VStack(spacing: 12) {
                Text("整理你的相册")
                    .font(.system(size: 26, weight: .bold))
                Text("滑动决定去留，攒够了再一次性清理。\n所有处理都在本机完成，不会上传任何照片。")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 34)
            .padding(.horizontal, 36)

            Spacer()

            Button {
                guard !requesting else { return }
                requesting = true
                Task {
                    let result = await library.requestAccess()
                    if result == .authorized || result == .limited {
                        await library.loadCounts()
                        await library.loadCoverImages()
                    }
                    requesting = false
                }
            } label: {
                ZStack {
                    if requesting {
                        ProgressView().tint(.black)
                    } else {
                        Text("允许访问相册")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 28)
            .disabled(requesting)

            Text("需要「完全访问」才能按分类整理并删除照片")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 14)
                .padding(.bottom, 36)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - 权限被拒绝

struct DeniedView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("没有相册访问权限")
                .font(.system(size: 19, weight: .semibold))
            Text("请到「设置 › 隐私与安全性 › 照片」中\n允许本 App 访问。")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("去设置")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
