using System;
using System.Globalization;
using System.Windows;
using DesktopPet.Models;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class SettingsWindow : Window
    {
        private readonly SecretService _secretService;
        public AppSettings ResultSettings { get; private set; }

        public SettingsWindow(AppSettings settings, SecretService secretService)
        {
            InitializeComponent();
            ResultSettings = settings;
            _secretService = secretService;

            PetNameBox.Text = settings.PetName;
            ScaleSlider.Value = settings.PetScale;
            TopmostBox.IsChecked = settings.Topmost;
            WanderBox.IsChecked = settings.AutoWander;
            StartupBox.IsChecked = settings.StartWithWindows;
            HydrationBox.IsChecked = settings.HydrationEnabled;
            HydrationBoxMinutes.Text = settings.HydrationMinutes.ToString(CultureInfo.InvariantCulture);
            FocusBoxMinutes.Text = settings.FocusMinutes.ToString(CultureInfo.InvariantCulture);
            ModelBox.Text = settings.AiModel;
            UpdateApiStatus();
        }

        private void ScaleSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (ScaleLabel != null) ScaleLabel.Text = Math.Round(e.NewValue * 100) + "%";
        }

        private void ClearApiKey_Click(object sender, RoutedEventArgs e)
        {
            _secretService.ClearApiKey();
            ApiKeyBox.Clear();
            UpdateApiStatus();
        }

        private void UpdateApiStatus()
        {
            if (ApiStatusText == null) return;
            ApiStatusText.Text = _secretService.HasApiKey
                ? "已保存加密的 API key。"
                : "当前未保存 API key，将使用离线模式。";
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            int hydrationMinutes;
            int focusMinutes;
            if (!int.TryParse(HydrationBoxMinutes.Text, out hydrationMinutes) ||
                hydrationMinutes < 10 || hydrationMinutes > 240)
            {
                MessageBox.Show("喝水提醒间隔请输入 10–240 分钟。", "设置",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            if (!int.TryParse(FocusBoxMinutes.Text, out focusMinutes) ||
                focusMinutes < 1 || focusMinutes > 120)
            {
                MessageBox.Show("专注时长请输入 1–120 分钟。", "设置",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            ResultSettings.PetName = PetNameBox.Text.Trim();
            ResultSettings.PetScale = ScaleSlider.Value;
            ResultSettings.Topmost = TopmostBox.IsChecked == true;
            ResultSettings.AutoWander = WanderBox.IsChecked == true;
            ResultSettings.StartWithWindows = StartupBox.IsChecked == true;
            ResultSettings.HydrationEnabled = HydrationBox.IsChecked == true;
            ResultSettings.HydrationMinutes = hydrationMinutes;
            ResultSettings.FocusMinutes = focusMinutes;
            ResultSettings.AiModel = ModelBox.Text.Trim();
            ResultSettings.Normalize();

            if (!string.IsNullOrWhiteSpace(ApiKeyBox.Password))
                _secretService.SetApiKey(ApiKeyBox.Password);

            DialogResult = true;
            Close();
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }
    }
}
