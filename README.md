# 苏无度桌宠

苏无度是一个 Windows 原生桌面伴侣：透明、置顶、可拖动的像素角色，结合了专注计时、专注记录、喝水提醒、轻量桌面漫游和可选 AI 聊天。

项目当前版本为 `1.3.0`，使用 C#、WPF 和 .NET Framework 4.8 开发。应用不依赖 NuGet 包；ChatGPT 登录模式所需的 OpenAI Codex 运行组件随成品一起分发。

## 当前功能

### 桌面伴侣

- 12 种运行时状态：待机、眨眼、开心、工作、疑问、成功、错误、睡觉、提醒、挥手、比心和点击反应。
- 透明无边框窗口，可拖动、缩放、始终置顶或开启鼠标穿透。
- 支持多显示器；位置恢复和自动漫游都以当前显示器的可用工作区域为边界。
- 随机眨眼、挥手和比心；系统空闲约 5 分钟后自动睡觉。
- 可手动切换互斥的工作模式与睡眠模式。
- 可配置的低频自动漫游，默认在每次动作前随机等待 8–18 秒。
- 独立的透明文字气泡，不改变角色窗口大小，气泡区域不拦截鼠标。
- 系统托盘、启动面板、开始菜单入口、可选桌面快捷方式和开机启动。
- 单实例运行：再次启动会叫回现有桌宠并打开启动面板，不会创建第二个实例。
- 已安装版本会从 GitHub Releases 检查正式更新，下载完成后安全替换程序并自动重启。

### 专注与记录

- 可配置 1–120 分钟的专注计时，支持开始、暂停、继续、停止和重新开始。
- 开始与完成铃声可独立选择、试听或静音。
- 专注期间可启用随机微休息：每轮重新抽取间隔，分别播放“开始休息”和“继续工作”提示音。
- 运行中的计时会定期持久化；应用或电脑重启后，以暂停状态恢复剩余时间。
- 完整番茄钟自动写入专注记录；提前停止时，已经完成的整分钟会加入记录日的分钟调整。
- 记录日以本地时间 21:00 为分界，跨界专注会按实际完成片段拆分到两个记录日。
- 专注记录支持每日目标、分钟调整、手动补记、删除、每日 Notes、单次 Notes、当天纯文本复制和日期范围 Markdown 导出。
- 可配置喝水提醒间隔，并同时显示托盘通知和角色气泡。

### 聊天

应用提供三种聊天方式：

- **ChatGPT 登录**：通过随附的 Codex app-server 完成官方 OAuth 登录，动态读取账号可用的模型和推理强度。
- **OpenAI API**：使用开发者 API key 和自定义模型；API key 通过 Windows DPAPI 加密，仅当前 Windows 用户可解密。
- **离线陪伴**：不联网，提供简单的本地固定回复。

聊天窗口支持：

- `Enter` 发送，`Shift + Enter` 换行；
- 复制任意一条消息；
- 每次打开默认创建新聊天；可从左侧列表继续任意已保存聊天；
- 所有非空聊天自动保存在本机，并根据第一条用户消息生成标题；聊天可以归档和恢复，归档不会删除内容；
- “开启记忆功能”控制跨聊天精简记忆和明确要求记住的事实；关闭后仍会保存每个聊天；
- 最多保存 50 条用户明确要求“记住”的长期事实；
- 识别“请记住……”“记住：……”和“请忘记……”；
- “看屏幕”首次默认开启并记住上次选择；开启时每次发送只截取一张所有显示器画面，聊天窗口不会出现在截图中，请求结束后删除临时截图。

聊天历史和长期事实只保存在本机，不与 ChatGPT 网页版 Memory 同步。

## 交互约定

| 操作 | 结果 |
| --- | --- |
| 按住并拖动 | 移动桌宠 |
| 单击 | 播放点击互动；专注中显示 4 秒动态剩余时间 |
| 双击 | 开始专注 → 暂停 → 继续 |
| 三击 | 打开聊天窗口 |
| 睡眠时两次分开的单击 | 4 秒内完成两次锤击后叫醒 |
| 右键 | 打开完整功能菜单 |
| `Ctrl + Alt + P` | 关闭鼠标穿透并叫回桌宠 |
| 双击托盘图标 | 叫回桌宠 |

快速双击在睡眠状态下仍属于专注手势，不计作两次分开的叫醒锤击。

应用内的“使用说明书”面向最终用户，包含全部日常操作、专注记录、聊天设置和隐私说明。

