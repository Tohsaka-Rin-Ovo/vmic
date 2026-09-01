# vmic

vmic 是一个 iOS 18.2+ 麦克风注入原型。它可以导入本地音频文件，做成按钮音效板，并在系统允许时请求把本 App 播放的音频加入支持的通话输入流。

## 环境

- iPhone 或 iPad 需要 iOS/iPadOS 18.2 或更高版本，才能使用麦克风注入。
- Xcode 建议 16.2 或更高版本。
- 必须用真机测试。模拟器无法验证电话、FaceTime 或 VoIP 通话注入。

项目的最低部署版本暂设为 iOS 17.0，这样低版本设备也能打开不支持页面；真正的通话音频注入 API 只会在 iOS 18.2+ 上启用。
App 默认使用中文，左上角设置按钮可以切换中文和英文。

## 首次测试

1. 在 macOS 上打开 `vmic.xcodeproj`。
2. 把 bundle identifier 从 `com.example.vmic` 改成你自己的开发者标识。
3. 选择你的开发团队并用真机运行。
4. 打开 `设置 > 辅助功能 > 音频与视觉 > 通话中添加音频`，开启系统开关。
5. 回到 vmic，允许 App 添加音频到通话。
6. 先用电话或 FaceTime 测试：通话中打开 vmic 的注入开关，再点一个导入的音频。
7. 电话或 FaceTime 成功后，再测 KOOK 和微信电话。

## 说明

- vmic 不是系统级虚拟麦克风。它使用的是 `AVAudioSession.setPreferredMicrophoneInjectionMode(.spokenAudio)`。
- 跳转系统更新页面没有稳定公开 API，当前按钮使用的是自用构建可尝试的 Settings deep link。
- 如果未来考虑上架，产品定位最好往辅助沟通/AAC/通话提示方向收敛。
