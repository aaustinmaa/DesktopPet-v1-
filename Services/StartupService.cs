using System;
using Microsoft.Win32;

namespace DesktopPet.Services
{
    public static class StartupService
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "PixelHeartDesktopPet";

        public static bool IsEnabled()
        {
            using (var key = Registry.CurrentUser.OpenSubKey(RunKey, false))
            {
                return key != null && key.GetValue(ValueName) != null;
            }
        }

        public static void SetEnabled(bool enabled)
        {
            using (var key = Registry.CurrentUser.OpenSubKey(RunKey, true))
            {
                if (key == null) return;
                if (enabled)
                {
                    var executable = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
                    key.SetValue(ValueName, "\"" + executable + "\" --startup");
                }
                else
                {
                    key.DeleteValue(ValueName, false);
                }
            }
        }
    }
}
