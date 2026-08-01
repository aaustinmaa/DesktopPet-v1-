using System;
using System.Runtime.InteropServices;

namespace DesktopPet.Services
{
    internal static class NativeMethods
    {
        public const int GwlExStyle = -20;
        public const int WsExTransparent = 0x00000020;
        public const int WsExToolWindow = 0x00000080;
        public const int WsExNoActivate = 0x08000000;
        public const int WmHotkey = 0x0312;
        public const int HotkeyId = 0xBEEF;
        public const uint ModAlt = 0x0001;
        public const uint ModControl = 0x0002;
        public const uint VkP = 0x50;
        public const uint WdaNone = 0x00000000;
        public const uint WdaExcludeFromCapture = 0x00000011;

        [StructLayout(LayoutKind.Sequential)]
        private struct LastInputInfo
        {
            public uint cbSize;
            public uint dwTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct RtlOsVersionInfo
        {
            public uint dwOSVersionInfoSize;
            public uint dwMajorVersion;
            public uint dwMinorVersion;
            public uint dwBuildNumber;
            public uint dwPlatformId;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szCSDVersion;
        }

        [DllImport("user32.dll")]
        private static extern bool GetLastInputInfo(ref LastInputInfo info);

        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr windowHandle, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr windowHandle, int id);

        [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
        public static extern int GetWindowLong(IntPtr handle, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
        public static extern int SetWindowLong(IntPtr handle, int index, int newStyle);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowDisplayAffinity(
            IntPtr windowHandle,
            uint affinity);

        [DllImport("dwmapi.dll")]
        private static extern int DwmFlush();

        [DllImport("ntdll.dll", CharSet = CharSet.Unicode)]
        private static extern int RtlGetVersion(
            ref RtlOsVersionInfo versionInfo);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        public static TimeSpan GetSystemIdleTime()
        {
            var info = new LastInputInfo { cbSize = (uint)Marshal.SizeOf(typeof(LastInputInfo)) };
            if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
            var elapsed = unchecked((uint)Environment.TickCount - info.dwTime);
            return TimeSpan.FromMilliseconds(elapsed);
        }

        public static bool SupportsExcludeFromCapture()
        {
            try
            {
                var version = new RtlOsVersionInfo
                {
                    dwOSVersionInfoSize =
                        (uint)Marshal.SizeOf(typeof(RtlOsVersionInfo))
                };
                if (RtlGetVersion(ref version) != 0)
                    return false;
                return version.dwMajorVersion > 10 ||
                    (version.dwMajorVersion == 10 &&
                     version.dwBuildNumber >= 19041);
            }
            catch
            {
                return false;
            }
        }

        public static void FlushDesktopComposition()
        {
            try
            {
                DwmFlush();
            }
            catch
            {
                // Capturing can still proceed if DWM synchronization fails.
            }
        }
    }
}
