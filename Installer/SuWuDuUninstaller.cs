using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SuWuDu.Setup
{
    internal static class SuWuDuUninstaller
    {
        private const string ProductName = "苏无度";
        private const string ProductKey = "SuWuDuDesktopPet";
        private const string CleanupArgument = "--cleanup";

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (args.Length == 2 &&
                string.Equals(args[0], CleanupArgument, StringComparison.OrdinalIgnoreCase))
            {
                RunCleanupHelper(args[1]);
                return;
            }

            string installDirectory;
            try { installDirectory = GetValidatedInstallDirectory(); }
            catch (Exception ex)
            {
                MessageBox.Show("无法确认安装目录：\r\n" + ex.Message,
                    "卸载苏无度", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            DialogResult result = MessageBox.Show(
                "确定要卸载苏无度桌宠吗？\r\n\r\n桌宠的个人设置会保留，以便日后重新安装。",
                "卸载苏无度",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);
            if (result != DialogResult.Yes) return;

            if (IsPetRunning())
            {
                MessageBox.Show("请先在系统托盘中右键苏无度并选择“退出”，然后再卸载。",
                    "卸载苏无度", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            try
            {
                LaunchCleanupHelper(installDirectory);
            }
            catch (Exception ex)
            {
                MessageBox.Show("卸载没有开始：\r\n" + ex.Message,
                    "卸载苏无度", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static string GetValidatedInstallDirectory()
        {
            string actual = Path.GetFullPath(
                Path.GetDirectoryName(Application.ExecutablePath));
            return ValidateInstallDirectory(actual);
        }

        private static string ValidateInstallDirectory(string candidate)
        {
            if (string.IsNullOrWhiteSpace(candidate) || !Path.IsPathRooted(candidate))
                throw new InvalidOperationException("卸载目录无效。");

            string actual = Path.GetFullPath(candidate ?? string.Empty);
            string root = Path.GetPathRoot(actual);
            if (string.Equals(actual.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                    (root ?? string.Empty).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                    StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("卸载目录不能是磁盘根目录。");

            actual = actual.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string registered = GetRegisteredInstallDirectory();
            if (string.IsNullOrWhiteSpace(registered) ||
                !string.Equals(actual, registered, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("卸载目录与苏无度的安装记录不一致。");

            if (!File.Exists(Path.Combine(actual, "SuWuDu.exe")) ||
                !File.Exists(Path.Combine(actual, "Uninstall.exe")))
                throw new InvalidOperationException("所选目录中没有找到完整的苏无度安装文件。");
            return actual;
        }

        private static string GetRegisteredInstallDirectory()
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ProductKey))
            {
                string value = key == null ? null : key.GetValue("InstallLocation") as string;
                if (string.IsNullOrWhiteSpace(value) || !Path.IsPathRooted(value)) return null;
                return Path.GetFullPath(value).TrimEnd(
                    Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            }
        }

        private static bool IsPetRunning()
        {
            return Process.GetProcessesByName("SuWuDu").Length > 0 ||
                   Process.GetProcessesByName("DesktopPet").Length > 0;
        }

        private static void LaunchCleanupHelper(string installDirectory)
        {
            string helperPath = Path.Combine(
                Path.GetTempPath(),
                "SuWuDu-Uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
            File.Copy(Application.ExecutablePath, helperPath, false);
            Process.Start(new ProcessStartInfo(
                helperPath,
                CleanupArgument + " " + QuoteArgument(installDirectory))
            {
                UseShellExecute = true
            });
        }

        private static void RunCleanupHelper(string installDirectoryArgument)
        {
            string installDirectory;
            try
            {
                installDirectory = ValidateInstallDirectory(installDirectoryArgument);
                DeleteInstallationWithRetries(installDirectory);
                DeleteShortcutsOwnedByApp(installDirectory);
                DeleteStartupEntriesOwnedByApp(installDirectory);
                Registry.CurrentUser.DeleteSubKeyTree(
                    @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ProductKey,
                    false);
                MessageBox.Show(
                    "苏无度已卸载。开始菜单和桌面快捷方式也已移除。",
                    "卸载完成",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "卸载没有完成，原有应用入口已保留：\r\n" + ex.Message,
                    "卸载苏无度",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                ScheduleHelperSelfDelete();
            }
        }

        private static void DeleteInstallationWithRetries(string installDirectory)
        {
            Exception lastError = null;
            for (int attempt = 0; attempt < 12; attempt++)
            {
                try
                {
                    if (Directory.Exists(installDirectory))
                        Directory.Delete(installDirectory, true);
                    if (!Directory.Exists(installDirectory))
                        return;
                }
                catch (Exception ex)
                {
                    lastError = ex;
                }
                Thread.Sleep(350);
            }

            throw new IOException(
                "无法删除应用目录。请关闭仍在使用苏无度文件的程序后重试。",
                lastError);
        }

        private static void DeleteShortcutsOwnedByApp(string installDirectory)
        {
            DeleteShortcutIfOwned(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
                "Programs",
                ProductName + ".lnk"), installDirectory);
            DeleteShortcutIfOwned(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                ProductName + ".lnk"), installDirectory);
        }

        private static void DeleteShortcutIfOwned(string path, string installDirectory)
        {
            if (!File.Exists(path)) return;
            string expectedTarget = Path.GetFullPath(
                Path.Combine(installDirectory, "SuWuDu.exe"));
            string actualTarget = TryReadShortcutTarget(path);
            if (!string.IsNullOrWhiteSpace(actualTarget) &&
                string.Equals(Path.GetFullPath(actualTarget), expectedTarget,
                    StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(path);
            }
        }

        private static string TryReadShortcutTarget(string shortcutPath)
        {
            IShellLinkW shortcut = null;
            try
            {
                shortcut = (IShellLinkW)new ShellLink();
                ((IPersistFile)shortcut).Load(shortcutPath, 0);
                var target = new StringBuilder(32768);
                int result = shortcut.GetPath(target, target.Capacity, IntPtr.Zero, 0);
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                return target.ToString();
            }
            catch
            {
                return null;
            }
            finally
            {
                if (shortcut != null && Marshal.IsComObject(shortcut))
                    Marshal.FinalReleaseComObject(shortcut);
            }
        }

        private static void DeleteStartupEntriesOwnedByApp(string installDirectory)
        {
            string expectedExecutable = Path.GetFullPath(
                Path.Combine(installDirectory, "SuWuDu.exe"));
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run", true))
            {
                if (key == null) return;
                DeleteStartupValueIfOwned(key, "SuWuDuDesktopPet", expectedExecutable);
                DeleteStartupValueIfOwned(key, "PixelHeartDesktopPet", expectedExecutable);
            }
        }

        private static void DeleteStartupValueIfOwned(
            RegistryKey key,
            string valueName,
            string expectedExecutable)
        {
            string value = key.GetValue(valueName) as string;
            if (!string.IsNullOrWhiteSpace(value) &&
                value.IndexOf(expectedExecutable, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                key.DeleteValue(valueName, false);
            }
        }

        private static void ScheduleHelperSelfDelete()
        {
            string helperPath = Application.ExecutablePath.Replace("\"", string.Empty);
            Process.Start(new ProcessStartInfo(
                "cmd.exe",
                "/d /q /c ping 127.0.0.1 -n 3 > nul & del /f /q " +
                QuoteArgument(helperPath))
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                WindowStyle = ProcessWindowStyle.Hidden
            });
        }

        private static string QuoteArgument(string value)
        {
            return "\"" + (value ?? string.Empty).Replace("\"", string.Empty) + "\"";
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
