using System;
using System.IO;
using System.Runtime.Serialization.Json;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public class SettingsService
    {
        public static readonly string DataDirectory =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PixelHeartDesktopPet");

        public string SettingsPath => Path.Combine(DataDirectory, "settings.json");

        public AppSettings Load()
        {
            try
            {
                if (!File.Exists(SettingsPath))
                    return new AppSettings();

                AppSettings settings;
                string previousName;
                using (var stream = File.OpenRead(SettingsPath))
                {
                    var serializer = new DataContractJsonSerializer(typeof(AppSettings));
                    settings = serializer.ReadObject(stream) as AppSettings ?? new AppSettings();
                    previousName = settings.PetName;
                    settings.Normalize();
                }
                if (!string.Equals(previousName, settings.PetName, StringComparison.Ordinal))
                    Save(settings);
                return settings;
            }
            catch
            {
                return new AppSettings();
            }
        }

        public void Save(AppSettings settings)
        {
            settings.Normalize();
            Directory.CreateDirectory(DataDirectory);
            var temporaryPath = SettingsPath + ".tmp";
            using (var stream = File.Create(temporaryPath))
            {
                var serializer = new DataContractJsonSerializer(typeof(AppSettings));
                serializer.WriteObject(stream, settings);
            }

            if (File.Exists(SettingsPath))
            {
                var backupPath = SettingsPath + ".bak";
                File.Replace(temporaryPath, SettingsPath, backupPath, true);
            }
            else
            {
                File.Move(temporaryPath, SettingsPath);
            }
        }
    }
}
