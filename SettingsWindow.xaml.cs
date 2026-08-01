using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DesktopPet.Models;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class SettingsWindow : Window
    {
        private readonly SecretService _secretService;
        private readonly MemoryService _memoryService = MemoryService.Shared;
        private readonly SoundService _soundService = new SoundService();
        private string _selectedProvider;
        private string _savedCodexModel;
        private string _savedCodexReasoningEffort;
        private bool _isUpdatingCodexModels;
        private bool _isUpdatingCodexReasoning;
        public AppSettings ResultSettings { get; private set; }
        public event Action<double> PetScalePreviewChanged;

        public SettingsWindow(AppSettings settings, SecretService secretService)
        {
            InitializeComponent();
            ResultSettings = settings;
            _secretService = secretService;

            PetNameBox.Text = settings.PetName;
            ScaleSlider.Value = settings.PetScale;
            TopmostBox.IsChecked = settings.Topmost;
            WanderBox.IsChecked = settings.AutoWander;
            WanderMinIdleSecondsBox.Text =
                settings.WanderMinIdleSeconds.ToString(CultureInfo.InvariantCulture);
            WanderMaxIdleSecondsBox.Text =
                settings.WanderMaxIdleSeconds.ToString(CultureInfo.InvariantCulture);
            StartupBox.IsChecked = settings.StartWithWindows;
            HydrationBox.IsChecked = settings.HydrationEnabled;
            HydrationBoxMinutes.Text = settings.HydrationMinutes.ToString(CultureInfo.InvariantCulture);
            FocusBoxMinutes.Text = settings.FocusMinutes.ToString(CultureInfo.InvariantCulture);
            FocusStartSoundBox.ItemsSource = SoundService.Options;
            FocusStartSoundBox.SelectedValue = settings.FocusStartSound;
            FocusCompleteSoundBox.ItemsSource = SoundService.Options;
            FocusCompleteSoundBox.SelectedValue = settings.FocusCompleteSound;
            RandomCueEnabledBox.IsChecked = settings.RandomCueEnabled;
            RandomCueMinMinutesBox.Text =
                settings.RandomCueMinMinutes.ToString(CultureInfo.InvariantCulture);
            RandomCueMaxMinutesBox.Text =
                settings.RandomCueMaxMinutes.ToString(CultureInfo.InvariantCulture);
            RandomCueBreakSecondsBox.Text =
                settings.RandomCueBreakSeconds.ToString(CultureInfo.InvariantCulture);
            RandomCueBreakSoundBox.ItemsSource = SoundService.Options;
            RandomCueBreakSoundBox.SelectedValue = settings.RandomCueBreakSound;
            RandomCueResumeSoundBox.ItemsSource = SoundService.Options;
            RandomCueResumeSoundBox.SelectedValue = settings.RandomCueResumeSound;
            UpdateRandomCueControls();
            ModelBox.Text = settings.AiModel;
            _savedCodexModel = settings.CodexModel ?? string.Empty;
            _savedCodexReasoningEffort = settings.CodexReasoningEffort ?? string.Empty;
            ResetCodexModelList("登录后会自动读取此账号可用的模型。");
            MemoryBox.IsChecked = settings.MemoryEnabled;
            _selectedProvider = settings.AiProvider;
            UpdateProviderPanels();
            UpdateApiStatus();
            Loaded += async (sender, args) => await RefreshCodexStatusAsync();
            Closed += (sender, args) => _soundService.Dispose();
        }

        private void PreviewFocusStartSound_Click(object sender, RoutedEventArgs e)
        {
            _soundService.PlayFocusStart(Convert.ToString(FocusStartSoundBox.SelectedValue));
        }

        private void PreviewFocusCompleteSound_Click(object sender, RoutedEventArgs e)
        {
            _soundService.PlayFocusComplete(Convert.ToString(FocusCompleteSoundBox.SelectedValue));
        }

        private void RandomCueEnabled_Changed(object sender, RoutedEventArgs e)
        {
            UpdateRandomCueControls();
        }

        private void UpdateRandomCueControls()
        {
            if (RandomCueOptionsPanel != null)
                RandomCueOptionsPanel.IsEnabled = RandomCueEnabledBox.IsChecked == true;
        }

        private void PreviewRandomCueBreakSound_Click(object sender, RoutedEventArgs e)
        {
            _soundService.PlayRandomBreak(
                Convert.ToString(RandomCueBreakSoundBox.SelectedValue));
        }

        private void PreviewRandomCueResumeSound_Click(object sender, RoutedEventArgs e)
        {
            _soundService.PlayRandomResume(
                Convert.ToString(RandomCueResumeSoundBox.SelectedValue));
        }

        private void ScaleSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (ScaleLabel != null) ScaleLabel.Text = Math.Round(e.NewValue * 100) + "%";
            PetScalePreviewChanged?.Invoke(e.NewValue);
        }

        private void ClearApiKey_Click(object sender, RoutedEventArgs e)
        {
            _secretService.ClearApiKey();
            ApiKeyBox.Clear();
            UpdateApiStatus();
        }

        private void Provider_Click(object sender, RoutedEventArgs e)
        {
            var button = sender as Button;
            if (button == null) return;
            _selectedProvider = Convert.ToString(button.Tag);
            UpdateProviderPanels();
        }

        private void UpdateProviderPanels()
        {
            if (CodexPanel == null) return;
            CodexPanel.Visibility = _selectedProvider == "codex"
                ? Visibility.Visible : Visibility.Collapsed;
            OpenAiPanel.Visibility = _selectedProvider == "openai"
                ? Visibility.Visible : Visibility.Collapsed;
            OfflinePanel.Visibility = _selectedProvider == "offline"
                ? Visibility.Visible : Visibility.Collapsed;

            StyleProviderButton(CodexProviderButton, _selectedProvider == "codex");
            StyleProviderButton(OpenAiProviderButton, _selectedProvider == "openai");
            StyleProviderButton(OfflineProviderButton, _selectedProvider == "offline");
        }

        private void StyleProviderButton(Button button, bool selected)
        {
            if (button == null) return;
            button.ClearValue(Control.BackgroundProperty);
            button.ClearValue(Control.ForegroundProperty);
            button.ClearValue(Control.BorderBrushProperty);
            button.Style = (Style)FindResource(
                selected ? "ProviderSelectedButtonStyle" : "SecondaryButtonStyle");
        }

        private async System.Threading.Tasks.Task RefreshCodexStatusAsync()
        {
            CodexStatusText.Text = "正在检查 ChatGPT 连接…";
            CodexConnectButton.IsEnabled = false;
            try
            {
                var status = await CodexService.GetAccountStatusAsync();
                ShowCodexStatus(status);
                if (status.IsSignedIn)
                    await RefreshCodexModelsAsync();
                else
                    ResetCodexModelList("连接 ChatGPT 后会显示当前账号可用的模型。");
            }
            finally
            {
                CodexConnectButton.IsEnabled = true;
            }
        }

        private void ShowCodexStatus(CodexAccountStatus status)
        {
            if (!status.IsAvailable)
            {
                CodexStatusText.Text = "Codex 组件缺失，请重新下载完整版本。";
                CodexConnectButton.Visibility = Visibility.Collapsed;
                CodexLogoutButton.Visibility = Visibility.Collapsed;
                return;
            }
            if (status.IsSignedIn)
            {
                var account = string.IsNullOrWhiteSpace(status.Email)
                    ? "ChatGPT"
                    : status.Email;
                var plan = string.IsNullOrWhiteSpace(status.PlanType)
                    ? string.Empty
                    : " · " + status.PlanType;
                CodexStatusText.Text = "已连接：" + account + plan;
                CodexConnectButton.Content = "重新连接";
                CodexConnectButton.Visibility = Visibility.Visible;
                CodexLogoutButton.Visibility = Visibility.Visible;
            }
            else
            {
                CodexStatusText.Text = string.IsNullOrWhiteSpace(status.Error)
                    ? "尚未连接 ChatGPT。苏无度的登录与其他 Codex 客户端相互独立。"
                    : "连接检查失败：" + status.Error;
                CodexConnectButton.Content = "连接我的 ChatGPT";
                CodexConnectButton.Visibility = Visibility.Visible;
                CodexLogoutButton.Visibility = Visibility.Collapsed;
            }
        }

        private async System.Threading.Tasks.Task RefreshCodexModelsAsync()
        {
            CodexModelBox.IsEnabled = false;
            CodexModelHintText.Text = "正在读取当前账号可用的模型…";
            try
            {
                var models = await CodexService.GetAvailableModelsAsync();
                var accountDefaultModel = models.FirstOrDefault(item => item.IsDefault) ??
                    models.FirstOrDefault();
                var options = new List<CodexModelOption>
                {
                    new CodexModelOption
                    {
                        ModelId = string.Empty,
                        DisplayName = "自动选择",
                        Description = "由 Codex 选择当前账号的默认模型。",
                        IsDefault = true,
                        DefaultReasoningEffort = accountDefaultModel == null
                            ? string.Empty
                            : accountDefaultModel.DefaultReasoningEffort,
                        SupportedReasoningEfforts = accountDefaultModel == null
                            ? new List<CodexReasoningEffortOption>()
                            : accountDefaultModel.SupportedReasoningEfforts
                    }
                };
                options.AddRange(models);

                _isUpdatingCodexModels = true;
                CodexModelBox.ItemsSource = options;
                var selected = options.FirstOrDefault(item =>
                    !string.IsNullOrWhiteSpace(_savedCodexModel) &&
                    string.Equals(item.ModelId, _savedCodexModel,
                        StringComparison.OrdinalIgnoreCase));
                CodexModelBox.SelectedItem = selected ?? options[0];
                _isUpdatingCodexModels = false;

                if (selected == null && !string.IsNullOrWhiteSpace(_savedCodexModel))
                {
                    CodexModelHintText.Text =
                        "原来的模型“" + _savedCodexModel +
                        "”不在账号可用列表中，已安全切换为自动选择。";
                    _savedCodexModel = string.Empty;
                }
                else
                {
                    UpdateCodexModelHint();
                }
                RefreshCodexReasoningOptions();
            }
            catch (Exception ex)
            {
                ResetCodexModelList("模型列表读取失败，将使用自动选择。 " + ex.Message);
            }
            finally
            {
                CodexModelBox.IsEnabled = true;
            }
        }

        private void ResetCodexModelList(string hint)
        {
            if (CodexModelBox == null) return;
            _isUpdatingCodexModels = true;
            CodexModelBox.ItemsSource = new[]
            {
                new CodexModelOption
                {
                    ModelId = string.Empty,
                    DisplayName = "自动选择",
                    Description = "由 Codex 选择当前账号的默认模型。",
                    IsDefault = true,
                    DefaultReasoningEffort = string.Empty,
                    SupportedReasoningEfforts =
                        new List<CodexReasoningEffortOption>()
                }
            };
            CodexModelBox.SelectedIndex = 0;
            _isUpdatingCodexModels = false;
            ResetCodexReasoningList("读取模型后会显示可用的推理强度。");
            if (CodexModelHintText != null)
                CodexModelHintText.Text = hint;
        }

        private void CodexModelBox_SelectionChanged(
            object sender,
            SelectionChangedEventArgs e)
        {
            if (_isUpdatingCodexModels) return;
            var selected = CodexModelBox.SelectedItem as CodexModelOption;
            _savedCodexModel = selected == null ? string.Empty : selected.ModelId;
            UpdateCodexModelHint();
            RefreshCodexReasoningOptions();
        }

        private void UpdateCodexModelHint()
        {
            var selected = CodexModelBox.SelectedItem as CodexModelOption;
            if (selected == null)
            {
                CodexModelHintText.Text = string.Empty;
                return;
            }
            CodexModelHintText.Text = string.IsNullOrWhiteSpace(selected.ModelId)
                ? "由 Codex 自动选择，推荐大多数用户使用。"
                : selected.Description + "\n模型 ID：" + selected.ModelId;
        }

        private void RefreshCodexReasoningOptions()
        {
            if (CodexReasoningBox == null) return;
            var model = CodexModelBox.SelectedItem as CodexModelOption;
            var options = new List<CodexReasoningEffortOption>
            {
                new CodexReasoningEffortOption
                {
                    Effort = string.Empty,
                    Description = "使用所选模型公布的默认推理强度。"
                }
            };
            if (model != null && model.SupportedReasoningEfforts != null)
            {
                options.AddRange(model.SupportedReasoningEfforts.Select(item =>
                    new CodexReasoningEffortOption
                    {
                        Effort = item.Effort,
                        Description = item.Description,
                        IsModelDefault = item.IsModelDefault
                    }));
            }

            _isUpdatingCodexReasoning = true;
            CodexReasoningBox.ItemsSource = options;
            var selected = options.FirstOrDefault(item =>
                !string.IsNullOrWhiteSpace(_savedCodexReasoningEffort) &&
                string.Equals(item.Effort, _savedCodexReasoningEffort,
                    StringComparison.OrdinalIgnoreCase));
            CodexReasoningBox.SelectedItem = selected ?? options[0];
            _isUpdatingCodexReasoning = false;

            if (selected == null && !string.IsNullOrWhiteSpace(_savedCodexReasoningEffort))
            {
                CodexReasoningHintText.Text =
                    "原来的推理强度“" + _savedCodexReasoningEffort +
                    "”不适用于这个模型，已切换为模型默认值。";
                _savedCodexReasoningEffort = string.Empty;
            }
            else
            {
                UpdateCodexReasoningHint();
            }
        }

        private void ResetCodexReasoningList(string hint)
        {
            if (CodexReasoningBox == null) return;
            _isUpdatingCodexReasoning = true;
            CodexReasoningBox.ItemsSource = new[]
            {
                new CodexReasoningEffortOption
                {
                    Effort = string.Empty,
                    Description = "使用所选模型公布的默认推理强度。"
                }
            };
            CodexReasoningBox.SelectedIndex = 0;
            _isUpdatingCodexReasoning = false;
            if (CodexReasoningHintText != null)
                CodexReasoningHintText.Text = hint;
        }

        private void CodexReasoningBox_SelectionChanged(
            object sender,
            SelectionChangedEventArgs e)
        {
            if (_isUpdatingCodexReasoning) return;
            var selected = CodexReasoningBox.SelectedItem as CodexReasoningEffortOption;
            _savedCodexReasoningEffort = selected == null
                ? string.Empty
                : selected.Effort;
            UpdateCodexReasoningHint();
        }

        private void UpdateCodexReasoningHint()
        {
            var selected = CodexReasoningBox.SelectedItem as CodexReasoningEffortOption;
            var model = CodexModelBox.SelectedItem as CodexModelOption;
            if (selected == null)
            {
                CodexReasoningHintText.Text = string.Empty;
                return;
            }
            if (string.IsNullOrWhiteSpace(selected.Effort))
            {
                var modelDefault = model == null
                    ? string.Empty
                    : model.DefaultReasoningEffort;
                CodexReasoningHintText.Text = string.IsNullOrWhiteSpace(modelDefault)
                    ? "由 Codex 使用所选模型的默认推理强度。"
                    : "模型默认推理强度：" + modelDefault + "。";
                return;
            }
            CodexReasoningHintText.Text = string.IsNullOrWhiteSpace(selected.Description)
                ? "将明确使用 " + selected.Effort + " 推理强度。"
                : selected.Description;
        }

        private async void CodexConnect_Click(object sender, RoutedEventArgs e)
        {
            _selectedProvider = "codex";
            UpdateProviderPanels();
            CodexConnectButton.IsEnabled = false;
            CodexLogoutButton.IsEnabled = false;
            CodexStatusText.Text = "浏览器即将打开。登录后请回到这里，苏无度会自动确认。";
            try
            {
                var status = await CodexService.LoginAsync();
                ShowCodexStatus(status);
                if (status.IsSignedIn)
                    await RefreshCodexModelsAsync();
                if (!status.IsSignedIn)
                    MessageBox.Show("登录流程已结束，但没有检测到 ChatGPT 账号，请再试一次。",
                        "ChatGPT 连接", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            catch (Exception ex)
            {
                CodexStatusText.Text = "连接失败：" + ex.Message;
                MessageBox.Show(ex.Message, "ChatGPT 连接",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            finally
            {
                CodexConnectButton.IsEnabled = true;
                CodexLogoutButton.IsEnabled = true;
            }
        }

        private async void CodexLogout_Click(object sender, RoutedEventArgs e)
        {
            if (MessageBox.Show(
                    "确定断开苏无度与当前 ChatGPT 账号的连接吗？\n\n" +
                    "这只会清除苏无度保存的授权，不会退出浏览器、ChatGPT 桌面端或其他 Codex 客户端。",
                    "断开 ChatGPT 连接", MessageBoxButton.YesNo,
                    MessageBoxImage.Question) !=
                MessageBoxResult.Yes)
                return;

            CodexLogoutButton.IsEnabled = false;
            try
            {
                await CodexService.LogoutAsync();
                ShowCodexStatus(new CodexAccountStatus
                {
                    IsAvailable = CodexService.IsAvailable,
                    IsSignedIn = false
                });
                ResetCodexModelList("连接 ChatGPT 后会显示当前账号可用的模型。");
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "断开 ChatGPT 连接",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            finally
            {
                CodexLogoutButton.IsEnabled = true;
            }
        }

        private void ClearMemory_Click(object sender, RoutedEventArgs e)
        {
            if (MessageBox.Show(
                    "确定清除苏无度保存的所有聊天、归档和记忆吗？此操作无法撤销。",
                    "清除所有聊天与记忆",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning) !=
                MessageBoxResult.Yes)
                return;
            _memoryService.ClearAll();
            MessageBox.Show("苏无度的所有本地聊天、归档与记忆已经清除。",
                "清除完成", MessageBoxButton.OK, MessageBoxImage.Information);
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
            int randomCueMinMinutes;
            int randomCueMaxMinutes;
            int randomCueBreakSeconds;
            int wanderMinIdleSeconds;
            int wanderMaxIdleSeconds;
            if (!int.TryParse(
                    WanderMinIdleSecondsBox.Text,
                    out wanderMinIdleSeconds) ||
                wanderMinIdleSeconds < 3 ||
                wanderMinIdleSeconds > 300 ||
                !int.TryParse(
                    WanderMaxIdleSecondsBox.Text,
                    out wanderMaxIdleSeconds) ||
                wanderMaxIdleSeconds < 3 ||
                wanderMaxIdleSeconds > 300 ||
                wanderMinIdleSeconds > wanderMaxIdleSeconds)
            {
                MessageBox.Show(
                    "漫游停留范围请输入 3–300 秒，并确保最短时间不大于最长时间。",
                    "设置", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
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
            if (!int.TryParse(RandomCueMinMinutesBox.Text, out randomCueMinMinutes) ||
                randomCueMinMinutes < 1 || randomCueMinMinutes > 120 ||
                !int.TryParse(RandomCueMaxMinutesBox.Text, out randomCueMaxMinutes) ||
                randomCueMaxMinutes < 1 || randomCueMaxMinutes > 120 ||
                randomCueMinMinutes > randomCueMaxMinutes)
            {
                MessageBox.Show(
                    "随机提示音间隔请输入 1–120 分钟，并确保最短间隔不大于最长间隔。",
                    "设置", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            if (!int.TryParse(RandomCueBreakSecondsBox.Text, out randomCueBreakSeconds) ||
                randomCueBreakSeconds < 1 || randomCueBreakSeconds > 300)
            {
                MessageBox.Show("微休息时长请输入 1–300 秒。", "设置",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            ResultSettings.PetName = PetNameBox.Text.Trim();
            ResultSettings.PetScale = ScaleSlider.Value;
            ResultSettings.Topmost = TopmostBox.IsChecked == true;
            ResultSettings.AutoWander = WanderBox.IsChecked == true;
            ResultSettings.WanderMinIdleSeconds = wanderMinIdleSeconds;
            ResultSettings.WanderMaxIdleSeconds = wanderMaxIdleSeconds;
            ResultSettings.StartWithWindows = StartupBox.IsChecked == true;
            ResultSettings.HydrationEnabled = HydrationBox.IsChecked == true;
            ResultSettings.HydrationMinutes = hydrationMinutes;
            ResultSettings.FocusMinutes = focusMinutes;
            ResultSettings.FocusStartSound =
                Convert.ToString(FocusStartSoundBox.SelectedValue);
            ResultSettings.FocusCompleteSound =
                Convert.ToString(FocusCompleteSoundBox.SelectedValue);
            ResultSettings.RandomCueEnabled = RandomCueEnabledBox.IsChecked == true;
            ResultSettings.RandomCueMinMinutes = randomCueMinMinutes;
            ResultSettings.RandomCueMaxMinutes = randomCueMaxMinutes;
            ResultSettings.RandomCueBreakSeconds = randomCueBreakSeconds;
            ResultSettings.RandomCueBreakSound =
                Convert.ToString(RandomCueBreakSoundBox.SelectedValue);
            ResultSettings.RandomCueResumeSound =
                Convert.ToString(RandomCueResumeSoundBox.SelectedValue);
            ResultSettings.AiProvider = _selectedProvider;
            ResultSettings.AiModel = ModelBox.Text.Trim();
            var selectedCodexModel = CodexModelBox.SelectedItem as CodexModelOption;
            ResultSettings.CodexModel = selectedCodexModel == null
                ? string.Empty
                : selectedCodexModel.ModelId;
            var selectedCodexReasoning =
                CodexReasoningBox.SelectedItem as CodexReasoningEffortOption;
            ResultSettings.CodexReasoningEffort = selectedCodexReasoning == null
                ? string.Empty
                : selectedCodexReasoning.Effort;
            ResultSettings.MemoryEnabled = MemoryBox.IsChecked == true;
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
