<h1 align="center">
  <br>
  <img src="website/assets/app_icon_large.png" alt="Dynamic Notch" width="128">
  <br>
  Dynamic Notch
  <br>
</h1>

<p align="center">
  <strong>灵动自如的 macOS Live Activity 体验 · 专为 MacBook 物理刘海量身打造</strong>
</p>

<p align="center">
  <a href="README_zh.md">简体中文</a> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/linchi07/dynamic_notch/releases/latest"><img src="https://img.shields.io/github/v/release/linchi07/dynamic_notch?color=a855f7&label=Release&style=flat-square" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-black?style=flat-square&logo=apple" alt="macOS 14.0+" />
  <img src="https://img.shields.io/badge/Hardware-Notched%20Apple%20Silicon%20MacBook-blue?style=flat-square" alt="配备刘海的 Apple Silicon MacBook" />
  <img src="https://img.shields.io/badge/License-GPL--3.0-green?style=flat-square" alt="License GPL-3.0" />
  <img src="https://img.shields.io/badge/Fork%20of-TheBoredTeam%2Fboring.notch-purple?style=flat-square" alt="Fork" />
</p>

---

## 📖 项目渊源与致敬 (Origin & Acknowledgments)

本项目是基于开源社区著名项目 **[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)** 进行的深度二次开发（Fork）。

诚挚感谢 TheBoredTeam 的原开发者及所有开源贡献者。正是他们的工作奠定了本项目的基础；Dynamic Notch 是沿着这份成果继续探索的二开项目。

---

## 💡 二开初衷与设计理念 (Philosophy & Evolution)

相比原项目，本次二开的初衷是让界面更简单、更克制，也更贴近 Apple 原生 Live Activity 的设计哲学：信息一瞥即知、层次清楚、动效服务于内容。在保留并扩展实用工具的同时，尽量不让刘海显得拥挤。

本项目（**Dynamic Notch**）的二次开发初衷是：**更苹果、更 Live Activity、更简洁纯粹**。

我们坚信“少即是多（Less is More）”。刘海最打动人心的时刻，在于它宛若无形地隐于硬件之中，又在信息到来时如水滴般优雅溢出。

### 相对原分支（`origin/main`）的改动

- **项目与功能范围**：应用、Xcode 工程、Target 和 Scheme 更名为 DynamicNotch；移除日历与提醒事项集成。文件架仍然保留。
- **刘海与 HUD**：重做紧凑态与展开态、媒体双翼、切歌轻提醒、电池弹窗，以及独立的音量／亮度浮动 HUD 和过渡动画。
- **媒体播放**：加入六柱音乐可视化、多播放器支持、按应用筛选播放来源，并改进实时活动状态同步。
- **文件架与暂存板**：优化拖放、预览和分享；新增可持久化的文字暂存板、独立编辑窗口和拖放落点界面。
- **窗口分屏吸附（Windows 风格 Snap Layouts）**：加入类似 Windows 11 的屏幕顶边/刘海触发分屏系统，内置 5 种预设网格，支持按住 Shift 键一键将桌面所有窗口智能排布，并具备基于 SkyLight 的实验性磨砂玻璃幽灵替身动画（Ghost Animator），位移丝滑无闪烁；需要辅助功能权限。
- **外部实时活动**：授权的本地 macOS 应用可通过 Unix Domain Socket 发布活动与提醒；连接方需具备 Bundle ID，并经用户授权。详见[接口文档](docs/uds-live-activities.md)。
- **设置与本地化**：重整设置界面、限制开发者选项入口并扩充多语言 UI 文案；后续架构将辅助进程的功能移入主应用进程。
- **系统外观适配**：正在适配 macOS 26 Tahoe 的 UI，并计划适配 macOS 27（Golden Gate）；这是开发路线，不代表当前已完成兼容性验证。

---

## 📥 下载与安装 (Installation)

### 系统要求：
- **操作系统**：macOS 14.0 或更高版本；macOS 26 Tahoe 的 UI 适配进行中，macOS 27（Golden Gate）列入计划
- **设备支持**：配备内建物理刘海的 Apple Silicon MacBook；不支持 Intel Mac 或仅使用外接显示器的场景

---

### 手动安装步骤：

1. 前往 **[Releases 页面](https://github.com/linchi07/dynamic_notch/releases/latest)** 下载最新的 `DynamicNotch.dmg` 安装包；
2. 双击打开 DMG 文件，将 **Dynamic Notch.app** 拖拽至 **Applications**（应用程序）文件夹；
3. 若下载的版本尚未使用 Developer ID 签名并经过 Apple 公证，macOS Gatekeeper 可能提示安全警告。后续计划通过签名与公证改善安装体验；仅有签名不等于完成公证。
4. 按照系统提示在「系统设置 → 隐私与安全性 → 辅助功能」中授予权限，即可开启灵动体验。

---

## 🛠️ 从源码构建 (Building from Source)

如果你希望自行审计源码或参与开发，可以通过 Xcode 编译构建：

### 环境要求：
- macOS 14.0+
- 与项目 Swift 依赖及 macOS 14 SDK 兼容的 Xcode 版本

### 构建步骤：
```bash
# 1. 克隆本仓库
git clone https://github.com/linchi07/dynamic_notch.git
cd dynamic_notch

# 2. 用 Xcode 打开工程文件
open DynamicNotch.xcodeproj

# 3. 在 Xcode 中选择 Scheme 为 DynamicNotch，按下 Cmd + R 即可编译并运行
```

---

## 🗺️ 架构对比一览 (Comparison)

| 核心特性 | 原项目 (Boring Notch) | 二开版本 (Dynamic Notch) |
| :--- | :--- | :--- |
| **日历与提醒** | 内置集成 | 已移除 |
| **文件架** | 文件架 | 保留并优化，新增文字暂存板 |
| **媒体播放** | 音乐控制与可视化 | 六柱频谱、来源筛选与新版媒体界面 |
| **HUD 与提醒** | 原有系统事件界面 | 浮动 HUD、电池弹窗与切歌轻提醒 |
| **窗口分屏 (Snap Layouts)** | 无顶边吸附流程 | Windows 11 风格顶边选择器（5 款网格、Shift 全局平铺、磨砂幽灵动画） |
| **开发者接口** | 无本地实时活动 Socket | 需授权的 Unix Domain Socket 接口 |
| **设计取向** | 功能较广的桌面工具 | 更简洁、更贴近原生 Live Activity 的呈现 |

---

## 📄 开源许可 (License)

本项目继承原项目的开源许可，采用 **GPL-3.0** 许可证自由分发。完整且未经修改的许可证正文见 [LICENSE](LICENSE)，版权归属见 [NOTICE](NOTICE)。

> 本项目是 boring.notch 的衍生作品，因此必须继续沿用 GPL-3.0，不能改用其他协议。

**版权声明**

- Copyright (C) 2026 linchi —— Dynamic Notch
- Copyright (C) The Bored Team 及 boring.notch 贡献者 —— 上游项目 Boring Notch

### 致谢与开源依赖：
- **[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)**：本项目所 Fork 的上游原项目；
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)**：macOS 媒体播放状态原生监听支持；
- **[Pow](https://github.com/movingparts-io/Pow)**：精细动效支持；
- **[Defaults](https://github.com/sindresorhus/Defaults)**：现代化偏好设置持久化支持。

---

<p align="center">
  <em>Crafted with care by linchi07 &middot; Dedicated to the Apple design ethos.</em>
</p>
