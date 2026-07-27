using System;
using System.Runtime.InteropServices;

namespace DesktopPet.Services
{
    internal static class NativeMethods
    {
        public const int GwlExStyle = -20;
        public const int WsExTransparent = 0x00000020;
        public const int WmHotkey = 0x0312;
        public const int HotkeyId = 0xBEEF;
        public const uint ModAlt = 0x0001;
        public const uint ModControl = 0x0002;
        public const uint VkP = 0x50;

        [StructLayout(LayoutKind.Sequential)]
        private struct LastInputInfo
        {
            public uint cbSize;
            public uint dwTime;
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

        public static TimeSpan GetSystemIdleTime()
        {
            var info = new LastInputInfo { cbSize = (uint)Marshal.SizeOf(typeof(LastInputInfo)) };
            if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
            var elapsed = unchecked((uint)Environment.TickCount - info.dwTime);
            return TimeSpan.FromMilliseconds(elapsed);
        }
    }
}
