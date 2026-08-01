using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class SuWuDuUpdater
{
    private const string UninstallRegistryPath =
        @"Software\Microsoft\Windows\CurrentVersion\Uninstall\SuWuDuDesktopPet";
    private static readonly string DataDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PixelHeartDesktopPet");
    private static readonly string LogPath = Path.Combine(DataDirectory, "update.log");

    [STAThread]
    private static int Main(string[] args)
    {
        bool validationOnly = args.Any(argument =>
            string.Equals(argument, "--validate-package", StringComparison.OrdinalIgnoreCase));
        try
        {
            Directory.CreateDirectory(DataDirectory);
            Dictionary<string, string> options = ParseArguments(args);
            if (options.ContainsKey("--validate-package"))
            {
                ValidatePackageOnly(
                    options["--validate-package"],
                    Require(options, "--version"),
                    Require(options, "--sha256"));
                return 0;
            }

            if (!options.ContainsKey("--apply"))
                throw new ArgumentException("缺少 --apply 参数。");

            ApplyUpdate(
                Require(options, "--package"),
                Require(options, "--target"),
                Require(options, "--version"),
                Require(options, "--sha256"),
                int.Parse(Require(options, "--pid"), CultureInfo.InvariantCulture));
            return 0;
        }
        catch (Exception ex)
        {
            Log("更新失败：" + ex);
            if (!validationOnly)
            {
                MessageBox.Show(
                    "苏无度没有完成更新，原来的版本会保留。\r\n\r\n" + ex.Message,
                    "苏无度更新失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            return 1;
        }
    }

    private static void ApplyUpdate(
        string packagePath,
        string targetPath,
        string versionText,
        string expectedHash,
        int processId)
    {
        packagePath = Path.GetFullPath(packagePath);
        targetPath = Path.GetFullPath(targetPath).TrimEnd(Path.DirectorySeparatorChar);
        Version expectedVersion = ParseVersion(versionText);
        ValidateTarget(targetPath);
        ValidateHash(packagePath, expectedHash);
        WaitForApplication(processId);

        string parent = Directory.GetParent(targetPath)?.FullName;
        if (string.IsNullOrWhiteSpace(parent))
            throw new InvalidOperationException("无法确定安装目录的父目录。");
        string marker = Guid.NewGuid().ToString("N");
        string stagingPath = Path.Combine(parent, ".suwudu-update-" + marker);
        string backupPath = Path.Combine(parent, ".suwudu-backup-" + marker);
        bool targetMoved = false;

        try
        {
            Directory.CreateDirectory(stagingPath);
            ExtractSafely(packagePath, stagingPath);
            ValidateExtractedApplication(stagingPath, expectedVersion);

            string existingUninstaller = Path.Combine(targetPath, "Uninstall.exe");
            File.Copy(existingUninstaller, Path.Combine(stagingPath, "Uninstall.exe"), true);

            MoveDirectoryWithRetries(targetPath, backupPath);
            targetMoved = true;
            try
            {
                MoveDirectoryWithRetries(stagingPath, targetPath);
            }
            catch
            {
                if (!Directory.Exists(targetPath) && Directory.Exists(backupPath))
                    MoveDirectoryWithRetries(backupPath, targetPath);
                throw;
            }

            SetInstalledVersion(versionText, targetPath);
            string application = Path.Combine(targetPath, "SuWuDu.exe");
            Process.Start(new ProcessStartInfo
            {
                FileName = application,
                Arguments = "--background",
                WorkingDirectory = targetPath,
                UseShellExecute = true
            });
            Log("已更新到 v" + versionText + "。安装目录：" + targetPath);
            TryDeleteDirectory(backupPath);
            ScheduleSelfDelete();
        }
        catch
        {
            if (!targetMoved) TryDeleteDirectory(stagingPath);
            throw;
        }
    }

    private static void ValidatePackageOnly(
        string packagePath, string versionText, string expectedHash)
    {
        packagePath = Path.GetFullPath(packagePath);
        Version expectedVersion = ParseVersion(versionText);
        ValidateHash(packagePath, expectedHash);
        string temporary = Path.Combine(Path.GetTempPath(),
            "suwudu-validate-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(temporary);
            bool updaterFound = false;
            string root = Path.GetFullPath(temporary).TrimEnd(Path.DirectorySeparatorChar) +
                Path.DirectorySeparatorChar;
            using (ZipArchive archive = ZipFile.OpenRead(packagePath))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string output = Path.GetFullPath(Path.Combine(temporary, entry.FullName));
                    if (!output.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("更新包包含不安全的文件路径。");
                    if (string.Equals(entry.FullName, "SuWuDuUpdater.exe",
                        StringComparison.OrdinalIgnoreCase))
                        updaterFound = true;
                    if (string.Equals(entry.FullName, "SuWuDu.exe",
                        StringComparison.OrdinalIgnoreCase))
                        entry.ExtractToFile(Path.Combine(temporary, "SuWuDu.exe"), true);
                }
            }
            if (!updaterFound)
                throw new InvalidDataException("更新包缺少更新器。");
            ValidateApplicationVersion(Path.Combine(temporary, "SuWuDu.exe"), expectedVersion);
            Log("更新包验证成功：" + packagePath);
        }
        finally
        {
            TryDeleteDirectory(temporary);
        }
    }

    private static void ValidateTarget(string targetPath)
    {
        string root = Path.GetPathRoot(targetPath);
        if (string.IsNullOrWhiteSpace(root) ||
            string.Equals(root.TrimEnd(Path.DirectorySeparatorChar),
                targetPath.TrimEnd(Path.DirectorySeparatorChar),
                StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("拒绝更新磁盘根目录。");
        if (!Directory.Exists(targetPath) ||
            !File.Exists(Path.Combine(targetPath, "SuWuDu.exe")) ||
            !File.Exists(Path.Combine(targetPath, "Uninstall.exe")))
            throw new InvalidOperationException("目标目录不是完整的苏无度安装目录。");

        using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallRegistryPath))
        {
            string registered = key?.GetValue("InstallLocation") as string;
            if (string.IsNullOrWhiteSpace(registered) || !PathsEqual(registered, targetPath))
                throw new InvalidOperationException("安装目录与 Windows 中登记的位置不一致。");
        }
    }

    private static void ValidateExtractedApplication(string directory, Version expected)
    {
        string application = Path.Combine(directory, "SuWuDu.exe");
        string updater = Path.Combine(directory, "SuWuDuUpdater.exe");
        if (!File.Exists(application) || !File.Exists(updater))
            throw new InvalidDataException("更新包缺少主程序或更新器。");

        ValidateApplicationVersion(application, expected);
    }

    private static void ValidateApplicationVersion(string application, Version expected)
    {
        if (!File.Exists(application))
            throw new InvalidDataException("更新包缺少主程序。");
        FileVersionInfo info = FileVersionInfo.GetVersionInfo(application);
        Version actual;
        if (!Version.TryParse(info.FileVersion, out actual) ||
            actual.Major != expected.Major || actual.Minor != expected.Minor ||
            actual.Build != expected.Build)
            throw new InvalidDataException("更新包中的程序版本与 Release 版本不一致。");
    }

    private static void ExtractSafely(string zipPath, string destination)
    {
        string root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar) +
            Path.DirectorySeparatorChar;
        using (ZipArchive archive = ZipFile.OpenRead(zipPath))
        {
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                string output = Path.GetFullPath(Path.Combine(destination, entry.FullName));
                if (!output.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("更新包包含不安全的文件路径。");
                if (string.IsNullOrEmpty(entry.Name))
                {
                    Directory.CreateDirectory(output);
                    continue;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(output));
                entry.ExtractToFile(output, true);
            }
        }
    }

    private static void ValidateHash(string path, string expected)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("找不到更新包。", path);
        string normalized = (expected ?? string.Empty).Trim().ToUpperInvariant();
        if (normalized.Length != 64 || normalized.Any(character => !Uri.IsHexDigit(character)))
            throw new InvalidDataException("SHA-256 校验值无效。");
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
        {
            string actual = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", string.Empty);
            if (!string.Equals(actual, normalized, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("更新包的 SHA-256 校验失败。");
        }
    }

    private static void WaitForApplication(int processId)
    {
        try
        {
            Process process = Process.GetProcessById(processId);
            if (!process.WaitForExit(60000))
                throw new TimeoutException("等待苏无度退出超时。");
        }
        catch (ArgumentException) { }
    }

    private static void MoveDirectoryWithRetries(string source, string destination)
    {
        Exception last = null;
        for (int attempt = 0; attempt < 12; attempt++)
        {
            try
            {
                Directory.Move(source, destination);
                return;
            }
            catch (Exception ex)
            {
                last = ex;
                Thread.Sleep(500);
            }
        }
        throw new IOException("无法替换程序目录。", last);
    }

    private static void SetInstalledVersion(string versionText, string targetPath)
    {
        using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
            UninstallRegistryPath, writable: true))
        {
            if (key == null) return;
            key.SetValue("DisplayVersion", versionText);
            key.SetValue("DisplayIcon", Path.Combine(targetPath, "SuWuDu.exe"));
            key.SetValue("InstallLocation", targetPath);
        }
    }

    private static Version ParseVersion(string value)
    {
        Version version;
        string text = (value ?? string.Empty).Trim().TrimStart('v', 'V');
        if (!Version.TryParse(text, out version))
            throw new ArgumentException("版本号无效：" + value);
        return version;
    }

    private static Dictionary<string, string> ParseArguments(string[] args)
    {
        Dictionary<string, string> result =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; index < args.Length; index++)
        {
            string key = args[index];
            if (!key.StartsWith("--", StringComparison.Ordinal)) continue;
            if (string.Equals(key, "--apply", StringComparison.OrdinalIgnoreCase))
            {
                result[key] = "true";
                continue;
            }
            if (index + 1 >= args.Length)
                throw new ArgumentException("参数缺少值：" + key);
            result[key] = args[++index];
        }
        return result;
    }

    private static string Require(Dictionary<string, string> values, string key)
    {
        string value;
        if (!values.TryGetValue(key, out value) || string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("缺少参数：" + key);
        return value;
    }

    private static bool PathsEqual(string first, string second)
    {
        string a = Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar);
        string b = Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar);
        return string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    }

    private static void TryDeleteDirectory(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        for (int attempt = 0; attempt < 8; attempt++)
        {
            try
            {
                if (Directory.Exists(path)) Directory.Delete(path, true);
                return;
            }
            catch { Thread.Sleep(350); }
        }
    }

    private static void ScheduleSelfDelete()
    {
        try
        {
            string directory = AppDomain.CurrentDomain.BaseDirectory
                .TrimEnd(Path.DirectorySeparatorChar);
            Process.Start(new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c ping 127.0.0.1 -n 3 > nul & rmdir /s /q \"" + directory + "\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                WindowStyle = ProcessWindowStyle.Hidden
            });
        }
        catch { }
    }

    private static void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(DataDirectory);
            File.AppendAllText(LogPath,
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) +
                "  " + message + Environment.NewLine,
                new UTF8Encoding(false));
        }
        catch { }
    }
}
