# The Styk

<p align="center">
  <img src="assets/logo.png" width="128" alt="The Styk Logo" /><br>
  <sub>
    <b>版本:</b> macOS (Apple Silicon 11+ / Intel 10.15+) | Windows 10/11<br>
    <b>语言:</b> Português (Brasil), English, Deutsch, Français, 日本語, 简体中文
  </sub>
</p>

住在 Mac 文件夹里的数字化便签。

The Styk 是一款极为小巧的程序，可以将数字化便签锚定在您的 Finder 文件夹中。当您停留在创建该便签的文件夹时，便签会悬浮在屏幕上——离开文件夹，便签消失；返回文件夹，便签重新出现。

## 安装

在 https://setor101.com.br/apps/styk 下载 The Styk，将其拖入您的“应用程序”（Applications）文件夹，然后双击图标启动它。

> [!NOTE]
> **macOS 安全警告 (Gatekeeper)**
>
> 如果您看到“Apple 无法验证此 App 是否包含恶意软件...”的警告，请注意，这是由于 Apple 要求开发者支付年费以对应用程序进行数字签名。由于 The Styk 是一个免费且开源的项目，我们认为这一财务要求对独立开发者而言是不公平的。
> 
> 仍要打开此 App：
> 1. 尝试打开一次 App 以触发警告，然后关闭它。
> 2. 前往 Mac 上的 **系统设置 (System Settings)** > **隐私与安全性 (Privacy & Security)**。
> 3. 向下滚动至 **安全性** 部分，然后点击关于 `The Styk.app` 提示下方的 **仍要打开 (Open Anyway)** 按钮。
> 4. 输入您的密码或使用 Touch ID 进行确认。

## 使用方法

The Styk 会在菜单栏右侧放置一个便签图标。点击该图标显示菜单。从这里，您可以选择 **“New note in this folder（在此文件夹新建便签）”** 来创建便签。直接在其中输入即可，便签会自动保存。

### 菜单栏
状态栏菜单列出了所有便签（按文件夹分组）。点击任何便签可直接在 Finder 中跳转到该文件夹、导出或删除它。

### 便签交互
将鼠标悬停在便签上可显示其操作栏。您可以：
- 更改便签颜色。
- 调整字体大小（A− / A+）和字体样式（Aa）。
- 分享便签（通过 AirDrop、信息、邮件等）。
- 删除便签。

拖动便签背景可移动它，拖动边缘可调整大小。在便签内部，使用 `⌘ +` 和 `⌘ −` 快捷键可以快速调整文本大小。

### 偏好设置（Preferences）
从栏菜单中打开“偏好设置”（Preferences）进行配置：
- **Language（语言）**：在葡萄牙语（巴西）、英语、中文、日语、德语或法语之间切换。
- **Finder Permission（Finder 权限）**：管理跟踪活动 Finder 窗口所需的 Apple Events 自动化权限。
- **Start at Login（开机启动）**：切换是否在启动 Mac 时自动打开 The Styk。
- **Backups（备份）**：配置自动每日本地备份，或手动导出/恢复所有便签。

## FAQ（常见问题）

### 这需要特殊权限吗？
是的。首次启动时，macOS 会请求控制 Finder 的权限。这是必需的，以便 The Styk 检测当前活动文件夹并显示相应的便签。如果您不小心拒绝了该权限，可以通过“偏好设置” -> “Request Finder permission...（请求 Finder 权限...）”按钮重新触发提示。

### 当我删除便签时会发生什么？
删除操作是完全可逆的。删除的便签会进入应用内部的垃圾箱（可通过菜单栏访问），并在 5 天后自动彻底清除。

### 如果我移动、重命名或删除文件夹，会发生什么？
- **移动/重命名的文件夹**：The Styk使用 macOS 书签（Bookmarks）机制，因此即使您重命名文件夹或将其移动到其他磁盘，便签也会自动跟随该文件夹。
- **删除的文件夹**：便签不会丢失；它们会被移至菜单中的“Orphan notes（孤立便签）”部分，您可以在此处重新锚定、导出或删除它们。

### 它支持 macOS 10.x 吗？
主要的 Apple Silicon 版本需要 macOS 11 (Big Sur) 或更高版本。但是，也提供了一个兼容 macOS 10.15 (Catalina) 及更高版本的 Intel 遗留版本。

### The Styk 与普通的便签有什么不同？
与普通的便签应用（便签会无期限地堆满您的桌面）不同，The Styk 将便签上下文锚定到特定的文件夹。它们只有在您实际在 Finder 中打开并查看该文件夹时才会出现。
