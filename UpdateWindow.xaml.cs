using System;
using System.Diagnostics;
using System.Windows;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class UpdateWindow : Window
    {
        private readonly UpdateService _updateService;
        private readonly UpdateReleaseInfo _release;
        private bool _busy;

        public UpdateWindow(UpdateService updateService, UpdateReleaseInfo release)
        {
            InitializeComponent();
            _updateService = updateService;
            _release = release;
            VersionText.Text = "当前版本 v" + Format(updateService.CurrentVersion) +
                "  →  新版本 v" + release.VersionText;
            NotesText.Text = release.Notes;
            StatusText.Text = "更新完成后，苏无度会自动重新出现。";
        }

        private async void Update_Click(object sender, RoutedEventArgs e)
        {
            if (_busy) return;
            _busy = true;
            UpdateButton.IsEnabled = false;
            LaterButton.IsEnabled = false;
            ReleasePageButton.IsEnabled = false;
            DownloadProgress.Visibility = Visibility.Visible;
            StatusText.Text = "正在下载更新…";

            try
            {
                Progress<int> progress = new Progress<int>(value =>
                {
                    DownloadProgress.Value = value;
                    StatusText.Text = "正在下载更新… " + value + "%";
                });
                await _updateService.DownloadAndLaunchAsync(_release, progress);
                StatusText.Text = "下载完成，正在重新启动…";
                Application.Current.Shutdown();
            }
            catch (Exception ex)
            {
                _busy = false;
                UpdateButton.IsEnabled = true;
                LaterButton.IsEnabled = true;
                ReleasePageButton.IsEnabled = true;
                StatusText.Text = "更新失败，请稍后重试。";
                MessageBox.Show(this, ex.Message, "苏无度更新",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void Later_Click(object sender, RoutedEventArgs e)
        {
            if (!_busy) Close();
        }

        private void ReleasePage_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(_release.ReleaseUrl)) return;
            Process.Start(new ProcessStartInfo
            {
                FileName = _release.ReleaseUrl,
                UseShellExecute = true
            });
        }

        private static string Format(Version version)
        {
            return version.Major + "." + version.Minor + "." +
                Math.Max(0, version.Build);
        }
    }
}
