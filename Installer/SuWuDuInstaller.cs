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
            private readonly TextBox _installPath;
            private readonly Button _browseButton;
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
                var locationInput = new TableLayoutPanel
                {
                    ColumnCount = 2,
                    Dock = DockStyle.Fill,
                    Margin = new Padding(0),
                    RowCount = 1
                };
                locationInput.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
                locationInput.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96F));

                _installPath = new TextBox
                {
                    AutoCompleteMode = AutoCompleteMode.SuggestAppend,
                    AutoCompleteSource = AutoCompleteSource.FileSystemDirectories,
                    BorderStyle = BorderStyle.FixedSingle,
                    Dock = DockStyle.Fill,
                    Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point),
                    Margin = new Padding(0, 3, 10, 3),
                    Text = GetInitialInstallDirectory()
                };
                _browseButton = new Button
                {
                    BackColor = Color.White,
                    Cursor = Cursors.Hand,
                    Dock = DockStyle.Fill,
                    FlatStyle = FlatStyle.Flat,
                    ForeColor = Color.FromArgb(58, 67, 78),
                    Margin = new Padding(0, 1, 0, 1),
                    Text = "浏览…",
                    UseCompatibleTextRendering = false
                };
                _browseButton.FlatAppearance.BorderColor = Color.FromArgb(198, 205, 214);
                _browseButton.FlatAppearance.BorderSize = 1;
                _browseButton.Click += BrowseButton_Click;
                locationInput.Controls.Add(_installPath, 0, 0);
                locationInput.Controls.Add(_browseButton, 1, 0);
                locationCard.Controls.Add(locationCaption, 0, 0);
                locationCard.Controls.Add(locationInput, 0, 1);

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

            private void BrowseButton_Click(object sender, EventArgs e)
            {
                try
                {
                    string selectedPath = FindExistingDirectory(_installPath.Text);
                    string result = ShowModernFolderPicker(this, selectedPath);
                    if (!string.IsNullOrWhiteSpace(result))
                    {
                        _installPath.Text = result;
                        _installPath.SelectionStart = _installPath.TextLength;
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show("无法打开文件夹选择窗口：\r\n" + ex.Message,
                        "选择安装位置", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }

            private void InstallButton_Click(object sender, EventArgs e)
            {
                try
                {
                    ToggleControls(false);
                    _status.Text = "正在准备安装…";
                    _status.Refresh();
                    Install(_installPath.Text, _desktopShortcut.Checked);
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
                _installPath.Enabled = enabled;
                _browseButton.Enabled = enabled;
                UseWaitCursor = !enabled;
            }
        }

        private static string DefaultInstallDirectory
        {
            get
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", ProductKey);
            }
        }

        private static string GetInitialInstallDirectory()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ProductKey))
                {
                    string registeredPath = key == null ? null : key.GetValue("InstallLocation") as string;
                    if (!string.IsNullOrWhiteSpace(registeredPath) && Path.IsPathRooted(registeredPath))
                        return Path.GetFullPath(registeredPath);
                }
            }
            catch
            {
            }

            return DefaultInstallDirectory;
        }

        private static string FindExistingDirectory(string candidate)
        {
            try
            {
                string current = Environment.ExpandEnvironmentVariables(
                    (candidate ?? string.Empty).Trim().Trim('"'));
                if (string.IsNullOrWhiteSpace(current) || !Path.IsPathRooted(current))
                    return Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

                current = Path.GetFullPath(current);
                while (!string.IsNullOrWhiteSpace(current) && !Directory.Exists(current))
                {
                    string parent = Path.GetDirectoryName(current);
                    if (string.Equals(parent, current, StringComparison.OrdinalIgnoreCase)) break;
                    current = parent;
                }
                return current;
            }
            catch
            {
                return Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            }
        }

        private static string ShowModernFolderPicker(IWin32Window owner, string initialDirectory)
        {
            const uint FosNoChangeDirectory = 0x00000008;
            const uint FosPickFolders = 0x00000020;
            const uint FosForceFileSystem = 0x00000040;
            const uint FosPathMustExist = 0x00000800;
            const uint SigdnFileSystemPath = 0x80058000;
            const int HResultCancelled = unchecked((int)0x800704C7);

            IFileDialog dialog = null;
            IShellItem initialItem = null;
            IShellItem selectedItem = null;
            IntPtr selectedPathPointer = IntPtr.Zero;
            try
            {
                dialog = (IFileDialog)new FileOpenDialog();
                uint options;
                ThrowIfFailed(dialog.GetOptions(out options));
                ThrowIfFailed(dialog.SetOptions(options | FosNoChangeDirectory |
                    FosPickFolders | FosForceFileSystem | FosPathMustExist));
                ThrowIfFailed(dialog.SetTitle("选择苏无度的安装文件夹"));
                ThrowIfFailed(dialog.SetOkButtonLabel("选择此文件夹"));

                if (!string.IsNullOrWhiteSpace(initialDirectory) && Directory.Exists(initialDirectory))
                {
                    Guid shellItemId = typeof(IShellItem).GUID;
                    if (SHCreateItemFromParsingName(initialDirectory, IntPtr.Zero,
                            ref shellItemId, out initialItem) >= 0)
                    {
                        ThrowIfFailed(dialog.SetFolder(initialItem));
                    }
                }

                int result = dialog.Show(owner == null ? IntPtr.Zero : owner.Handle);
                if (result == HResultCancelled) return null;
                ThrowIfFailed(result);
                ThrowIfFailed(dialog.GetResult(out selectedItem));
                ThrowIfFailed(selectedItem.GetDisplayName(SigdnFileSystemPath,
                    out selectedPathPointer));
                return Marshal.PtrToStringUni(selectedPathPointer);
            }
            finally
            {
                if (selectedPathPointer != IntPtr.Zero)
                    Marshal.FreeCoTaskMem(selectedPathPointer);
                if (selectedItem != null && Marshal.IsComObject(selectedItem))
                    Marshal.FinalReleaseComObject(selectedItem);
                if (initialItem != null && Marshal.IsComObject(initialItem))
                    Marshal.FinalReleaseComObject(initialItem);
                if (dialog != null && Marshal.IsComObject(dialog))
                    Marshal.FinalReleaseComObject(dialog);
            }
        }

        private static void Install(string requestedDirectory, bool createDesktopShortcut)
        {
            string installDirectory = GetValidatedInstallDirectory(requestedDirectory);
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

        private static string GetValidatedInstallDirectory(string candidate)
        {
            if (string.IsNullOrWhiteSpace(candidate))
                throw new InvalidOperationException("请选择安装位置。");

            string expanded = Environment.ExpandEnvironmentVariables(candidate.Trim().Trim('"'));
            if (!Path.IsPathRooted(expanded))
                throw new InvalidOperationException("请输入完整的安装路径，例如 D:\\Apps\\SuWuDu。");

            string destination = Path.GetFullPath(expanded);
            string root = Path.GetPathRoot(destination);
            if (string.Equals(destination.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                    (root ?? string.Empty).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                    StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("不能直接安装到磁盘根目录，请选择一个专用文件夹。");

            destination = destination.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (File.Exists(destination))
                throw new InvalidOperationException("所选安装位置是一个文件，请选择文件夹。");

            if (Directory.Exists(destination) && DirectoryHasEntries(destination) &&
                !IsRecognizedInstallation(destination))
            {
                throw new InvalidOperationException(
                    "所选文件夹不是空文件夹，也不是已有的苏无度安装目录。请新建或选择一个专用文件夹。");
            }
            return destination;
        }

        private static bool DirectoryHasEntries(string directory)
        {
            using (var entries = Directory.EnumerateFileSystemEntries(directory).GetEnumerator())
                return entries.MoveNext();
        }

        private static bool IsRecognizedInstallation(string directory)
        {
            return File.Exists(Path.Combine(directory, AppFileName)) &&
                   File.Exists(Path.Combine(directory, "Uninstall.exe"));
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
            string previous = installDirectory + ".previous-" + Guid.NewGuid().ToString("N");
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

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string path,
            IntPtr bindingContext,
            ref Guid shellItemId,
            [MarshalAs(UnmanagedType.Interface)] out IShellItem shellItem);

        [ComImport]
        [Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
        private class FileOpenDialog
        {
        }

        [ComImport]
        [Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog
        {
            [PreserveSig]
            int Show(IntPtr parent);
            [PreserveSig]
            int SetFileTypes(uint count, IntPtr filterSpecifications);
            [PreserveSig]
            int SetFileTypeIndex(uint index);
            [PreserveSig]
            int GetFileTypeIndex(out uint index);
            [PreserveSig]
            int Advise(IntPtr events, out uint cookie);
            [PreserveSig]
            int Unadvise(uint cookie);
            [PreserveSig]
            int SetOptions(uint options);
            [PreserveSig]
            int GetOptions(out uint options);
            [PreserveSig]
            int SetDefaultFolder(IShellItem shellItem);
            [PreserveSig]
            int SetFolder(IShellItem shellItem);
            [PreserveSig]
            int GetFolder(out IShellItem shellItem);
            [PreserveSig]
            int GetCurrentSelection(out IShellItem shellItem);
            [PreserveSig]
            int SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
            [PreserveSig]
            int GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name);
            [PreserveSig]
            int SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
            [PreserveSig]
            int SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
            [PreserveSig]
            int SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
            [PreserveSig]
            int GetResult(out IShellItem shellItem);
            [PreserveSig]
            int AddPlace(IShellItem shellItem, uint alignment);
            [PreserveSig]
            int SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension);
            [PreserveSig]
            int Close(int result);
            [PreserveSig]
            int SetClientGuid(ref Guid clientGuid);
            [PreserveSig]
            int ClearClientData();
            [PreserveSig]
            int SetFilter(IntPtr filter);
        }

        [ComImport]
        [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem
        {
            [PreserveSig]
            int BindToHandler(IntPtr bindingContext, ref Guid bindingHandler,
                ref Guid interfaceId, out IntPtr result);
            [PreserveSig]
            int GetParent(out IShellItem parent);
            [PreserveSig]
            int GetDisplayName(uint displayNameType, out IntPtr name);
            [PreserveSig]
            int GetAttributes(uint attributeMask, out uint attributes);
            [PreserveSig]
            int Compare(IShellItem other, uint hint, out int order);
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
