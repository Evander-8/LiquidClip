# Services/
> L2 | Parent: ../../../GEMINI.md

成员清单
ClipboardMonitor.swift: 系统剪贴板轮询监听与划词复制采集器，过滤隐私/瞬态标记与排除应用，支持严格 Hex/rgb/rgba/hsl/hsla/oklch 色彩识别后入库
HotkeyManager.swift: Carbon 全局热键注册管理器，负责热键冲突检测与键盘布局无关的按键文本格式化
ImageCacheStore.swift: 图像媒体与缓存管理器，封装后台 PNG 编解码、SHA-256 哈希、原始 PNG 字节异步读取、NSCache 字节限额与异步缩略图加载
LoginService.swift: 开机自启管理器，优先使用 SMAppService 并对 Ad-hoc 签名降级兼容 LSSharedFileList
OCRService.swift: 基于原生 Vision 框架的离线中英文图片文字识别服务
PasteSimulator.swift: 剪贴板异步 PNG 写入（含纯文本去格式）与 CGEvent 模拟 ⌘V 自动粘贴执行器，含辅助功能权限自愈重置
SQLiteStore.swift: 基于系统 SQLite3 + External-Content FTS5 trigram（Triggers 自动同步 + user_version 2 迁移）的 WAL 模式持久化与异步检索引擎
SoundManager.swift: 原生系统音效播放器，管理复制、粘贴与删除反馈音
StorageManager.swift: 历史与分组存储协调中心，负责 JSON->SQLite 无损迁移、O(1) 指纹去重、异步检索、隐私模式隔离、后台图像/OCR 管线与缓存回收
UpdateChecker.swift: GitHub Releases 轻量更新检测器，支持启动静默检查与交互式检查状态反馈

[PROTOCOL]: Update this header on change, then check GEMINI.md
