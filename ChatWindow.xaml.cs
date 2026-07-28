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
        private readonly AppSettings _settings;
        private readonly SecretService _secrets;
        private readonly MainWindow _petWindow;
        private readonly MemoryService _memoryService;
        private readonly AiService _aiService;
        private bool _isSending;

        public ChatWindow(AppSettings settings, SecretService secrets, MainWindow petWindow)
        {
            InitializeComponent();
            _settings = settings;
            _secrets = secrets;
            _petWindow = petWindow;
            _memoryService = new MemoryService();
            _aiService = new AiService(_secrets, _settings, _memoryService);
            TitleText.Text = "和 " + _settings.PetName + " 聊聊";
            ModeText.Text = GetModeText();
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

        private async void MessageBox_KeyDown(object sender, KeyEventArgs e)
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
            AddMessage("你", message, true);
            StatusText.Text = _settings.PetName + " 正在想…";
            _petWindow.SetPetState(PetState.Working, 0);

            try
            {
                var reply = await _aiService.GetReplyAsync(message);
                AddMessage(_settings.PetName, reply.Reply, false);
                _petWindow.ShowBubble(reply.Reply, 6);
                _petWindow.SetPetState(reply.Emotion, 6);
                if (string.Equals(reply.Action, "bounce", StringComparison.OrdinalIgnoreCase))
                    _petWindow.Bounce();
                StatusText.Text = reply.ProviderLabel +
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
                _isSending = false;
                SendButton.IsEnabled = true;
                MessageBox.Focus();
            }
        }

        private void AddMessage(string author, string message, bool fromUser, bool isError = false)
        {
            var border = new Border
            {
                Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
                    isError ? "#FF4A2228" : fromUser ? "#FF005F3B" : "#FF34303A")),
                CornerRadius = new CornerRadius(9),
                Padding = new Thickness(10, 8, 10, 8),
                Margin = new Thickness(fromUser ? 44 : 0, 4, fromUser ? 0 : 44, 4),
                HorizontalAlignment = fromUser ? HorizontalAlignment.Right : HorizontalAlignment.Left,
                MaxWidth = GetBubbleMaxWidth(),
                Tag = "ChatBubble"
            };
            var stack = new StackPanel();
            stack.Children.Add(new TextBlock
            {
                Text = author,
                Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#FF8FE6A7")),
                FontWeight = FontWeights.Bold,
                FontSize = 11,
                Margin = new Thickness(0, 0, 0, 3)
            });
            stack.Children.Add(new TextBlock
            {
                Text = message,
                Foreground = Brushes.White,
                TextWrapping = TextWrapping.Wrap,
                FontSize = 13
            });
            border.Child = stack;
            ConversationPanel.Children.Add(border);
            ConversationScroll.ScrollToEnd();
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
