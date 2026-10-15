# Windows 与 Mac 功能差异及接续清单

核对日期：2026-10-15。本文描述当前仓库源码：任务与 Claude 功能先在 Mac 实现，共享动画及对应 Windows 播放逻辑则已更新。源码已实现不等于 Windows 开发版或安装包已重建。

## 在 Windows 接续

在仓库根目录拉取最新 `main`；先处理本机已有修改，避免覆盖其他工作。缺少被 Git 忽略的 Codex 运行组件时，先在线还原，再构建开发版：

```powershell
git pull --ff-only origin main
.\Scripts\RestoreCodexRuntime.ps1
.\build.ps1
```

开发版入口是 `dist\SuWuDu\SuWuDu.exe`。构建需要 Visual Studio Build Tools 的 .NET 桌面构建工具；`build.ps1` 本身以 `-NoDownload` 检查 Codex，因此仅拉源码后直接构建可能提示缺组件。已有完整组件时，还原脚本只校验。此流程构建当前 Windows 功能，下面标为“待实现”的功能仍需移植。

GitHub 保存源码、测试、说明及共享美术资源；`dist/`、`Mac/output/`、`Mac/runtime/` 等本机构建/运行产物不通过源码 push 分发。个人任务、备忘、聊天及登录凭据也不会随 Git 同步。开发版构建与安装包是独立范围，只有明确要求安装包时才运行 `build-installer.ps1`。

## Claude 订阅连接（2026-10-14）

| 能力 | Mac 开发版 | Windows |
|---|---|---|
| 连接自己的 Claude 订阅 | 设置中选择 Claude 登录，账号区与 ChatGPT 排版一致；支持连接、刷新账号和模型、退出登录和取消登录 | 待实现，无 Claude 入口 |
| 模型与推理强度 | 动态读取官方 CLI 模型元数据，仅显示模型支持的强度；默认自动选择／模型默认，保存后供三类 AI 功能共用 | 待实现 |
| 聊天与看屏幕 | 使用同一 Claude 连接，支持现有聊天上下文和可选截图 | 待实现 |
| 备忘提取、番茄匹配 | 使用现有固定指令、严格 JSON Schema、本地校验和预览应用流程 | 待实现 |
| 凭据与运行组件 | 随附原样官方 Claude Code 2.1.300；凭据由官方组件管理，应用配置目录隔离 | 尚未分发 Claude 组件或保存其凭据 |
| API 回退 | 每次请求确认 Claude 订阅登录，不传入 API key / token 环境覆盖，不自动改用其它服务 | 原有 ChatGPT / OpenAI API / 离线行为不变 |

