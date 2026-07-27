using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace DesktopPet.Services
{
    public static class CodexLocator
    {
        public static string FindExecutable()
        {
            var candidates = new List<string>
            {
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                    "Tools", "Codex", "package", "bin", "codex.exe"),
                Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                    "..", "..", "Tools", "Codex", "package", "bin", "codex.exe")),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs", "OpenAI", "Codex", "bin", "codex.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    ".codex", "packages", "standalone", "current", "bin", "codex.exe")
            };

            var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            candidates.AddRange(path.Split(new[] { Path.PathSeparator },
                    StringSplitOptions.RemoveEmptyEntries)
                .Select(item => Path.Combine(item.Trim().Trim('"'), "codex.exe")));
            candidates.AddRange(path.Split(new[] { Path.PathSeparator },
                    StringSplitOptions.RemoveEmptyEntries)
                .Select(item => Path.Combine(item.Trim().Trim('"'),
                    "codex-x86_64-pc-windows-msvc.exe")));

            return candidates.FirstOrDefault(candidate =>
                !string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate));
        }
    }
}
