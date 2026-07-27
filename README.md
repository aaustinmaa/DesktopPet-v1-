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
- 双击打开聊天窗口；没有 API key 时使用离线陪伴回复。
- 可选 OpenAI Responses API；API key 使用 Windows DPAPI 加密保存在当前用户目录。
- 可由 Codex、脚本或其它程序发送状态命令，实现“工作中 / 完成 / 出错 / 等待输入”等联动。

## 操作

- 单击并拖动：移动桌宠。
- 双击：打开聊天。
- 右键：打开完整菜单。
- `Ctrl + Alt + P`：恢复鼠标交互并叫回隐藏的桌宠。
- 双击托盘图标：叫醒桌宠。
- 再次双击启动程序：不会创建第二只桌宠，而是直接叫回并置前现有桌宠。

## 可选 AI

右键桌宠 → **设置**：

1. 填入 OpenAI API key。
2. 模型默认是 `gpt-5.6-sol`，也可以自行修改。
3. 保存后重新打开聊天窗口。

没有 key 时应用完全正常工作，并自动使用离线模式。API key 不会写进项目文件或普通 JSON 设置。

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

项目不使用 NuGet 包或其它第三方运行时依赖。

## 本地数据

设置、加密 key、命令文件和错误日志都位于：

```text
%LocalAppData%\PixelHeartDesktopPet
```

删除该文件夹即可重置桌宠。开机启动项位于当前用户的 Windows `Run` 注册表项，可在设置中随时关闭。

## 素材

- `v1image.png`：用户提供的角色原型。
- `Assets\sprite-sheet.png`：生成并透明化后的 4 × 3 Sprite sheet。
- `Assets\Sprites\*.png`：应用实际使用的 12 个独立帧。
