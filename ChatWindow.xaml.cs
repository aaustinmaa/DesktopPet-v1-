using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DesktopPet.Models;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class ChatWindow : Window
    {
        private AppSettings _settings;
        private readonly SecretService _secrets;
        private readonly MainWindow _petWindow;
        private readonly MemoryService _memoryService;
        private readonly ScreenCaptureService _screenCaptureService;
        private AiService _aiService;
        private bool _isSending;

        public ChatWindow(AppSettings settings, SecretService secrets, MainWindow petWindow)
        {
            InitializeComponent();
            _settings = settings;
            _secrets = secrets;
            _petWindow = petWindow;
            _memoryService = new MemoryService();
            _screenCaptureService = new ScreenCaptureService();
            _aiService = new AiService(_secrets, _settings, _memoryService);
            TitleText.Text = "和 " + _settings.PetName + " 聊聊";
            ModeText.Text = GetModeText();
            UpdateScreenVisionAvailability();
            LoadHistory();
            Closed += (s, e) => _aiService.Dispose();
            ConversationScroll.SizeChanged += (s, e) => UpdateBubbleWidths();
            Loaded += (s, e) =>
            {
                UpdateBubbleWidths();
                MessageBox.Focus();
            };
        }

        private string GetModeText()
        {
            switch ((_settings.AiProvider ?? string.Empty).ToLowerInvariant())
            {
                case "openai":
                    return _secrets.HasApiKey
                        ? "OpenAI API · " + _settings.AiModel
                        : "OpenAI API · 需要在设置中添加 API key";
                case "offline":
                    return "离线陪伴 · 不联网";
                default:
                    var model = string.IsNullOrWhiteSpace(_settings.CodexModel)
                        ? "自动模型"
                        : _settings.CodexModel;
                    var effort = string.IsNullOrWhiteSpace(_settings.CodexReasoningEffort)
                        ? "模型默认推理"
                        : _settings.CodexReasoningEffort + " 推理";
                    return "ChatGPT · " + model + " · " + effort;
            }
        }

        private void LoadHistory()
        {
            if (_settings.MemoryEnabled)
            {
                var history = _memoryService.GetRecentHistory(20);
                foreach (var item in history)
                {
                    var fromUser = item.Role == "user";
                    AddMessage(fromUser ? "你" : _settings.PetName,
                        item.Content, fromUser);
                }
                if (history.Count > 0)
                {
                    StatusText.Text = "已恢复最近聊天";
                    return;
                }
            }
            AddMessage(_settings.PetName, "我在这里。今天想聊点什么？", false);
            StatusText.Text = _settings.MemoryEnabled ? "聊天记忆已开启" : "聊天记忆已关闭";
        }

        private async void SendButton_Click(object sender, RoutedEventArgs e)
        {
            await SendCurrentMessageAsync();
        }

        private void SettingsButton_Click(object sender, RoutedEventArgs e)
        {
            var updatedSettings = _petWindow.OpenSettings(this);
            if (updatedSettings == null) return;

            _aiService.Dispose();
            _settings = updatedSettings;
            _aiService = new AiService(_secrets, _settings, _memoryService);
            TitleText.Text = "和 " + _settings.PetName + " 聊聊";
            ModeText.Text = GetModeText();
            UpdateScreenVisionAvailability();
            StatusText.Text = "设置已更新；下一条消息会使用新的聊天设置";
            MessageBox.Focus();
        }

        private void ScreenVisionToggle_Changed(object sender, RoutedEventArgs e)
        {
            if (ScreenVisionToggle == null || StatusText == null) return;
            var enabled = ScreenVisionToggle.IsChecked == true;
            if (enabled)
            {
                StatusText.Text =
                    "已开启：点击发送时截取一张所有显示器画面；不会持续录屏";
            }
            else if (ScreenVisionToggle.IsEnabled)
            {
                StatusText.Text = "屏幕不可见；只发送聊天文字";
            }
        }

        private void UpdateScreenVisionAvailability()
        {
            if (ScreenVisionToggle == null) return;
            var offline = string.Equals(
                _settings.AiProvider, "offline", StringComparison.OrdinalIgnoreCase);
            ScreenVisionToggle.IsEnabled = !offline;
            if (offline)
            {
                ScreenVisionToggle.IsChecked = false;
                ScreenVisionToggle.ToolTip = "离线模式不会向模型发送截图。";
            }
            else
            {
                ScreenVisionToggle.ToolTip =
                    "开启后，每次点击发送只截取一张所有显示器画面；不会持续录屏。";
            }
        }

        private async void MessageBox_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if ((e.Key == Key.Enter || e.Key == Key.Return) &&
                (Keyboard.Modifiers & ModifierKeys.Shift) == 0)
            {
                e.Handled = true;
                await SendCurrentMessageAsync();
            }
        }

        private async Task SendCurrentMessageAsync()
        {
            if (_isSending) return;
            var message = MessageBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(message)) return;

            _isSending = true;
            MessageBox.Clear();
            SendButton.IsEnabled = false;
            SettingsButton.IsEnabled = false;
            ScreenVisionToggle.IsEnabled = false;
            AddMessage("你", message, true);
            var includeScreen = ScreenVisionToggle.IsChecked == true;
            StatusText.Text = includeScreen
                ? "正在截取发送瞬间的屏幕…"
                : _settings.PetName + " 正在想…";
            _petWindow.SetPetState(PetState.Working, 0);
            string screenshotPath = null;

            try
            {
                if (includeScreen)
                {
                    screenshotPath = await CaptureScreenForMessageAsync();
                    StatusText.Text = _settings.PetName + " 正在看截图并思考…";
                }
                var reply = await _aiService.GetReplyAsync(message, screenshotPath);
                AddMessage(_settings.PetName, reply.Reply, false);
                _petWindow.ShowBubble(reply.Reply, 6);
                _petWindow.SetPetState(reply.Emotion, 6);
                if (string.Equals(reply.Action, "bounce", StringComparison.OrdinalIgnoreCase))
                    _petWindow.SetPetState(PetState.HeartPulse, 3);
                StatusText.Text = reply.ProviderLabel +
                    (includeScreen ? " · 已查看发送时截图" : string.Empty) +
                    (_settings.MemoryEnabled ? " · 已保存聊天" : string.Empty);
            }
            catch (Exception ex)
            {
                AddMessage("系统", ex.Message + "\n可以在苏无度的“设置 → AI 与记忆”中检查连接。", false, true);
                _petWindow.SetPetState(PetState.Error, 6);
                StatusText.Text = "请求失败";
            }
            finally
            {
                _screenCaptureService.DeleteCapture(screenshotPath);
                _isSending = false;
                SendButton.IsEnabled = true;
                SettingsButton.IsEnabled = true;
                UpdateScreenVisionAvailability();
                MessageBox.Focus();
            }
        }

        private async Task<string> CaptureScreenForMessageAsync()
        {
            Hide();
            try
            {
                // Give the desktop compositor time to reveal the window behind
                // the chat so the screenshot does not contain its own history.
                await Task.Delay(140);
                return await Task.Run(() =>
                    _screenCaptureService.CaptureVirtualDesktop());
            }
            finally
            {
                Show();
                Activate();
            }
        }

        private void AddMessage(string author, string message, bool fromUser, bool isError = false)
        {
            var border = new Border
            {
                Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
                    isError ? "#FFF2E8E7" : fromUser ? "#FF007175" : "#FFD9E8E6")),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(12, 9, 12, 9),
                Margin = new Thickness(fromUser ? 52 : 0, 5, fromUser ? 0 : 52, 5),
                HorizontalAlignment = fromUser ? HorizontalAlignment.Right : HorizontalAlignment.Left,
                MaxWidth = GetBubbleMaxWidth(),
                Tag = "ChatBubble"
            };
            var stack = new StackPanel();
            var header = new DockPanel();
            var copyButton = new Button
            {
                Content = "复制",
                Style = (Style)FindResource("BubbleCopyButtonStyle"),
                ToolTip = "复制这条消息",
                VerticalAlignment = VerticalAlignment.Center
            };
            copyButton.SetResourceReference(
                Control.ForegroundProperty,
                fromUser ? "LightTextBrush" : "InkBrush");
            copyButton.Click += (s, e) => CopyMessage(message);
            DockPanel.SetDock(copyButton, Dock.Right);
            header.Children.Add(copyButton);
            header.Children.Add(new TextBlock
            {
                Text = author,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
                    fromUser ? "#FFF7FBFA" : isError ? "#FF93625F" : "#FF007175")),
                FontWeight = FontWeights.SemiBold,
                FontSize = 11,
                Margin = new Thickness(0, 2, 0, 3),
                VerticalAlignment = VerticalAlignment.Center
            });
            stack.Children.Add(header);
            stack.Children.Add(new TextBlock
            {
                Text = message,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
                    fromUser ? "#FFF7FBFA" : "#FF284852")),
                TextWrapping = TextWrapping.Wrap,
                FontSize = 13
            });
            border.Child = stack;
            ConversationPanel.Children.Add(border);
            ConversationScroll.ScrollToEnd();
        }

        private void CopyMessage(string message)
        {
            if (string.IsNullOrEmpty(message)) return;

            try
            {
                Clipboard.SetText(message);
                StatusText.Text = "已复制这条消息";
            }
            catch (Exception ex)
            {
                StatusText.Text = "复制失败：" + ex.Message;
            }
        }

        private double GetBubbleMaxWidth()
        {
            var availableWidth = ConversationScroll.ActualWidth;
            if (availableWidth <= 0)
                return 330;

            // Keep compact windows readable while allowing wide and maximized
            // chat windows to use their horizontal space naturally.
            return Math.Max(280, Math.Min(1000, availableWidth * 0.86));
        }

        private void UpdateBubbleWidths()
        {
            var maxWidth = GetBubbleMaxWidth();
            foreach (var child in ConversationPanel.Children)
            {
                var bubble = child as Border;
                if (bubble != null && Equals(bubble.Tag, "ChatBubble"))
                    bubble.MaxWidth = maxWidth;
            }
        }
    }
}
