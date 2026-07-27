using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace DesktopPet.Services
{
    public class SecretService
    {
        private readonly string _secretPath = Path.Combine(SettingsService.DataDirectory, "secret.dat");
        private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("PixelHeartDesktopPet-v1");

        public bool HasApiKey
        {
            get
            {
                try { return !string.IsNullOrWhiteSpace(GetApiKey()); }
                catch { return false; }
            }
        }

        public string GetApiKey()
        {
            if (!File.Exists(_secretPath))
                return string.Empty;

            var encrypted = File.ReadAllBytes(_secretPath);
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(clear);
        }

        public void SetApiKey(string apiKey)
        {
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                ClearApiKey();
                return;
            }

            Directory.CreateDirectory(SettingsService.DataDirectory);
            var clear = Encoding.UTF8.GetBytes(apiKey.Trim());
            var encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(_secretPath, encrypted);
        }

        public void ClearApiKey()
        {
            if (File.Exists(_secretPath))
                File.Delete(_secretPath);
        }
    }
}
