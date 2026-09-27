import SwiftUI

struct HealthAuthView: View {
    let onFinish: () -> Void

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red.gradient)
                .symbolEffect(.pulse.byLayer)

            VStack(spacing: 12) {
                Text("连接你的健康数据")
                    .font(.title2.bold())

                Text("iHealth 需要读取你的健康数据\n用来计算恢复度、训练负荷和运动统计。\n\n所有数据仅保存在本机，不会上传。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        isRequesting = true
                        // 触发系统授权弹窗 + 首次同步
                        // BodyMetricsStore.load() 内部会 requestAuthorization
                        await BodyMetricsStore.shared.load()
                        isRequesting = false
                        onFinish()
                    }
                } label: {
                    Group {
                        if isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Text("允许访问健康数据")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isRequesting)

                Button("稍后再说") {
                    // 不调用 load()，让 Body Tab 的 .task 首屏再触发
                    // 无论如何系统弹窗只会弹一次，这里只是延后时机
                    onFinish()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}
