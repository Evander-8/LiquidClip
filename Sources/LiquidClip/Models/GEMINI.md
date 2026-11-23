# Models/
> L2 | Parent: ../../../GEMINI.md

成员清单
AppSettings.swift: 全局偏好设置单例，管理 UserDefaults 持久化、Carbon 快捷键编码与隐私模式/历史上限联动
ClipGroup.swift: 自定义分组实体，定义分组 UUID、名称、SF Symbol 图标与创建时间
ClipItem.swift: 剪贴板记录模型，提供预计算文本统计、SHA-256 图像指纹、RGBA 解析与异步图像桥接
ClipType.swift: 内容类型枚举 ClipType 与筛选标签枚举 ClipFilter，声明图标与强调色

[PROTOCOL]: Update this header on change, then check GEMINI.md
