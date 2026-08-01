using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace DesktopPet.Services
{
    public sealed class UpdateReleaseInfo
    {
        public Version Version { get; set; }
        public string VersionText { get; set; }
        public string Notes { get; set; }
        public string PackageUrl { get; set; }
        public string ChecksumUrl { get; set; }
        public string ReleaseUrl { get; set; }
    }

    public sealed class UpdateCheckResult
    {
        public bool Skipped { get; set; }
        public bool IsInstalledCopy { get; set; }
        public UpdateReleaseInfo Release { get; set; }
        public string Message { get; set; }

        public bool HasUpdate => Release != null;
    }

    public sealed class UpdateService
    {
        private const string Repository = "aaustinmaa/DesktopPet-v1-";
        private const string LatestReleaseApi =
            "https://api.github.com/repos/" + Repository + "/releases/latest";
        private const string UninstallRegistryPath =
            @"Software\Microsoft\Windows\CurrentVersion\Uninstall\SuWuDuDesktopPet";
        private static readonly TimeSpan AutomaticCheckInterval = TimeSpan.FromHours(6);
        private readonly string _applicationDirectory = AppDomain.CurrentDomain.BaseDirectory;
        private readonly string _lastCheckPath = Path.Combine(
            SettingsService.DataDirectory, "last-update-check.txt");

        public Version CurrentVersion => Assembly.GetExecutingAssembly().GetName().Version;

        public bool IsInstalledCopy
        {
            get
            {
                string uninstaller = Path.Combine(_applicationDirectory, "Uninstall.exe");
                if (!File.Exists(uninstaller)) return false;

                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallRegistryPath))
                {
                    string registered = key?.GetValue("InstallLocation") as string;
                    if (string.IsNullOrWhiteSpace(registered)) return false;
                    return PathsEqual(registered, _applicationDirectory);
                }
            }
        }

        public async Task<UpdateCheckResult> CheckAsync(bool manual)
        {
            if (!IsInstalledCopy)
            {
                return new UpdateCheckResult
                {
                    IsInstalledCopy = false,
                    Message = "自动更新只用于已经安装的苏无度。你现在运行的是开发版或便携版，请先安装最新版安装包。"
                };
            }

            if (!manual && WasCheckedRecently())
            {
                return new UpdateCheckResult
                {
                    Skipped = true,
                    IsInstalledCopy = true,
                    Message = "最近已经检查过更新。"
                };
            }

            try
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                using (HttpClient client = CreateClient())
                using (HttpResponseMessage response = await client.GetAsync(LatestReleaseApi))
                {
                    SaveLastCheckTime();
                    if (response.StatusCode == HttpStatusCode.NotFound)
                    {
                        return new UpdateCheckResult
                        {
                            IsInstalledCopy = true,
                            Message = "GitHub 上还没有可用的正式版本。"
                        };
                    }

                    response.EnsureSuccessStatusCode();
                    string json = await response.Content.ReadAsStringAsync();
                    GitHubRelease release = new JavaScriptSerializer()
                        .Deserialize<GitHubRelease>(json);
                    Version latest;
                    if (release == null || release.draft || release.prerelease ||
                        !TryParseVersion(release.tag_name, out latest))
                    {
                        throw new InvalidDataException("GitHub Release 的版本号无效。");
                    }

                    if (latest <= CurrentVersion)
                    {
                        return new UpdateCheckResult
                        {
                            IsInstalledCopy = true,
                            Message = "你正在使用最新版（v" + FormatVersion(CurrentVersion) + "）。"
                        };
                    }

                    string versionText = FormatVersion(latest);
                    string packageName = "SuWuDu-update-v" + versionText + ".zip";
                    string checksumName = packageName + ".sha256";
                    GitHubAsset package = release.assets?.FirstOrDefault(
                        asset => string.Equals(asset.name, packageName,
                            StringComparison.OrdinalIgnoreCase));
                    GitHubAsset checksum = release.assets?.FirstOrDefault(
                        asset => string.Equals(asset.name, checksumName,
                            StringComparison.OrdinalIgnoreCase));
                    if (package == null || checksum == null)
                    {
                        throw new InvalidDataException(
                            "这个 Release 缺少更新包或校验文件，请稍后再试。");
                    }

                    return new UpdateCheckResult
                    {
                        IsInstalledCopy = true,
                        Release = new UpdateReleaseInfo
                        {
                            Version = latest,
                            VersionText = versionText,
                            Notes = string.IsNullOrWhiteSpace(release.body)
                                ? "这个版本没有附加更新说明。"
                                : release.body.Trim(),
                            PackageUrl = package.browser_download_url,
                            ChecksumUrl = checksum.browser_download_url,
                            ReleaseUrl = release.html_url
                        }
                    };
                }
            }
            catch (Exception ex)
            {
                return new UpdateCheckResult
                {
                    IsInstalledCopy = true,
                    Message = "暂时无法检查更新：" + ex.Message
                };
            }
        }

        public async Task DownloadAndLaunchAsync(
            UpdateReleaseInfo release,
            IProgress<int> progress)
        {
            if (release == null) throw new ArgumentNullException(nameof(release));
            if (!IsInstalledCopy)
                throw new InvalidOperationException("当前程序不是已安装版本，无法自动替换。");

            string updateDirectory = Path.Combine(
                SettingsService.DataDirectory, "Updates", release.VersionText);
            Directory.CreateDirectory(updateDirectory);
            string packagePath = Path.Combine(
                updateDirectory, "SuWuDu-update-v" + release.VersionText + ".zip");
            string partialPath = packagePath + ".part";
            string checksumPath = packagePath + ".sha256";
            TryDelete(partialPath);

            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            using (HttpClient client = CreateClient())
            {
                string checksumText = await client.GetStringAsync(release.ChecksumUrl);
                string expectedHash = ParseChecksum(checksumText);
                File.WriteAllText(checksumPath, expectedHash + "  " +
                    Path.GetFileName(packagePath), new UTF8Encoding(false));

                using (HttpResponseMessage response = await client.GetAsync(
                    release.PackageUrl, HttpCompletionOption.ResponseHeadersRead))
                {
                    response.EnsureSuccessStatusCode();
                    long? total = response.Content.Headers.ContentLength;
                    using (Stream source = await response.Content.ReadAsStreamAsync())
                    using (FileStream destination = new FileStream(
                        partialPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        byte[] buffer = new byte[81920];
                        long received = 0;
                        int read;
                        while ((read = await source.ReadAsync(buffer, 0, buffer.Length)) > 0)
                        {
                            await destination.WriteAsync(buffer, 0, read);
                            received += read;
                            if (total.HasValue && total.Value > 0)
                                progress?.Report((int)(received * 100L / total.Value));
                        }
                    }
                }

                string actualHash = ComputeSha256(partialPath);
                if (!string.Equals(actualHash, expectedHash,
                    StringComparison.OrdinalIgnoreCase))
                {
                    TryDelete(partialPath);
                    throw new InvalidDataException("更新包校验失败，文件可能未完整下载。");
                }

                TryDelete(packagePath);
                File.Move(partialPath, packagePath);

                string installedUpdater = Path.Combine(
                    _applicationDirectory, "SuWuDuUpdater.exe");
                if (!File.Exists(installedUpdater))
                    throw new FileNotFoundException("找不到更新程序。", installedUpdater);

                string updaterDirectory = Path.Combine(
                    SettingsService.DataDirectory, "Updater", Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(updaterDirectory);
                string updaterCopy = Path.Combine(updaterDirectory, "SuWuDuUpdater.exe");
                File.Copy(installedUpdater, updaterCopy, true);

                string arguments = "--apply --package " + Quote(packagePath) +
                    " --target " + Quote(_applicationDirectory) +
                    " --version " + Quote(release.VersionText) +
                    " --sha256 " + Quote(expectedHash) +
                    " --pid " + Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture);
                Process.Start(new ProcessStartInfo
                {
                    FileName = updaterCopy,
                    Arguments = arguments,
                    UseShellExecute = false,
                    WorkingDirectory = updaterDirectory
                });
            }
        }

        private static HttpClient CreateClient()
        {
            HttpClient client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("SuWuDu-DesktopPet-Updater/1.0");
            client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
            client.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28");
            return client;
        }

        private bool WasCheckedRecently()
        {
            try
            {
                DateTime saved;
                return File.Exists(_lastCheckPath) &&
                    DateTime.TryParse(File.ReadAllText(_lastCheckPath),
                        CultureInfo.InvariantCulture,
                        DateTimeStyles.RoundtripKind, out saved) &&
                    DateTime.UtcNow - saved.ToUniversalTime() < AutomaticCheckInterval;
            }
            catch { return false; }
        }

        private void SaveLastCheckTime()
        {
            try
            {
                Directory.CreateDirectory(SettingsService.DataDirectory);
                File.WriteAllText(_lastCheckPath,
                    DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    new UTF8Encoding(false));
            }
            catch { }
        }

        private static bool TryParseVersion(string tag, out Version version)
        {
            version = null;
            if (string.IsNullOrWhiteSpace(tag)) return false;
            string value = tag.Trim();
            if (value.StartsWith("v", StringComparison.OrdinalIgnoreCase))
                value = value.Substring(1);
            string core = value.Split('-', '+')[0];
            return Version.TryParse(core, out version);
        }

        private static string FormatVersion(Version version)
        {
            return version.Major + "." + version.Minor + "." +
                Math.Max(0, version.Build);
        }

        private static string ParseChecksum(string value)
        {
            string token = (value ?? string.Empty).Trim()
                .Split((char[])null, StringSplitOptions.RemoveEmptyEntries)
                .FirstOrDefault();
            if (string.IsNullOrWhiteSpace(token) || token.Length != 64 ||
                token.Any(character => !Uri.IsHexDigit(character)))
                throw new InvalidDataException("更新包的 SHA-256 校验文件无效。");
            return token.ToUpperInvariant();
        }

        private static string ComputeSha256(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", string.Empty);
        }

        private static bool PathsEqual(string first, string second)
        {
            string a = Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar);
            string b = Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar);
            return string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static void TryDelete(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }

        public sealed class GitHubRelease
        {
            public string tag_name { get; set; }
            public string body { get; set; }
            public string html_url { get; set; }
            public bool draft { get; set; }
            public bool prerelease { get; set; }
            public GitHubAsset[] assets { get; set; }
        }

        public sealed class GitHubAsset
        {
            public string name { get; set; }
            public string browser_download_url { get; set; }
        }
    }
}
