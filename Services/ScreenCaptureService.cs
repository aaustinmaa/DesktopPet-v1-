using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace DesktopPet.Services
{
    public sealed class ScreenCaptureService
    {
        private const int MaxLongEdge = 2560;
        private static readonly string CaptureDirectory =
            Path.Combine(SettingsService.DataDirectory, "ScreenCaptures");

        public ScreenCaptureService()
        {
            CleanupStaleCaptures();
        }

        public string CaptureVirtualDesktop()
        {
            var bounds = SystemInformation.VirtualScreen;
            if (bounds.Width <= 0 || bounds.Height <= 0)
                throw new InvalidOperationException("Windows 没有返回可截图的显示器区域。");

            Directory.CreateDirectory(CaptureDirectory);
            var path = Path.Combine(
                CaptureDirectory,
                "screen-" + Guid.NewGuid().ToString("N") + ".jpg");

            using (var fullSize = new Bitmap(
                bounds.Width, bounds.Height, PixelFormat.Format24bppRgb))
            {
                using (var graphics = Graphics.FromImage(fullSize))
                {
                    graphics.CopyFromScreen(
                        bounds.Left,
                        bounds.Top,
                        0,
                        0,
                        bounds.Size,
                        CopyPixelOperation.SourceCopy);
                }

                using (var output = ResizeIfNeeded(fullSize))
                    SaveJpeg(output, path, 88L);
            }
            return path;
        }

        public void DeleteCapture(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return;
            try
            {
                var fullPath = Path.GetFullPath(path);
                var captureRoot = Path.GetFullPath(CaptureDirectory)
                    .TrimEnd(Path.DirectorySeparatorChar) +
                    Path.DirectorySeparatorChar;
                if (!fullPath.StartsWith(
                        captureRoot, StringComparison.OrdinalIgnoreCase))
                    return;
                if (File.Exists(fullPath))
                    File.Delete(fullPath);
            }
            catch
            {
                // A failed cleanup must not hide a useful chat response.
            }
        }

        private static Bitmap ResizeIfNeeded(Bitmap source)
        {
            var longest = Math.Max(source.Width, source.Height);
            if (longest <= MaxLongEdge)
                return source.Clone(
                    new Rectangle(0, 0, source.Width, source.Height),
                    PixelFormat.Format24bppRgb);

            var scale = MaxLongEdge / (double)longest;
            var width = Math.Max(1, (int)Math.Round(source.Width * scale));
            var height = Math.Max(1, (int)Math.Round(source.Height * scale));
            var resized = new Bitmap(width, height, PixelFormat.Format24bppRgb);
            using (var graphics = Graphics.FromImage(resized))
            {
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.DrawImage(source, 0, 0, width, height);
            }
            return resized;
        }

        private static void SaveJpeg(Bitmap bitmap, string path, long quality)
        {
            var encoder = ImageCodecInfo.GetImageEncoders()
                .First(item => item.FormatID == ImageFormat.Jpeg.Guid);
            using (var parameters = new EncoderParameters(1))
            {
                parameters.Param[0] = new EncoderParameter(
                    System.Drawing.Imaging.Encoder.Quality, quality);
                bitmap.Save(path, encoder, parameters);
            }
        }

        private static void CleanupStaleCaptures()
        {
            try
            {
                if (!Directory.Exists(CaptureDirectory)) return;
                var cutoff = DateTime.UtcNow.AddHours(-12);
                foreach (var path in Directory.GetFiles(
                    CaptureDirectory, "screen-*.jpg", SearchOption.TopDirectoryOnly))
                {
                    if (File.GetLastWriteTimeUtc(path) < cutoff)
                        File.Delete(path);
                }
            }
            catch
            {
                // Best-effort cleanup only.
            }
        }
    }
}
