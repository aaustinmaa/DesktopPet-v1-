using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SuWuDu.Setup
{
    internal static class SuWuDuInstaller
    {
        private const string ProductName = "苏无度";
        private const string ProductKey = "SuWuDuDesktopPet";
        private const string AppFileName = "SuWuDu.exe";
        private static readonly byte[] FooterMagic = Encoding.ASCII.GetBytes("SWDPACK1");

        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }

        private sealed class InstallerForm : Form
        {
            private readonly CheckBox _desktopShortcut;
            private readonly Button _installButton;
            private readonly Button _cancelButton;
            private readonly Label _status;

            public InstallerForm()
            {
                Text = "安装 " + SuWuDuInstaller.ProductName;
                FormBorderStyle = FormBorderStyle.FixedDialog;
                MaximizeBox = false;
                MinimizeBox = false;
                StartPosition = FormStartPosition.CenterScreen;
                AutoScaleMode = AutoScaleMode.Dpi;
                ClientSize = new Size(680, 430);
                MinimumSize = new Size(696, 469);
                BackColor = Color.FromArgb(246, 248, 251);
                Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);
                Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

                var accent = new Panel
                {
                    BackColor = Color.FromArgb(25, 130, 102),
                    Dock = DockStyle.Top,
                    Height = 6
                };

                var layout = new TableLayoutPanel
                {
                    BackColor = BackColor,
                    ColumnCount = 1,
                    Dock = DockStyle.Fill,
                    Padding = new Padding(38, 28, 38, 24),
                    RowCount = 5
                };
                layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 84F));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 64F));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 86F));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 52F));
                layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

                var header = new TableLayoutPanel
                {
                    ColumnCount = 2,
                    Dock = DockStyle.Fill,
                    Margin = new Padding(0)
                };
                header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 72F));
                header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));

                var iconImage = new PictureBox
                {
                    Dock = DockStyle.Fill,
                    Image = Icon.ToBitmap(),
                    Margin = new Padding(0, 2, 18, 14),
                    SizeMode = PictureBoxSizeMode.Zoom
                };

                var heading = new TableLayoutPanel
                {
                    ColumnCount = 1,
                    Dock = DockStyle.Fill,
                    Margin = new Padding(0)
                };
                heading.RowStyles.Add(new RowStyle(SizeType.Absolute, 43F));
                heading.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
                var title = new Label
                {
                    AutoEllipsis = true,
                    Dock = DockStyle.Fill,
                    Font = new Font("Segoe UI Semibold", 20F, FontStyle.Regular, GraphicsUnit.Point),
                    ForeColor = Color.FromArgb(28, 35, 43),
                    Margin = new Padding(0),
                    Text = "安装苏无度",
                    TextAlign = ContentAlignment.MiddleLeft,
                    UseCompatibleTextRendering = false
                };
                var subtitle = new Label
                {
                    Dock = DockStyle.Fill,
                    ForeColor = Color.FromArgb(94, 103, 114),
                    Margin = new Padding(1, 0, 0, 0),
                    Text = "把你的像素桌宠带到 Windows 桌面",
                    TextAlign = ContentAlignment.TopLeft,
                    UseCompatibleTextRendering = false
                };
                heading.Controls.Add(title, 0, 0);
                heading.Controls.Add(subtitle, 0, 1);
                header.Controls.Add(iconImage, 0, 0);
                header.Controls.Add(heading, 1, 0);

                var description = new Label
                {
                    Dock = DockStyle.Fill,
                    ForeColor = Color.FromArgb(58, 67, 78),
                    Margin = new Padding(1, 0, 0, 0),
                    Text = "安装完成后，可以从 Windows 开始菜单搜索“苏无度”，也可以固定到任务栏。\r\n仅为当前用户安装，不需要管理员权限。",
                    TextAlign = ContentAlignment.MiddleLeft,
                    UseCompatibleTextRendering = false
                };

                var locationCard = new TableLayoutPanel
                {
                    BackColor = Color.White,
                    CellBorderStyle = TableLayoutPanelCellBorderStyle.Single,
                    ColumnCount = 1,
                    Dock = DockStyle.Fill,
                    Margin = new Padding(0, 4, 0, 8),
                    Padding = new Padding(16, 8, 16, 8),
                    RowCount = 2
                };
                locationCard.RowStyles.Add(new RowStyle(SizeType.Absolute, 24F));
                locationCard.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
                var locationCaption = new Label
                {
                    Dock = DockStyle.Fill,
                    Font = new Font("Segoe UI Semibold", 9F, FontStyle.Regular, GraphicsUnit.Point),
                    ForeColor = Color.FromArgb(94, 103, 114),
                    Margin = new Padding(0),
                    Text = "安装位置",
                    TextAlign = ContentAlignment.MiddleLeft,
                    UseCompatibleTextRendering = false
                };
                var locationValue = new Label
                {
                    AutoEllipsis = true,
                    Dock = DockStyle.Fill,
                    ForeColor = Color.FromArgb(28, 35, 43),
                    Margin = new Padding(0),
                    Text = InstallDirectory,
                    TextAlign = ContentAlignment.MiddleLeft,
                    UseCompatibleTextRendering = false
                };
                locationCard.Controls.Add(locationCaption, 0, 0);
                locationCard.Controls.Add(locationValue, 0, 1);

                _desktopShortcut = new CheckBox
                {
                    Text = "创建桌面快捷方式",
                    Checked = true,
                    Dock = DockStyle.Fill,
                    FlatStyle = FlatStyle.System,
                    Margin = new Padding(1, 4, 0, 0),
                    UseCompatibleTextRendering = false
                };

                var footer = new TableLayoutPanel
                {
                    ColumnCount = 2,
                    Dock = DockStyle.Fill,
                    Margin = new Padding(0)
                };
                footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
                footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 244F));

                _status = new Label
                {
                    Dock = DockStyle.Fill,
                    ForeColor = Color.FromArgb(94, 103, 114),
                    Margin = new Padding(1, 0, 12, 0),
                    Text = "准备就绪",
                    TextAlign = ContentAlignment.MiddleLeft,
                    UseCompatibleTextRendering = false
                };

                var buttons = new FlowLayoutPanel
                {
                    Dock = DockStyle.Fill,
                    FlowDirection = FlowDirection.RightToLeft,
                    Margin = new Padding(0),
                    Padding = new Padding(0, 10, 0, 0),
                    WrapContents = false
                };
                _installButton = new Button
                {
                    BackColor = Color.FromArgb(25, 130, 102),
                    Cursor = Cursors.Hand,
                    DialogResult = DialogResult.None,
                    FlatStyle = FlatStyle.Flat,
                    Font = new Font("Segoe UI Semibold", 10F, FontStyle.Regular, GraphicsUnit.Point),
                    ForeColor = Color.White,
                    Height = 40,
                    Margin = new Padding(10, 0, 0, 0),
                    Text = "安装",
                    UseCompatibleTextRendering = false,
                    Width = 112
                };
                _installButton.FlatAppearance.BorderSize = 0;
                _cancelButton = new Button
                {
                    BackColor = Color.White,
                    Cursor = Cursors.Hand,
                    DialogResult = DialogResult.Cancel,
                    FlatStyle = FlatStyle.Flat,
                    ForeColor = Color.FromArgb(58, 67, 78),
                    Height = 40,
                    Margin = new Padding(0),
                    Text = "取消",
                    UseCompatibleTextRendering = false,
                    Width = 112
                };
                _cancelButton.FlatAppearance.BorderColor = Color.FromArgb(198, 205, 214);
                _cancelButton.FlatAppearance.BorderSize = 1;

                _installButton.Click += InstallButton_Click;
                _cancelButton.Click += delegate { Close(); };
                AcceptButton = _installButton;
                CancelButton = _cancelButton;
                buttons.Controls.Add(_installButton);
                buttons.Controls.Add(_cancelButton);
                footer.Controls.Add(_status, 0, 0);
                footer.Controls.Add(buttons, 1, 0);

                layout.Controls.Add(header, 0, 0);
                layout.Controls.Add(description, 0, 1);
                layout.Controls.Add(locationCard, 0, 2);
                layout.Controls.Add(_desktopShortcut, 0, 3);
                layout.Controls.Add(footer, 0, 4);
                Controls.Add(layout);
                Controls.Add(accent);
            }

            private void InstallButton_Click(object sender, EventArgs e)
            {
                try
                {
                    ToggleControls(false);
                    _status.Text = "正在准备安装…";
                    _status.Refresh();
                    Install(_desktopShortcut.Checked);
                    MessageBox.Show("苏无度已经安装好了。\r\n\r\n以后请在开始菜单搜索“苏无度”，右键即可固定到任务栏。",
                        "安装完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    Close();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("安装没有完成：\r\n" + ex.Message, "安装苏无度", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    ToggleControls(true);
                    _status.Text = "请处理问题后再试一次。";
                }
            }

            private void ToggleControls(bool enabled)
            {
                _installButton.Enabled = enabled;
                _cancelButton.Enabled = enabled;
                _desktopShortcut.Enabled = enabled;
                UseWaitCursor = !enabled;
            }
        }

        private static string InstallDirectory
        {
            get
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", ProductKey);
            }
        }

        private static void Install(bool createDesktopShortcut)
        {
            string installDirectory = GetValidatedInstallDirectory();
            EnsurePetIsClosed();

            string installParent = Path.GetDirectoryName(installDirectory);
            Directory.CreateDirectory(installParent);
            string tempRoot = Path.Combine(
                installParent,
                ".SuWuDuSetup-" + Guid.NewGuid().ToString("N"));
            string zipPath = Path.Combine(tempRoot, "payload.zip");
            string extractedDirectory = Path.Combine(tempRoot, "app");
            try
            {
                Directory.CreateDirectory(tempRoot);
                ExtractPayload(zipPath);
                ExtractZipSafely(zipPath, extractedDirectory);
                ValidateAppPayload(extractedDirectory);

                ReplaceInstallation(extractedDirectory, installDirectory);
                CreateShortcuts(installDirectory, createDesktopShortcut);
                WriteUninstallRegistration(installDirectory);
                Process.Start(new ProcessStartInfo(Path.Combine(installDirectory, AppFileName), "--launcher") { UseShellExecute = true });
            }
            finally
            {
                TryDeleteDirectory(tempRoot);
            }
        }

        private static void EnsurePetIsClosed()
        {
            foreach (string processName in new[] { "SuWuDu", "DesktopPet" })
            {
                if (Process.GetProcessesByName(processName).Length > 0)
                    throw new InvalidOperationException("请先从系统托盘右键退出正在运行的苏无度，然后重新运行安装程序。");
            }
        }

        private static string GetValidatedInstallDirectory()
        {
            string programsRoot = Path.GetFullPath(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs"));
            string destination = Path.GetFullPath(InstallDirectory);
            string expected = Path.Combine(programsRoot, ProductKey);
            if (!string.Equals(destination, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("安装路径校验失败。");
            return destination;
        }

        private static void ExtractPayload(string destinationZip)
        {
            string installerPath = Application.ExecutablePath;
            using (FileStream source = new FileStream(installerPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                if (source.Length < FooterMagic.Length + sizeof(long))
                    throw new InvalidDataException("安装程序中没有找到应用文件。");

                source.Seek(-(FooterMagic.Length + sizeof(long)), SeekOrigin.End);
                byte[] magic = new byte[FooterMagic.Length];
                ReadExactly(source, magic, 0, magic.Length);
                if (!ByteArraysEqual(magic, FooterMagic))
                    throw new InvalidDataException("安装程序的数据校验失败。");

                byte[] sizeBytes = new byte[sizeof(long)];
                ReadExactly(source, sizeBytes, 0, sizeBytes.Length);
                long payloadLength = BitConverter.ToInt64(sizeBytes, 0);
                long payloadStart = source.Length - FooterMagic.Length - sizeof(long) - payloadLength;
                if (payloadLength <= 0 || payloadStart < 0)
                    throw new InvalidDataException("安装程序的数据长度无效。");

                source.Seek(payloadStart, SeekOrigin.Begin);
                using (FileStream destination = new FileStream(destinationZip, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    CopyExactly(source, destination, payloadLength);
                }
            }
        }

        private static void ExtractZipSafely(string zipPath, string destinationDirectory)
        {
            string root = Path.GetFullPath(destinationDirectory);
            string rootWithSeparator = root.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal)
                ? root : root + Path.DirectorySeparatorChar;
            Directory.CreateDirectory(root);
            using (ZipArchive archive = ZipFile.OpenRead(zipPath))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    if (string.IsNullOrWhiteSpace(entry.FullName)) continue;
                    string destinationPath = Path.GetFullPath(Path.Combine(root, entry.FullName));
                    if (!destinationPath.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(destinationPath, root, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("安装包包含不安全的文件路径。");

                    if (entry.FullName.EndsWith("/", StringComparison.Ordinal) || entry.FullName.EndsWith("\\", StringComparison.Ordinal))
                    {
                        Directory.CreateDirectory(destinationPath);
                        continue;
                    }

                    string parent = Path.GetDirectoryName(destinationPath);
                    if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(destinationPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    {
                        input.CopyTo(output);
                    }
                }
            }
        }

        private static void ValidateAppPayload(string extractedDirectory)
        {
            string appPath = Path.Combine(extractedDirectory, AppFileName);
            string uninstallerPath = Path.Combine(extractedDirectory, "Uninstall.exe");
            if (!File.Exists(appPath) || !File.Exists(uninstallerPath))
                throw new InvalidDataException("安装包不完整，缺少苏无度的程序文件。");
        }

        private static void ReplaceInstallation(string extractedDirectory, string installDirectory)
        {
            string previous = installDirectory + ".previous";
            if (Directory.Exists(previous)) TryDeleteDirectory(previous);
            if (Directory.Exists(installDirectory)) Directory.Move(installDirectory, previous);
            try
            {
                Directory.Move(extractedDirectory, installDirectory);
                if (Directory.Exists(previous)) TryDeleteDirectory(previous);
            }
            catch
            {
                if (!Directory.Exists(installDirectory) && Directory.Exists(previous)) Directory.Move(previous, installDirectory);
                throw;
            }
        }

        private static void CreateShortcuts(string installDirectory, bool createDesktopShortcut)
        {
            string target = Path.Combine(installDirectory, AppFileName);
            string startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs");
            CreateShortcut(Path.Combine(startMenu, ProductName + ".lnk"), target, "启动苏无度桌宠");

            string desktopShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), ProductName + ".lnk");
            if (createDesktopShortcut)
                CreateShortcut(desktopShortcut, target, "启动苏无度桌宠");
            else if (File.Exists(desktopShortcut))
                File.Delete(desktopShortcut);
        }

        private static void CreateShortcut(string shortcutPath, string targetPath, string description)
        {
            string folder = Path.GetDirectoryName(shortcutPath);
            if (!string.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
            IShellLinkW shortcut = null;
            try
            {
                shortcut = (IShellLinkW)new ShellLink();
                ThrowIfFailed(shortcut.SetPath(targetPath));
                ThrowIfFailed(shortcut.SetArguments("--launcher"));
                ThrowIfFailed(shortcut.SetWorkingDirectory(Path.GetDirectoryName(targetPath)));
                ThrowIfFailed(shortcut.SetDescription(description));
                string icon = Path.Combine(Path.GetDirectoryName(targetPath), "Assets", "app.ico");
                ThrowIfFailed(shortcut.SetIconLocation(
                    File.Exists(icon) ? icon : targetPath, 0));
                ((IPersistFile)shortcut).Save(shortcutPath, true);
            }
            finally
            {
                if (shortcut != null && Marshal.IsComObject(shortcut))
                    Marshal.FinalReleaseComObject(shortcut);
            }
        }

        private static void ThrowIfFailed(int result)
        {
            if (result < 0) Marshal.ThrowExceptionForHR(result);
        }

        private static void WriteUninstallRegistration(string installDirectory)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ProductKey))
            {
                key.SetValue("DisplayName", ProductName + " 桌宠");
                key.SetValue("DisplayVersion", "1.2.0");
                key.SetValue("Publisher", ProductName);
                key.SetValue("InstallLocation", installDirectory);
                key.SetValue("DisplayIcon", Path.Combine(installDirectory, AppFileName));
                key.SetValue("UninstallString", "\"" + Path.Combine(installDirectory, "Uninstall.exe") + "\"");
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
        }

        private static void ReadExactly(Stream stream, byte[] buffer, int offset, int count)
        {
            while (count > 0)
            {
                int read = stream.Read(buffer, offset, count);
                if (read == 0) throw new EndOfStreamException();
                offset += read;
                count -= read;
            }
        }

        private static void CopyExactly(Stream input, Stream output, long count)
        {
            byte[] buffer = new byte[81920];
            while (count > 0)
            {
                int wanted = (int)Math.Min(buffer.Length, count);
                int read = input.Read(buffer, 0, wanted);
                if (read == 0) throw new EndOfStreamException();
                output.Write(buffer, 0, read);
                count -= read;
            }
        }

        private static bool ByteArraysEqual(byte[] left, byte[] right)
        {
            if (left.Length != right.Length) return false;
            for (int i = 0; i < left.Length; i++) if (left[i] != right[i]) return false;
            return true;
        }

        private static void TryDeleteDirectory(string path)
        {
            if (Directory.Exists(path)) Directory.Delete(path, true);
        }

        [ComImport]
        [Guid("00021401-0000-0000-C000-000000000046")]
        private class ShellLink
        {
        }

        [ComImport]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        [Guid("000214F9-0000-0000-C000-000000000046")]
        private interface IShellLinkW
        {
            [PreserveSig]
            int GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder filePath,
                int maxPath, IntPtr findData, uint flags);
            [PreserveSig]
            int GetIDList(out IntPtr pidl);
            [PreserveSig]
            int SetIDList(IntPtr pidl);
            [PreserveSig]
            int GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name,
                int maxName);
            [PreserveSig]
            int SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
            [PreserveSig]
            int GetWorkingDirectory(
                [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder directory, int maxPath);
            [PreserveSig]
            int SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string directory);
            [PreserveSig]
            int GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder arguments,
                int maxPath);
            [PreserveSig]
            int SetArguments([MarshalAs(UnmanagedType.LPWStr)] string arguments);
            [PreserveSig]
            int GetHotkey(out short hotkey);
            [PreserveSig]
            int SetHotkey(short hotkey);
            [PreserveSig]
            int GetShowCmd(out int showCommand);
            [PreserveSig]
            int SetShowCmd(int showCommand);
            [PreserveSig]
            int GetIconLocation(
                [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder iconPath,
                int iconPathLength,
                out int iconIndex);
            [PreserveSig]
            int SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string iconPath, int iconIndex);
            [PreserveSig]
            int SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
            [PreserveSig]
            int Resolve(IntPtr hwnd, uint flags);
            [PreserveSig]
            int SetPath([MarshalAs(UnmanagedType.LPWStr)] string filePath);
        }

        [ComImport]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        [Guid("0000010B-0000-0000-C000-000000000046")]
        private interface IPersistFile
        {
            void GetClassID(out Guid classId);
            [PreserveSig]
            int IsDirty();
            void Load([MarshalAs(UnmanagedType.LPWStr)] string fileName, uint mode);
            void Save(
                [MarshalAs(UnmanagedType.LPWStr)] string fileName,
                [MarshalAs(UnmanagedType.Bool)] bool remember);
            void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string fileName);
            void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string fileName);
        }
    }
}