## 运行现有成品

仓库中的两个输出属于不同的交付范围：

- `dist\SuWuDu\SuWuDu.exe`：开发/便携版入口；
- `dist\苏无度安装程序.exe`：当前用户范围的安装包。

便携版也可以通过根目录的 `Start Desktop Pet.cmd` 启动。安装包不要求管理员权限，默认安装到：

```text
%LocalAppData%\Programs\SuWuDuDesktopPet
```

当前成品没有商业代码签名，因此 Windows 可能在首次运行时显示安全提示。

## 从源码构建

### 环境要求

- Windows 10 或 Windows 11；
- .NET Framework 4.8；
- Visual Studio 2022 Build Tools，包含 MSBuild 和 Roslyn C# 编译器；
- PowerShell 5.1 或更高版本。

`build.ps1` 会通过 `vswhere.exe` 查找最新的 Visual Studio Build Tools，并使用 .NET Framework MSBuild 构建 x64 Release 输出。

两个体积较大的 Codex Runtime EXE 不进入 Git；本地构建会校验现有文件，GitHub Actions 则会根据 `codex-package.json` 从 OpenAI 官方 GitHub Release 恢复并校验固定版本，避免云端产物缺少聊天组件。手动恢复命令：

```powershell
.\Scripts\RestoreCodexRuntime.ps1
```

### 开发版

```powershell
.\build.ps1
```

输出：

```text
dist\SuWuDu\SuWuDu.exe
```

构建并启动，或直接启动已有输出：

```powershell
.\run.ps1
```

需要 Debug 配置时：

```powershell
.\build.ps1 -Configuration Debug
```

### 安装包

安装包是独立交付物。先生成最新开发版，再单独构建安装包：

```powershell
.\build.ps1
.\build-installer.ps1
```

输出：

```text
dist\苏无度安装程序.exe
```

安装脚本会验证 `Assets\asset-classification.json`：所有运行时素材必须被标记为 `used`，源文件、提示词和归档素材必须被标记为 `unused`，未分类或错误进入成品的素材会使构建失败。

### 自动更新与发布

自动更新只对安装版启用；`dist\SuWuDu` 开发/便携版不会覆盖自己的文件。安装版启动后最多每 6 小时静默检查一次，也可以从桌宠右键菜单或托盘菜单选择“检查更新”。用户设置、聊天记录、专注记录和离线数据位于 `%LocalAppData%\PixelHeartDesktopPet`，更新程序目录时不会被删除。

每个正式 GitHub Release 必须包含同一版本的三个文件：

```text
苏无度安装程序.exe
SuWuDu-update-v1.3.0.zip
SuWuDu-update-v1.3.0.zip.sha256
```

本地生成完整发布产物：

```powershell
.\build-release.ps1 -Version 1.3.0
```

也可以推送符合 `v*.*.*` 格式的 tag，由 `.github\workflows\release.yml` 在 Windows runner 上构建并创建 GitHub Release：

```powershell
git tag v1.3.0
git push origin v1.3.0
```

仓库必须保持公开，或者另行提供安全的认证更新服务；应用不会内置 GitHub token。第一批用户仍需手动安装包含更新器的 `1.3.0` 安装包，之后发布 `1.3.1` 或更高版本时即可在应用内升级。

## 代码结构

```text
DesktopPet.csproj             WPF/.NET Framework 4.8 项目定义
App.xaml(.cs)                 全局样式、单实例启动、异常记录和唤醒事件
MainWindow.xaml(.cs)          桌宠窗口、状态编排、手势、计时、托盘和菜单
ChatWindow.xaml(.cs)          聊天界面、屏幕附图与消息展示
SettingsWindow.xaml(.cs)      外观、提醒、专注、AI 与记忆设置
HelpWindow.xaml(.cs)          面向最终用户的内置使用说明书
LauncherWindow.xaml(.cs)      可固定到任务栏的启动与管理面板
FocusJournalWindow.xaml(.cs)  专注记录浏览和编辑
FocusExportWindow.xaml(.cs)   Markdown 导出范围选择
UpdateWindow.xaml(.cs)        GitHub Release 更新提示、说明和下载进度
Models/                       设置、命令、聊天记忆和专注记录数据结构
Services/                     持久化、AI、声音、动画、屏幕、漫游等服务
Assets/Sprites/               应用实际加载的运行时图片
Assets/Source/                维护和重新生成当前素材所需的源文件
Assets/Archive/               历史素材，不参与构建
Scripts/                      素材生成与外部控制脚本
Installer/                    自包含安装器和卸载器源码
Updater/                      主程序退出后验证、替换和回滚的独立更新器
Tests/                        当前的 Codex 账号/模型集成烟雾测试源码
Tools/Codex/package/          随成品分发的 Codex Windows 运行组件
```

