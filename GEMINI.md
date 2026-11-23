# LiquidClip - macOS 原生液态玻璃剪贴板历史管理器
Swift 6.0 工具链 (-swift-version 5) + SwiftUI + AppKit + Carbon + CryptoKit + ImageIO + ServiceManagement

<directory>
Sources/LiquidClip/ - 应用源码根目录 (4 个子模块: Models, Services, Window, Views)
Resources/ - 应用图标资源与 Info.plist (v1.0.6)
scripts/ - 原生编译打包与 DMG 制作脚本
dist/ - 本地构建输出目录 (.app 与 .dmg)
</directory>

<config>
Package.swift - Swift Package 清单，声明 macOS 14.0+ 目标与零第三方依赖
Resources/Info.plist - 应用 Bundle 元数据与 LSUIElement 菜单栏配置
scripts/build_app.sh - swiftc 发布构建、Ad-hoc 签名与 DMG 打包脚本
</config>
