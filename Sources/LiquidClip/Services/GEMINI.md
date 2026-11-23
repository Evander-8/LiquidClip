# Services/
> L2 | Parent: ../../../GEMINI.md

成员清单
ClipboardMonitor.swift: 系统剪贴板轮询监听与划词复制采集器，过滤密码管理器与排除应用后入库
HotkeyManager.swift: Carbon 全局热键注册管理器，负责热键冲突检测与键盘布局无关的按键文本格式化
LoginService.swift: 开机自启管理器，优先使用 SMAppService 并对 Ad-hoc 签名降级兼容 LSSharedFileList
PasteSimulator.swift: 剪贴板写入与 CGEvent 模拟 ⌘V 自动粘贴执行器，含辅助功能权限检测与 TCC 自愈重置
SoundManager.swift: 原生系统音效播放器，管理复制、粘贴与删除反馈音
StorageManager.swift: 历史与分组持久化中心，负责隐私模式内存隔离、后台图像编码去重、缓存限制与孤儿图片回收
UpdateChecker.swift: GitHub Releases 轻量更新检测器，启动时单次请求版本元数据并广播通知

[PROTOCOL]: Update this header on change, then check GEMINI.md
