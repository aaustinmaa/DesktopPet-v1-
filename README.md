# 苏无度桌宠

一个可直接运行的 Windows 原生 WPF 桌宠。角色基于 `v1image.png` 重新绘制成 12 帧透明像素动画，小巧、置顶、可拖动，也可以安静地待在托盘里。

## 直接运行

双击：

```text
Start Desktop Pet.cmd
```

已构建的便携版位于：

```text
dist\DesktopPet\DesktopPet.exe
```

不需要安装。Windows 首次显示安全提示时，可以展开“更多信息”后选择运行；这是因为便携版没有商业代码签名。

## 主要功能

- 12 个统一风格的透明像素状态：待机、眨眼、开心、工作、疑问、成功、错误、睡觉、提醒、挥手和心跳。
- 透明无边框小窗口，默认约 170 × 195 px，可拖动、缩放、置顶。
- 点击弹跳、随机眨眼/挥手/心跳，长时间离开后自动睡觉。
- 可选的轻量桌面漫游。
- 系统托盘：叫醒、聊天、专注、设置、退出。
- 鼠标穿透模式；任何时候按 `Ctrl + Alt + P` 都能恢复交互。
- 登录 Windows 时自动启动。
- 保存上次位置、大小和所有偏好；恢复时会检查位置是否仍在屏幕上。
- 内置专注计时器和喝水提醒。
- 双击打开通用聊天窗口；默认可用官方 ChatGPT OAuth 登录，无需 API key。
- 三种聊天方式：ChatGPT/Codex、OpenAI 开发者 API、完全离线。
- 保存最近聊天，并持久记住用户明确要求“记住”的信息；可以随时关闭或清除。
- OpenAI API key 使用 Windows DPAPI 加密保存在当前用户目录。
- 可由 Codex、脚本或其它程序发送状态命令，实现“工作中 / 完成 / 出错 / 等待输入”等联动。

## 操作

- 单击并拖动：移动桌宠。
- 双击：打开聊天。
- 右键：打开完整菜单。
- `Ctrl + Alt + P`：恢复鼠标交互并叫回隐藏的桌宠。
- 双击托盘图标：叫醒桌宠。
- 再次双击启动程序：不会创建第二只桌宠，而是直接叫回并置前现有桌宠。

## AI 聊天与登录

右键桌宠 → **设置**：

1. 选择 **ChatGPT 登录**（推荐）。
2. 点击 **连接我的 ChatGPT**，在浏览器中完成 OpenAI 官方 OAuth 登录。
3. 回到设置，看到“已连接”后保存。
4. 双击苏无度即可进行通用聊天。

这条路径使用账号中可用的 Codex 订阅额度，不会把 ChatGPT 密码交给桌宠，也不需要 API key。模型下拉框会读取当前账号真正可用的选项；推理强度下拉框会进一步读取所选模型支持的级别和默认值。推荐保留两个“自动选择”，由 Codex 使用兼容默认值。旧版本保存的无效模型名或推理强度会自动回退，不再导致聊天 400 错误。

另外两种方式：

- **API key**：使用 OpenAI 开发者 API，和 ChatGPT 订阅分开计费；可自行填写模型名。
- **离线**：完全不联网，只提供简单的陪伴式固定回复。

苏无度随附经过官方 Release SHA-256 校验的 OpenAI Codex 0.144.4 Windows 组件，不修改 PATH，也不要求用户安装命令行工具。第三方组件信息见 `THIRD-PARTY-NOTICES.txt`。

## 聊天记忆

开启设置中的“聊天记忆”后：

- 聊天窗口会恢复最近 20 条消息；
- 本地最多保留最近 100 条消息；
- 对苏无度说“请记住……”或“记住：……”会保存一条长期事实；
- 对她说“请忘记……”可删除匹配的长期事实；
- 设置中的“清除苏无度的聊天与记忆”会删除全部本地聊天记忆。

这些内容只保存在本机，不与 ChatGPT 网页版的 Memory 同步。关闭聊天记忆后，新消息不会写入本地历史。

## 和 Codex / 脚本联动

应用每秒检查一次本地命令文件。使用便携版附带的控制脚本：

```powershell
.\dist\DesktopPet\Scripts\PetControl.ps1 -State working -Message 'Codex 正在处理任务…'
.\dist\DesktopPet\Scripts\PetControl.ps1 -State success -Message '任务完成！'
.\dist\DesktopPet\Scripts\PetControl.ps1 -State question -Message '需要你的输入。'
.\dist\DesktopPet\Scripts\PetControl.ps1 -State error -Message '构建失败，请检查日志。'
```

可用状态：

```text
idle blink happy working question success error sleeping reminder waving heart
```

任何工具只要写入以下 JSON 也能控制桌宠：

```text
%LocalAppData%\PixelHeartDesktopPet\command.json
```

```json
{
  "state": "success",
  "message": "全部完成！"
}
```

## 从源码构建

要求：

- Windows 10/11
- Visual Studio 2022 Build Tools（包含 MSBuild 与 Roslyn C# 编译器）
- Windows 自带 .NET Framework 4.x

运行：

```powershell
.\build.ps1
```

项目不使用 NuGet 包。便携版包含官方 Codex 运行组件，用于 ChatGPT OAuth 与 app-server 通信。

## 本地数据

设置、加密 key、聊天记忆、命令文件和错误日志都位于：

```text
%LocalAppData%\PixelHeartDesktopPet
```

删除该文件夹即可重置桌宠。开机启动项位于当前用户的 Windows `Run` 注册表项，可在设置中随时关闭。

主要文件：

```text
settings.json       普通设置（聊天方式、模型、提醒、窗口位置等）
secret.dat          DPAPI 加密的 OpenAI API key
chat-memory.json    最近聊天和明确记住的内容
error.log           崩溃诊断日志
```

## 素材

- `v1image.png`：用户提供的角色原型。
- `Assets\sprite-sheet.png`：生成并透明化后的 4 × 3 Sprite sheet。
- `Assets\Sprites\*.png`：应用实际使用的 12 个独立帧。
