using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace DesktopPet.Services
{
    public static class ApplicationIntegrationService
    {
        private const string ShortcutFileName = "苏无度.lnk";

        public static string StartMenuShortcutPath =>
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
                "Programs",
                ShortcutFileName);

        public static string DesktopShortcutPath =>
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                ShortcutFileName);

        public static void EnsureStartMenuShortcut()
        {
            if (!File.Exists(StartMenuShortcutPath) || IsRunningFromInstalledLocation())
                CreateShortcut(StartMenuShortcutPath);
        }

        public static void CreateDesktopShortcut()
        {
            CreateShortcut(DesktopShortcutPath);
        }

        public static void CreateShortcut(string shortcutPath)
        {
            if (string.IsNullOrWhiteSpace(shortcutPath))
                throw new ArgumentException("快捷方式路径不能为空。", nameof(shortcutPath));

            var executablePath = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
            var directory = Path.GetDirectoryName(shortcutPath);
            if (!string.IsNullOrWhiteSpace(directory))
                Directory.CreateDirectory(directory);

            IShellLinkW shortcut = null;
            try
            {
                shortcut = (IShellLinkW)new ShellLink();
                ThrowIfFailed(shortcut.SetPath(executablePath));
                ThrowIfFailed(shortcut.SetArguments("--launcher"));
                ThrowIfFailed(shortcut.SetDescription("启动或叫醒苏无度桌宠"));
                ThrowIfFailed(shortcut.SetWorkingDirectory(Path.GetDirectoryName(executablePath)));
                ThrowIfFailed(shortcut.SetIconLocation(executablePath, 0));
                ((IPersistFile)shortcut).Save(shortcutPath, true);
            }
            finally
            {
                if (shortcut != null && Marshal.IsComObject(shortcut))
                    Marshal.FinalReleaseComObject(shortcut);
            }
        }

        private static bool IsRunningFromInstalledLocation()
        {
            var executablePath =
                System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
            var expectedDirectory = Path.GetFullPath(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs",
                "SuWuDuDesktopPet"));
            var actualDirectory = Path.GetFullPath(Path.GetDirectoryName(executablePath));
            return string.Equals(
                actualDirectory.TrimEnd(Path.DirectorySeparatorChar),
                expectedDirectory.TrimEnd(Path.DirectorySeparatorChar),
                StringComparison.OrdinalIgnoreCase);
        }

        private static void ThrowIfFailed(int result)
        {
            if (result < 0)
                Marshal.ThrowExceptionForHR(result);
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