Mac 的订阅限额及 Claude 账户中已启用的额外用量设置仍适用；应用不能覆盖该账户设置。用户可直接在 [Claude 官方用量设置](https://claude.ai/settings/usage) 中关闭额外付费；应用账号区不另设用量按钮。此保证是不会自动切到 API 凭据或另一 provider，并非承诺无限额度或禁用 Claude 已启用的额外用量。

模型目录通过 `initialize` 控制响应读取，不发送用户回合、不进行推理。模型名称旁显示官方 `resolvedModel` 完整型号，“自动选择”也显示当前对应型号；缺少该字段时保留原名称，不猜版本。保存仍使用官方原始 `value`／别名，不锁定版本。已保存但当前不可用的选择仍保留显示，发送前验证；失败不会自动换模型或切换 API。当前目录没有可靠的订阅计费权字段，因此暂不提供 Fable 及其别名和明确的 `[1m]` 付费变体；推理强度不提供 `ultracode`。

本节 Claude 功能仅更新了 Mac 开发版；Windows 的 Claude 源码、运行组件及开发输出尚未实现，未更新安装包或 Mac DMG。

### 登录、凭据与平台组件

| 项目 | Mac 当前实现 | Windows 当前实现／移植要求 |
| --- | --- | --- |
| ChatGPT / Codex 登录凭据 | 官方 Codex 使用 `cli_auth_credentials_store="keyring"`，由 macOS Keychain 保存；独立 `CODEX_HOME` 在应用数据的 `Codex/` | 官方 Codex 使用 `cli_auth_credentials_store=file`，独立 `CODEX_HOME` 在 `%LocalAppData%\PixelHeartDesktopPet\CodexHome`；不是 `secret.dat` |
| OpenAI API key | 应用通过 macOS Keychain 保存 | `Services/SecretService.cs` 用当前 Windows 用户的 DPAPI 加密保存到 `secret.dat`；这是 API key 的存储，不是订阅登录凭据 |
| Claude 登录凭据 | 随附的官方 Claude Code 管理，独立 `CLAUDE_CONFIG_DIR`；应用不读取或复制 token | 待接入对应 Windows 官方组件和其凭据机制；不能直接使用 Mac 二进制、Keychain 或 Darwin 签名校验流程 |
| 桌面应用依赖 | 使用随附 CLI，无需 Codex Desktop 或 Claude Desktop | 当前 ChatGPT 可使用随附 Codex，无需 Codex Desktop；Claude 移植也应保持此方式 |

浏览器授权完成登录，之后 CLI 从本机凭据存储恢复会话；跨电脑需要在当地登录，不能把 Mac 凭据或 Windows DPAPI 文件当作可移植配置。Windows Claude 接入应保留 Mac 的独立配置/工作目录、环境变量白名单、禁用工具与项目配置、取消/超时终止子进程，以及订阅登录校验；不能继承 API key 或因失败切换付费方式。模型与推理强度要为 ChatGPT、Claude 分别保存。实现参见 [ClaudeClient.swift](Sources/SuWuDu/ClaudeClient.swift) 和 [ClaudeModels.swift](Sources/SuWuDu/ClaudeModels.swift)；Mac 下载脚本的架构、哈希及签名逻辑需另做 Windows 适配。

## 任务与专注（2026-10-15）

以下功能已先在 Mac 开发版实现，Windows 本次未移植，仍使用原专注记录窗口。

| 功能 | Mac | Windows |
| --- | --- | --- |
| 批量目标 | 自选日期范围、整个月、指定日期起所有未来日期；只覆盖目标，保留记录和 Notes | 待实现 |
| 快速分钟增减 | 分别输入“增加分钟”“减少分钟”，保留直接填写正负分钟调整 | 原有分钟调整输入框；快捷增减待实现 |
| 统一任务清单 | 名称、可选预计番茄数、截止日期/时间、说明、完成状态 | 待实现 |
| 备忘与清单迁入 | 自由备忘、转任务、粘贴清单并预览导入 | 待实现 |
| AI 备忘提取 | 提取可执行任务、保留原文出处，编辑/勾选预览后整批导入 | 待实现 |
| 已完成任务历史 | 完成时间、任务说明/出处、实际投入和关联专注明细 | 待实现 |
| 紧凑番茄表格 | 只显示计入数量的番茄钟，含分钟换算；一行显示时间、分钟、任务用时、来源（自动／手动／分钟换算）与 Notes，点击 Notes 或箭头区域展开，保持 30 点行高 | 待实现 |
| 提前结束与未计入明细 | 提前结束只计实际分钟，明细在“目标与分钟调整 → 分钟明细”中编辑任务、分钟、Notes 或删除；未计入目标的普通记录放在“未计入记录”，可恢复计入 | 待实现 |
| 展开点击范围 | 所有展开标题行及空白区域可点击，最小高度 32 点；涵盖分钟调整、任务匹配、备忘原文和归档聊天 | 待实现 |
| 多任务用时分配 | 一个番茄关联多个任务，默认均分，以分钟调整；25 分钟可分为 12.5/12.5 或 10/15 | 待实现 |
| 当前任务沿用 | 每轮启动捕获完整任务分配；途中切换仅影响下一轮；暂停/恢复保留本轮分配 | 待实现 |
| 事后匹配 | 任务卡快捷操作与多选记录默认追加任务；保留单条分钟编辑，以及明确的重新分配用时、清空关联和整批撤销 | 待实现 |
| AI 匹配 | 一句话整理多任务分配、未关联记录建议、任务用时前后及原因预览、完整分配与修订号校验 | 待实现 |
| 本机匹配建议 | Notes 中出现明确且唯一的完整任务名时生成建议，离线可用 | 待实现 |
| 任务投入 | 按分配比例累计小数番茄数与实际分钟；提前结束只计分钟，目标换算记录不重复计量 | 待实现 |
| 复制/导出 | 保留日期范围 Markdown，包含时间、各任务分配分钟和提前结束明细 | 原有导出格式 |
| Notes 编辑 | 原生输入法组合状态保护、8 点内部留白；计时更新不覆盖正在输入的拼音或选区 | 现有 WPF 文本框；保留中文输入体验，不能直接照搬 AppKit 实现；未认定 Windows 存在同类缺陷 |

Mac 的新功能合并在原专注记录入口，保留每日目标、批量目标、正负分钟调整、补记、忽略目标、删除、每日/单次 Notes、保存、复制和范围导出。继续使用既有浅青配色及共享控件。提前结束明细继续保存在原数据中，任务投入、完成历史和导出保留其实际分钟且只计一次；无需迁移旧数据。主表全选、未关联选择、Shift 连选、批量操作和 AI／本机匹配仅处理计入数量的实际番茄钟，不包含提前结束、未计入记录或分钟换算记录。

**追加任务…** 只选择要加入的任务，每条记录分别保留自己的旧任务并加入所选任务，不在记录间复制任务。加入新任务后该条记录默认均分全部最终任务；只重复选择已有任务时保留原自定义分钟，整批无变化也保留之前的撤销记录。未关联记录均分新增任务。更多菜单的 **重新分配用时…** 明确替换完整分配，**清空任务关联** 明确清除；原有过期检查、原子应用和整批撤销继续生效。Windows 此次未实现这些操作。

### 数据与 AI 边界

- 新任务、备忘、运行时任务分配与记录关联保存在 Mac 的 `app-state.json`，旧 Mac 数据无需手动迁移；旧单任务 ID 按 100% 份额读取，没有任务的旧记录仍未关联。新增分配数组在读写时校验，无效数据使用现有备份恢复机制。
- 从 Windows 导入时仍按原规则替换匹配日期，保留 Mac 任务/备忘以及同 ID 记录的完整任务分配；被替换日期中的 Mac 专注明细可能随导入被替换。新任务字段不回写 Windows，不提供两平台任务同步。
- 截止日期使用普通本地日历；只填日期时过了当天才算逾期，与专注记录的 21:00 换日独立。
- AI 番茄匹配使用 Mac 已选择的 ChatGPT/Codex、Claude 订阅或 OpenAI API，接收用户说明、任务 ID/名称/说明，以及请求范围内的记录 ID、时间、顺序编号、实际分钟、已有分配、单次 Notes 和时区；不发送聊天、自由备忘或截图。离线模式使用本机明确关键词建议。
- 匹配协议固定为 `{"matches":[{"sessionID":"…","allocations":[{"taskID":"…","share":1}],"reason":"…"}]}`。各层字段必填、禁止额外字段，只能引用快照内 ID；内部 share 为正数、非空分配合计 1，用户界面使用分钟。AI 负责将用户的分钟/比例说明转换为完整最终分配，并区分添加、删除、替换和清空；空数组明确清空，省略记录保持原样，未知或有歧义时不猜测。本地只校验规范结果，不再解析用户语句。
- AI 备忘提取向所选服务发送专用固定指令、当前备忘、本地日期/时区上下文及严格 JSON Schema，保留原备忘。任务结果固定包含 `title`、`estimatedPomodoros`、`dueDate`、`dueTime`、`notes`、`sourceExcerpt`；预计数为 0–10000 的整数或 null，日期/时间为有效的 `YYYY-MM-DD` / `HH:mm` 或 null，时间必须有日期。
- 用户的横线后数字、下一行数字、命名子任务 `+N` 等备忘习惯由 AI 解释；父任务和子任务预算分开，课程号不当作预算。AI 根据参考日期/时区规范化明确截止日期；本地仅检查契约、类型、范围、日期有效性和原文完整性，不解析备忘写法或限定截止日期词表。Windows 尚无此功能。离线时仍可手动转任务或粘贴导入。
- AI 返回建议，不直接改数据；有歧义保持原关联。整批应用、撤销按稳定记录 ID、完整分配与修订号校验，保留记录总分钟、Notes 和目标状态。
- 当前支持粘贴导入，没有 Google Docs 自动同步。本次只更新 Mac 开发 `.app`，Windows 开发版及两平台安装分发包不在本次范围。

### Windows 数据与结算移植要点

- **数据布局不同**：Mac 的设置、任务、备忘、专注恢复、记录及聊天位于同一个原子写入的 `app-state.json`。Windows 当前分别保存 `settings.json`、`focus-journal.json`、`active-focus.json` 和 `chat-memory.json`，并不直接读取 Mac 文件。应设计 Windows 的向后兼容字段和一致性保存，不能只复制 UI，也不能把“代码同步”当作“两端业务数据同步”。
- **新增模型**：任务需保存稳定 ID、名称、预计番茄数、截止日期/是否含时间、Notes、完成状态/完成时间、原文出处及创建/修改时间。下一轮选择和正在运行的专注均需保存完整任务分配；记录需保存 `taskAllocations`（`taskID` / `share`）、`assignmentSource`、`assignmentRevision`、`actualMinutes`、`completedPomodoro`，兼容旧的单 `taskID` 和缺字段记录。分配必须唯一、有限、正数且合计 1，空数组表示未关联。
- **保留新字段**：Windows 当前 `FocusJournalService.NormalizeSession` 会将非 `automatic` 来源改为 `manual`；移植时必须保留 `partial`。同时更新序列化、`CloneSession`、导入/保存/撤销和 `ActiveFocusStateData`，防止编辑、克隆或重启恢复时丢失任务分配与结算标记。记录来源 `source` 与任务关联来源 `assignmentSource` 含义不同。
- **提前结束只入账一次**：Windows 现在只把提前结束的整分钟加到分钟调整；Mac 另外保存 `source="partial"`、`countsTowardGoal=false` 的明细及分配，用于任务投入、编辑、历史与导出。其分钟已经进入调整，不能再把明细加进当天总分钟。修改/删除明细时按修改前后 partial 分钟差更新调整，再执行原有结算。暂停时间排除；21:00 换日和跨日实际片段分配保持原规则。
- **换算标记明确**：分钟换算记录用 `actualMinutes=0`、`completedPomodoro=false` 且非 `partial` 标识，不通过 Notes 文案、`source="manual"` 或显示分钟为 0 猜测。换算单位可计入每日数量并显示在主表，但不可再次分配任务或重复累计任务投入。普通手动补记是独立完整记录；时间重叠也不自动去重。
- **显示范围与任务统计分开**：主表是非 partial 且 `countsTowardGoal=true`；可批量/AI 关联范围再排除分钟换算。提前结束进入分钟明细，其他未计入条目保留在可恢复区域。任务历史和实际投入从完整存储记录计算，按 `taskMinutes` 与 `isCompletedPomodoro` 分摊，不按主表过滤结果计算；已实际完成但被取消每日计数的记录仍可能代表任务投入。
- **统一 AI 契约**：同时移植专用指令、JSON Schema、解析/校验与请求快照限制，不能只复制 prompt。失败、取消、超时、格式错误或快照过期均不得导入/关联；预览应用、保存和整批撤销使用完整分配及修订号，防止异步结果覆盖新编辑。具体长度/条数边界以当前实现为准。

## 已同步到两端源码的动画

这些变更已经包含 Windows 播放代码，不属于上述待移植功能；仍需在 Windows 重建开发版并检查实际播放。

| 内容 | 当前状态 |
| --- | --- |
| 苏无度挥手与提醒 | 共享 v3 美术资源及播放选择已更新 |
| 沈青动作 | 11 类动作使用 v4 的 16 帧资源；睡眠使用单张底图及独立 Z 图层，Z 的位置/运动按朝向镜像，字形不翻转 |
| 待机与点击 | 沈青在两端均更新为 60–120 秒待机小动作及 980 毫秒受击反馈；再次点击重新开始受击动画 |
| 运行素材与草稿 | `Assets/Sprites/` 是运行素材，Windows 项目构建会自动复制；`Assets/Source/` 的护头/睡姿候选与 `Assets/Archive/` 是源稿/留档，拉取后不会自动启用候选 |

对应 [Assets/README.md](../Assets/README.md)、[Services/SpriteAnimator.cs](../Services/SpriteAnimator.cs)、[MainWindow.xaml.cs](../MainWindow.xaml.cs) 和 [Mac PetPanel.swift](Sources/SuWuDu/PetPanel.swift)。无需为使用已提交帧而重新运行 atlas 生成脚本。

## 接续代码与验证索引

| 范围 | Mac 参考实现 | Windows 接续位置 |
| --- | --- | --- |
| 任务/分配/历史/撤销 | [FocusTasks.swift](Sources/SuWuDu/FocusTasks.swift)、[AppModelFocusTasks.swift](Sources/SuWuDu/AppModelFocusTasks.swift)、[FocusAllocationEditor.swift](Sources/SuWuDu/FocusAllocationEditor.swift) | `Models/`、`Services/FocusJournalService.cs`，新增任务与分配模型/服务 |
| 计时/恢复/结算/存储 | [Core.swift](Sources/SuWuDu/Core.swift)、[AppModel.swift](Sources/SuWuDu/AppModel.swift)、[Persistence.swift](Sources/SuWuDu/Persistence.swift) | `MainWindow.xaml.cs`、`Models/FocusJournalData.cs`、`Models/ActiveFocusStateData.cs`、`Services/FocusTimeAccounting.cs`、`Services/ActiveFocusStateService.cs` |
| 合并面板与交互 | [JournalView.swift](Sources/SuWuDu/JournalView.swift)、[FocusTasksView.swift](Sources/SuWuDu/FocusTasksView.swift)、[Theme.swift](Sources/SuWuDu/Theme.swift)、[NotesEditor.swift](Sources/SuWuDu/NotesEditor.swift) | `FocusJournalWindow.xaml` / `.xaml.cs`、共享 WPF 样式、入口与使用说明 |
| AI 备忘/匹配 | [FocusMemoExtraction.swift](Sources/SuWuDu/FocusMemoExtraction.swift)、[FocusTaskMatching.swift](Sources/SuWuDu/FocusTaskMatching.swift)、[AppModelMemoTasks.swift](Sources/SuWuDu/AppModelMemoTasks.swift)、[AIService.swift](Sources/SuWuDu/AIService.swift) | `Services/AiService.cs`、`Services/CodexAppServerClient.cs`，新增结构化提取/匹配调用 |
| Claude 设置/运行组件 | [ClaudeSettingsView.swift](Sources/SuWuDu/ClaudeSettingsView.swift)、[ClaudeClient.swift](Sources/SuWuDu/ClaudeClient.swift)、[ClaudeModels.swift](Sources/SuWuDu/ClaudeModels.swift)、[fetch-claude-runtime.py](scripts/fetch-claude-runtime.py) | `SettingsWindow.xaml` / `.xaml.cs`、`Models/AppSettings.cs`、新增官方 Windows Claude 组件与客户端、开发构建脚本 |

Mac 已做的保存失败处理、编辑期间字段合并、导入并发、备份恢复、严格日期/整数输入、请求取消和旧进程回调隔离等修复见 [BUG_AUDIT.md](BUG_AUDIT.md)。Windows 移植时逐项对照；这份 Mac 审查不代表已确认 Windows 也有同一 bug。

Windows 验收应覆盖：旧数据缺字段仍可读写；25 分钟分成 10/15 只累计 0.4/0.6；提前结束 10+15 分钟仅换算一颗且任务用时只计一次；明细编辑/删除同步调整；未计入记录恢复；不同记录追加任务各保留旧分配；重复追加不改变自定义分钟；异步结果过期被拒绝、整批撤销；中文组合输入不被计时刷新打断；展开标题/留白可点击；Claude 模型/强度贯通聊天、提取和匹配且失败不转 API。

可按语义移植 [FocusJournalRecordsTests](Tests/SuWuDuTests/FocusJournalRecordsTests.swift)、[FocusTaskAppendTests](Tests/SuWuDuTests/FocusTaskAppendTests.swift)、[FocusAllocationTests](Tests/SuWuDuTests/FocusAllocationTests.swift)、[FocusAllocationEditorTests](Tests/SuWuDuTests/FocusAllocationEditorTests.swift)、[FocusMemoExtractionTests](Tests/SuWuDuTests/FocusMemoExtractionTests.swift)、[FocusTaskMatchingTests](Tests/SuWuDuTests/FocusTaskMatchingTests.swift)、[ClaudeClientTests](Tests/SuWuDuTests/ClaudeClientTests.swift)、[ClaudeModelTests](Tests/SuWuDuTests/ClaudeModelTests.swift) 和 [ClaudeProviderTests](Tests/SuWuDuTests/ClaudeProviderTests.swift)。已有 Mac 验证及限制见 [VALIDATION.md](VALIDATION.md)；不能把这些通过记录当作 Windows 验证结果。
