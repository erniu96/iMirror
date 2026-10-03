# 架构

iMirror 按数据所有权分为五层，依赖始终向内：

```text
SwiftUI 菜单栏与设置
        │ 类型化用户意图 / ReceiverStatus
        ▼
AppModel（用例编排，不处理协议细节）
        │
        ├── AirPlayReceiverService ── ObjC++ Bridge ── AirPlay/RAOP C
        ├── SettingsStore ─────────── UserDefaults
        └── VideoSessionRouter
                 └── 每个 RAOP 会话：MirrorWindowController ─ VideoPipeline ─ VideoToolbox ─ Metal
```

## 深模块边界

- `AirPlayReceiverService` 隐藏 RAOP 生命周期、线程和 Objective-C delegate，只暴露类型化事件和视频访问单元。
- `VideoSessionRouter` 使用 bridge 确认过的 `raop_connection_t` 指针身份作为进程内会话 ID，将每路压缩视频送入唯一的管线；窗口创建期间仅保留有明确内存上限的首帧缓冲。
- `VideoPipeline` 隐藏 Annex-B 拆包、H.264 参数集、异步硬件解码和首帧语义；窗口只接收可显示帧。
- 每个会话独占一个 `VideoPipeline`、`MirrorWindowController` 和 Metal 渲染视图。一台设备断开时只销毁自己的会话，不影响其余投屏。
- `MirrorWindowController` 统一负责渲染、横竖屏比例、首帧尺寸和 hover 控件。
- `SettingsStore` 保存基础名称、本机稳定标记和窗口偏好；配对验证码由协议层在每次新配对时随机生成，不持久化。

底层 `AirPlay/` 是明确隔离的协议实现。上层不读取其结构体字段，除 ObjC++ bridge 已确认的 `raop_connection_t.devInfo` 契约外，也不做候选字段或启发式映射。
