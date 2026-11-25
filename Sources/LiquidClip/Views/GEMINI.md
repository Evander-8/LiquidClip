# Views/
> L2 | Parent: ../../../GEMINI.md

成员清单
Inspectors/ - 按 ClipType 拆分的多格式内容检查器子模块 (5 个检查器文件)
Settings/ - 分栏偏好设置子页与共享卡片组件 (5 个设置模块文件)
AboutView.swift: 可复用的液态玻璃关于界面，提供 Hero 信息、交互式更新检测、架构微卡片与诊断信息复制
ClipDetailView.swift: 右侧内容检查器路由容器，负责顶部粘贴/纯文本/复制/分组/收藏工具栏与分发渲染
ClipRowView.swift: 左侧历史列表行视图，支持 Equatable 精确比对、异步缩略图、双击粘贴与列表拖拽
ExcludedAppsSettingsSection.swift: 忽略应用可视化管理组件，支持从运行中应用一键添加或手动输入 Bundle ID
GlassComponents.swift: 通用液态玻璃基础组件，包含应用/文件图标缓存、键盘角标、聚焦搜索框、悬浮按钮与 FlowLayout 自动换行布局
MainWindowView.swift: 主窗口根视图，直接订阅 MainWindowViewModel 缓存派生列表与指标渲染分栏布局、提示横幅与弹窗浮层
NewGroupModal.swift: 自定义分组新建与编辑弹窗，提供名称输入与 21 款 SF Symbol 图标网格选择器
SettingsView.swift: macOS 分栏导航式偏好设置中心，集成侧边栏 Tab、按需权限轮询与各分栏子页
VisualEffectView.swift: NSVisualEffectView 桥接视图与液态玻璃渐变边框修饰器

[PROTOCOL]: Update this header on change, then check GEMINI.md