### 主要运行关系

`App` 负责单实例和 Shell 入口；`MainWindow` 是桌宠状态与交互的协调中心；具体能力由 `Services` 中的独立服务完成：

- `SpriteAnimator` 和 `HammerAnimator` 管理角色动画与点击反馈；
- `WanderController` 负责当前显示器内的低频移动；
- `ActiveFocusStateService` 保存未完成计时；
- `FocusJournalService` 与 `FocusTimeAccounting` 负责记录、21:00 分界和跨日分钟分配；
- `AiService` 在 ChatGPT、OpenAI API 和离线三种 provider 之间路由；
- `CodexAppServerClient` 管理 Codex app-server、OAuth 状态、模型列表和消息；
- `ScreenCaptureService` 只在“看屏幕”开启时生成临时截图，并在捕获时排除聊天窗口；
- `MemoryService` 管理本地聊天 thread、标题、归档、精简摘要和长期事实；
- `SettingsService`、`SecretService` 和 `StartupService` 分别处理普通设置、加密 key 和开机启动。

## 本地数据

运行时数据统一保存在：

```text
%LocalAppData%\PixelHeartDesktopPet
```

| 文件或目录 | 用途 |
| --- | --- |
| `settings.json` | 窗口位置、外观、提醒、专注和聊天方式等普通设置 |
| `secret.dat` | 当前 Windows 用户可解密的 OpenAI API key |
| `chat-memory.json` | 所有聊天 thread、标题、归档状态、精简摘要和长期事实 |
| `focus-journal.json` | 专注记录、目标、调整和 Notes |
| `active-focus.json` | 未完成专注计时的恢复快照 |
| `command.json` | 外部程序写入的一次性状态命令 |
| `error.log` | 未处理异常诊断日志 |
| `CompanionWorkspace\` | Codex 聊天使用的隔离工作目录 |
| `ScreenCaptures\` | “看屏幕”产生的临时截图目录 |

普通 JSON 状态写入会使用临时文件和备份文件降低损坏风险。进行中的专注计时恢复为暂停状态，因此关机、睡眠或应用未运行的时间不会被误算为专注时间。

## 外部状态联动

Codex、自动化脚本或其它本地工具可以发送一次性状态和气泡文字：

```powershell
.\dist\SuWuDu\Scripts\PetControl.ps1 `
  -State working `
  -Message '正在处理任务…'

.\dist\SuWuDu\Scripts\PetControl.ps1 `
  -State success `
  -Message '任务完成！'
```

可用状态：

```text
idle blink happy working question success error sleeping reminder waving heart
```

也可以直接写入：

```text
%LocalAppData%\PixelHeartDesktopPet\command.json
```

```json
{
  "state": "question",
  "message": "需要你的输入。"
}
```

应用每秒检查一次该文件，读取后删除。未知状态会回退为 `idle`；没有消息时只更新动画。

## 素材维护

`Assets\Sprites` 是唯一参与运行和安装的图片目录。源图、生成中间文件和旧版本不要放入该目录。

当前素材脚本：

```powershell
.\Scripts\BuildStableWorkingAtlas.ps1
.\Scripts\ExtractAnimationAtlases.ps1
.\Scripts\BuildSleepingLayers.ps1
```

具体分类、归档和重新生成规则见 [`Assets\README.md`](Assets/README.md)。

## 测试与验证

- `.\build.ps1` 是当前开发版的基础编译验证。
- `Tests\CodexSmokeTest.cs` 覆盖已登录 ChatGPT 账号的状态、模型列表、模型回退、推理强度和图片消息链路；它依赖真实账号登录，不是离线单元测试。
- 仓库目前没有完整的自动化 UI 测试。透明、无边框和鼠标穿透相关交互仍应在 Windows 桌面环境中手动验证。
- 安装包验证与开发版验证是两个独立范围；修改开发版后不会自动重建安装包。

## 第三方组件

成品包含 OpenAI Codex `0.144.4` Windows 组件。版本与来源见 `Tools\Codex\package\codex-package.json` 和 `THIRD-PARTY-NOTICES.txt`，随附许可证正文见 `OPENAI-CODEX-LICENSE.txt`。
