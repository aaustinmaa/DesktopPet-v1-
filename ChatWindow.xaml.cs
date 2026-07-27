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
        private readonly AiService _aiService;
        private bool _isSending;

        public ChatWindow(AppSettings settings, SecretService secrets, MainWindow petWindow)
        {
            InitializeComponent();
            _settings = settings;
            _secrets = secrets;
            _petWindow = petWindow;
            _aiService = new AiService(_secrets, _settings);
            TitleText.Text = "和 " + _settings.PetName + " 聊聊";
            ModeText.Text = _secrets.HasApiKey
                ? "AI 模式 · " + _settings.AiModel
                : "离线陪伴模式 · 在设置中添加 API key 可启用 AI";
            AddMessage(_settings.PetName, "我在这里。今天想聊点什么？", false);
            Loaded += (s, e) => MessageBox.Focus();
        }

        private async void SendButton_Click(object sender, RoutedEventArgs e)
        {
            await SendCurrentMessageAsync();
        }

        private async void MessageBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0)
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
                StatusText.Text = reply.IsOffline ? "离线回复" : "AI 回复";
            }
            catch (Exception ex)
            {
                AddMessage("系统", ex.Message + "\n可以在设置中检查 API key 和模型名称。", false, true);
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
                MaxWidth = 330
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
    }
}
