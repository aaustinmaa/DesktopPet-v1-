using System;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
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
        private string _currentThreadId;
        private bool _isSending;
        private bool _isUpdatingScreenVisionToggle;
        private bool _archiveSectionExpanded;
        private bool _sidebarExpanded;

        public ChatWindow(AppSettings settings, SecretService secrets, MainWindow petWindow)
        {
            InitializeComponent();
            _settings = settings;
            _secrets = secrets;
            _petWindow = petWindow;
            _memoryService = MemoryService.Shared;
            _screenCaptureService = new ScreenCaptureService();

            _currentThreadId = _memoryService.CreateThread().Id;
            RecreateAiService();
            UpdateScreenVisionAvailability();
            RefreshThreadList();
            LoadCurrentThread();

            Closed += (sender, args) =>
            {
                _aiService.Dispose();
                _memoryService.RemoveThreadIfEmpty(_currentThreadId);
            };
            ConversationScroll.SizeChanged +=
                (sender, args) => UpdateBubbleWidths();
            Loaded += (sender, args) =>
            {
                UpdateBubbleWidths();
                MessageBox.Focus();
            };
        }

        private string GetModeText()
        {
            string mode;
            switch ((_settings.AiProvider ?? string.Empty).ToLowerInvariant())
            {
                case "openai":
                    mode = _secrets.HasApiKey
                        ? "OpenAI API · " + _settings.AiModel
                        : "OpenAI API · 需要在设置中添加 API key";
                    break;
                case "offline":
                    mode = "离线陪伴 · 不联网";
                    break;
                default:
                    var model = string.IsNullOrWhiteSpace(_settings.CodexModel)
                        ? "自动模型"
                        : _settings.CodexModel;
                    var effort = string.IsNullOrWhiteSpace(
                        _settings.CodexReasoningEffort)
                        ? "模型默认推理"
                        : _settings.CodexReasoningEffort + " 推理";
                    mode = "ChatGPT · " + model + " · " + effort;
                    break;
            }
            return mode + (_settings.MemoryEnabled
                ? " · 跨聊天记忆开启"
                : " · 仅使用当前聊天");
        }

        private void RecreateAiService()
        {
            _aiService?.Dispose();
            _aiService = new AiService(
                _secrets, _settings, _memoryService, _currentThreadId);
        }

        private void LoadCurrentThread()
        {
            var thread = _memoryService.GetThread(_currentThreadId);
            if (thread == null)
            {
                thread = _memoryService.CreateThread();
                _currentThreadId = thread.Id;
                RecreateAiService();
            }

            ConversationPanel.Children.Clear();
            foreach (var item in thread.Messages)
            {
                var fromUser = item.Role == "user";
                AddMessage(
                    fromUser ? "你" : _settings.PetName,
                    item.Content,
                    fromUser);
            }
            if (thread.Messages.Count == 0)
            {
                AddMessage(
                    _settings.PetName,
                    "我在这里。这个新聊天想从哪里开始？",
                    false);
                StatusText.Text = "新聊天 · 所有聊天都会自动保存在本机";
            }
            else
            {
                StatusText.Text = "已载入 " + thread.Messages.Count +
                    " 条消息" +
                    (_settings.MemoryEnabled ? " · 记忆功能已开启" : string.Empty);
            }
            if (thread.IsArchived)
                StatusText.Text += " · 继续发送会自动移回最近聊天";

            TitleText.Text = thread.Title;
            ModeText.Text = GetModeText();
            Title = "和 " + _settings.PetName + " 聊聊 · " + thread.Title;
            ArchiveCurrentButton.Content = thread.IsArchived ? "Restore" : "Archive";
            ArchiveCurrentButton.ToolTip = thread.IsArchived
                ? "把当前聊天移回最近聊天"
                : "把当前聊天移到归档";
            ConversationScroll.ScrollToEnd();
            UpdateBubbleWidths();
        }

        private void RefreshThreadList()
        {
            ActiveThreadsPanel.Children.Clear();
            ArchivedThreadsPanel.Children.Clear();

            var activeThreads = _memoryService.GetThreads(false);
            foreach (var thread in activeThreads)
                ActiveThreadsPanel.Children.Add(CreateThreadRow(thread));
            if (activeThreads.Count == 0)
            {
                ActiveThreadsPanel.Children.Add(new TextBlock
                {
                    Text = "还没有聊天",
                    Margin = new Thickness(8, 6, 0, 6),
                    Foreground = FindBrush("MutedBrush"),
                    FontSize = 11
                });
            }

            var archivedThreads = _memoryService.GetThreads(true);
            foreach (var thread in archivedThreads)
                ArchivedThreadsPanel.Children.Add(CreateThreadRow(thread));
            if (archivedThreads.Count == 0)
            {
                ArchivedThreadsPanel.Children.Add(new TextBlock
                {
                    Text = "归档为空",
                    Margin = new Thickness(8, 5, 0, 5),
                    Foreground = FindBrush("MutedBrush"),
                    FontSize = 11
                });
            }

            ArchivedToggleButton.Content =
                (_archiveSectionExpanded ? "⌄" : "›") +
                "  已归档  " + archivedThreads.Count;
            ArchivedThreadsPanel.Visibility = _archiveSectionExpanded
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        private Border CreateThreadRow(ChatThreadData thread)
        {
            var selected = string.Equals(
                thread.Id, _currentThreadId, StringComparison.OrdinalIgnoreCase);
            var border = new Border
            {
                Background = selected
                    ? FindBrush("AccentSoftBrush")
                    : Brushes.Transparent,
                BorderBrush = selected
                    ? FindBrush("BorderBrush")
                    : Brushes.Transparent,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(7),
                Margin = new Thickness(0, 2, 0, 2),
                Padding = new Thickness(2)
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            grid.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = GridLength.Auto
            });

            var titleStack = new StackPanel();
            titleStack.Children.Add(new TextBlock
            {
                Text = thread.Title,
                TextTrimming = TextTrimming.CharacterEllipsis,
                FontSize = 12,
                FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal
            });
            titleStack.Children.Add(new TextBlock
            {
                Text = FormatThreadTime(thread.UpdatedAtUtc),
                Margin = new Thickness(0, 2, 0, 0),
                FontSize = 10,
                Foreground = FindBrush("MutedBrush")
            });

            var selectButton = new Button
            {
                Tag = thread.Id,
                Content = titleStack,
                Style = (Style)FindResource("SidebarHeaderButtonStyle"),
                Foreground = CreateSidebarForeground(selected),
                Background = Brushes.Transparent,
                BorderBrush = Brushes.Transparent,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Margin = new Thickness(0),
                Padding = new Thickness(7, 5, 4, 5),
                ToolTip = thread.Summary
            };
            selectButton.Click += Thread_Click;
            grid.Children.Add(selectButton);

            var actionButton = new Button
            {
                Tag = thread.Id,
                Content = thread.IsArchived ? "Restore" : "Archive",
                Style = (Style)FindResource("CompactActionButtonStyle"),
                Padding = new Thickness(5, 2, 5, 2),
                MinHeight = 26,
                Margin = new Thickness(2, 4, 2, 4),
                FontSize = 10
            };
            Grid.SetColumn(actionButton, 1);
            if (thread.IsArchived)
                actionButton.Click += RestoreThread_Click;
            else
                actionButton.Click += ArchiveThread_Click;
            grid.Children.Add(actionButton);

            border.Child = grid;
            return border;
        }

        private SolidColorBrush CreateSidebarForeground(bool selected)
        {
            var source = (SolidColorBrush)FindResource(
                selected ? "AccentBrush" : "MutedBrush");
            return new SolidColorBrush(source.Color);
        }

        private void SidebarTextButton_MouseEnter(
            object sender,
            MouseEventArgs e)
        {
            var button = sender as Button;
            if (button == null) return;
            AnimateSidebarForeground(button, "AccentHoverBrush", 140);
        }

        private void SidebarTextButton_MouseLeave(
            object sender,
            MouseEventArgs e)
        {
            var button = sender as Button;
            if (button == null) return;
            var selected = !string.IsNullOrWhiteSpace(Convert.ToString(button.Tag)) &&
                string.Equals(
                    Convert.ToString(button.Tag),
                    _currentThreadId,
                    StringComparison.OrdinalIgnoreCase);
            AnimateSidebarForeground(
                button,
                selected ? "AccentBrush" : "MutedBrush",
                120);
        }

        private void AnimateSidebarForeground(
            Button button,
            string targetBrushKey,
            int durationMilliseconds)
        {
            var currentBrush = button.Foreground as SolidColorBrush;
            if (currentBrush == null || currentBrush.IsFrozen)
            {
                var startingColor = currentBrush == null
                    ? ((SolidColorBrush)FindResource("MutedBrush")).Color
                    : currentBrush.Color;
                currentBrush = new SolidColorBrush(startingColor);
                button.Foreground = currentBrush;
            }

            var targetColor =
                ((SolidColorBrush)FindResource(targetBrushKey)).Color;
            currentBrush.BeginAnimation(
                SolidColorBrush.ColorProperty,
                new ColorAnimation
                {
                    To = targetColor,
                    Duration = TimeSpan.FromMilliseconds(durationMilliseconds),
                    EasingFunction = new QuadraticEase
                    {
                        EasingMode = EasingMode.EaseOut
                    }
                },
                HandoffBehavior.SnapshotAndReplace);
        }

        private static string FormatThreadTime(string value)
        {
            DateTime date;
            if (!DateTime.TryParse(
                    value,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out date))
                return string.Empty;
            date = date.ToLocalTime();
            if (date.Date == DateTime.Today)
                return "今天 " + date.ToString("HH:mm");
            if (date.Date == DateTime.Today.AddDays(-1))
                return "昨天 " + date.ToString("HH:mm");
            return date.ToString("M月d日");
        }

        private Brush FindBrush(string key)
        {
            return (Brush)FindResource(key);
        }

        private void NewChat_Click(object sender, RoutedEventArgs e)
        {
            if (_isSending) return;
            var thread = _memoryService.CreateThread();
            SelectThread(thread.Id);
        }

        private void Thread_Click(object sender, RoutedEventArgs e)
        {
            if (_isSending) return;
            var button = sender as Button;
            SelectThread(Convert.ToString(button?.Tag));
        }

        private void SelectThread(string threadId)
        {
            if (string.IsNullOrWhiteSpace(threadId) ||
                _memoryService.GetThread(threadId) == null)
                return;
            if (!string.Equals(
                    threadId,
                    _currentThreadId,
                    StringComparison.OrdinalIgnoreCase))
                _memoryService.RemoveThreadIfEmpty(_currentThreadId);
            _currentThreadId = threadId;
            RecreateAiService();
            RefreshThreadList();
            LoadCurrentThread();
            MessageBox.Focus();
        }

        private void ArchiveCurrent_Click(object sender, RoutedEventArgs e)
        {
            if (_isSending) return;
            var current = _memoryService.GetThread(_currentThreadId);
            if (current == null) return;
            if (current.IsArchived)
            {
                _memoryService.SetArchived(current.Id, false);
                RefreshThreadList();
                LoadCurrentThread();
                return;
            }

            if (_memoryService.RemoveThreadIfEmpty(current.Id))
            {
                var emptyReplacement = _memoryService.CreateThread();
                SelectThread(emptyReplacement.Id);
                return;
            }
            _memoryService.SetArchived(current.Id, true);
            var next = _memoryService.CreateThread();
            SelectThread(next.Id);
        }

        private void ArchiveThread_Click(object sender, RoutedEventArgs e)
        {
            if (_isSending) return;
            var button = sender as Button;
            var threadId = Convert.ToString(button?.Tag);
            if (string.IsNullOrWhiteSpace(threadId)) return;
            _memoryService.SetArchived(threadId, true);
            if (string.Equals(
                    threadId,
                    _currentThreadId,
                    StringComparison.OrdinalIgnoreCase))
            {
                var next = _memoryService.CreateThread();
                SelectThread(next.Id);
            }
            else
            {
                RefreshThreadList();
            }
        }

        private void RestoreThread_Click(object sender, RoutedEventArgs e)
        {
            if (_isSending) return;
            var button = sender as Button;
            var threadId = Convert.ToString(button?.Tag);
            if (string.IsNullOrWhiteSpace(threadId)) return;
            _memoryService.SetArchived(threadId, false);
            SelectThread(threadId);
        }

        private void ArchivedToggle_Click(object sender, RoutedEventArgs e)
        {
            _archiveSectionExpanded = !_archiveSectionExpanded;
            RefreshThreadList();
        }

        private void SidebarToggle_Click(object sender, RoutedEventArgs e)
        {
            _sidebarExpanded = !_sidebarExpanded;
            SidebarColumn.Width = _sidebarExpanded
                ? new GridLength(238)
                : new GridLength(0);
            SidebarBorder.Visibility = _sidebarExpanded
                ? Visibility.Visible
                : Visibility.Collapsed;
            ExpandSidebarButton.Visibility = _sidebarExpanded
                ? Visibility.Collapsed
                : Visibility.Visible;
        }

        private void SettingsButton_Click(object sender, RoutedEventArgs e)
        {
            var updatedSettings = _petWindow.OpenSettings(this);
            if (updatedSettings == null) return;

            _settings = updatedSettings;
            if (_memoryService.GetThread(_currentThreadId) == null)
                _currentThreadId = _memoryService.CreateThread().Id;
            RecreateAiService();
            UpdateScreenVisionAvailability();
            RefreshThreadList();
            LoadCurrentThread();
            StatusText.Text = "设置已更新；下一条消息会使用新的聊天设置";
            MessageBox.Focus();
        }

        private void ScreenVisionToggle_Changed(object sender, RoutedEventArgs e)
        {
            if (ScreenVisionToggle == null || StatusText == null) return;
            var enabled = ScreenVisionToggle.IsChecked == true;
            if (!_isUpdatingScreenVisionToggle && _settings != null)
            {
                _settings.ScreenVisionEnabled = enabled;
                _petWindow.SetScreenVisionEnabled(enabled);
            }
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
            _isUpdatingScreenVisionToggle = true;
            try
            {
                ScreenVisionToggle.IsEnabled = !offline && !_isSending;
                ScreenVisionToggle.IsChecked =
                    offline ? false : _settings.ScreenVisionEnabled;
                ScreenVisionToggle.ToolTip = offline
                    ? "离线模式不会向模型发送截图。"
                    : "开启后，每次点击发送只截取一张所有显示器画面；不会持续录屏。";
            }
            finally
            {
                _isUpdatingScreenVisionToggle = false;
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

        private async void SendButton_Click(object sender, RoutedEventArgs e)
        {
            await SendCurrentMessageAsync();
        }

        private async Task SendCurrentMessageAsync()
        {
            if (_isSending) return;
            var message = MessageBox.Text.Trim();
            if (string.IsNullOrWhiteSpace(message)) return;

            _isSending = true;
            MessageBox.Clear();
            SetInteractionEnabled(false);
            AddMessage("你", message, true);
            var includeScreen = ScreenVisionToggle.IsChecked == true;
            StatusText.Text = includeScreen
                ? "正在截取发送瞬间的屏幕…"
                : _settings.PetName + " 正在想…";
            _petWindow.SetPetState(PetState.Working, 0);
            string screenshotPath = null;
            var messageRecordedByAiService = false;

            try
            {
                if (includeScreen)
                {
                    screenshotPath = await CaptureScreenForMessageAsync();
                    StatusText.Text = _settings.PetName + " 正在看截图并思考…";
                }

                var replyTask = _aiService.GetReplyAsync(message, screenshotPath);
                messageRecordedByAiService = true;
                RefreshThreadList();
                var updatedThread = _memoryService.GetThread(_currentThreadId);
                if (updatedThread != null)
                {
                    TitleText.Text = updatedThread.Title;
                    Title = "和 " + _settings.PetName + " 聊聊 · " +
                        updatedThread.Title;
                }

                var reply = await replyTask;
                AddMessage(_settings.PetName, reply.Reply, false);
                _petWindow.ShowBubble(reply.Reply, 6);
                _petWindow.SetPetState(reply.Emotion, 6);
                if (string.Equals(
                        reply.Action,
                        "bounce",
                        StringComparison.OrdinalIgnoreCase))
                    _petWindow.SetPetState(PetState.HeartPulse, 3);
                StatusText.Text = reply.ProviderLabel +
                    (includeScreen ? " · 已查看发送时截图" : string.Empty) +
                    (_settings.MemoryEnabled ? " · 记忆已开启" : string.Empty) +
                    " · 已保存聊天";
            }
            catch (Exception exception)
            {
                if (!messageRecordedByAiService)
                    _memoryService.RecordUserMessage(_currentThreadId, message);
                AddMessage(
                    "系统",
                    exception.Message +
                    "\n可以在苏无度的“设置 → AI 与记忆”中检查连接。",
                    false,
                    true);
                _petWindow.SetPetState(PetState.Error, 6);
                StatusText.Text = "请求失败 · 你的消息仍已保存";
            }
            finally
            {
                _screenCaptureService.DeleteCapture(screenshotPath);
                _isSending = false;
                SetInteractionEnabled(true);
                UpdateScreenVisionAvailability();
                RefreshThreadList();
                MessageBox.Focus();
            }
        }

        private void SetInteractionEnabled(bool enabled)
        {
            SendButton.IsEnabled = enabled;
            SettingsButton.IsEnabled = enabled;
            ArchiveCurrentButton.IsEnabled = enabled;
            SidebarBorder.IsEnabled = enabled;
            ExpandSidebarButton.IsEnabled = enabled;
            MessageBox.IsEnabled = enabled;
            ScreenVisionToggle.IsEnabled = enabled;
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

        private void AddMessage(
            string author,
            string message,
            bool fromUser,
            bool isError = false)
        {
            var border = new Border
            {
                Background = new SolidColorBrush(
                    (Color)ColorConverter.ConvertFromString(
                        isError
                            ? "#FFF2E8E7"
                            : fromUser
                                ? "#FF007175"
                                : "#FFD9E8E6")),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(12, 9, 12, 9),
                Margin = new Thickness(
                    fromUser ? 52 : 0,
                    5,
                    fromUser ? 0 : 52,
                    5),
                HorizontalAlignment = fromUser
                    ? HorizontalAlignment.Right
                    : HorizontalAlignment.Left,
                MaxWidth = GetBubbleMaxWidth(),
                Tag = "ChatBubble"
            };
            var stack = new StackPanel();
            var header = new DockPanel();
            var copyButton = new Button
            {
                Style = (Style)FindResource(
                    fromUser
                        ? "BubbleCopyButtonOnDarkStyle"
                        : "BubbleCopyButtonStyle"),
                Content = "Copy",
                ToolTip = "复制这条消息"
            };
            copyButton.Click += (sender, args) => CopyMessage(message);
            DockPanel.SetDock(copyButton, Dock.Right);
            header.Children.Add(copyButton);
            header.Children.Add(new TextBlock
            {
                Text = author,
                Foreground = new SolidColorBrush(
                    (Color)ColorConverter.ConvertFromString(
                        fromUser
                            ? "#FFF7FBFA"
                            : isError
                                ? "#FF93625F"
                                : "#FF007175")),
                FontWeight = FontWeights.SemiBold,
                FontSize = 11,
                Margin = new Thickness(0, 2, 0, 3),
                VerticalAlignment = VerticalAlignment.Center
            });
            stack.Children.Add(header);
            stack.Children.Add(new TextBlock
            {
                Text = message,
                Foreground = new SolidColorBrush(
                    (Color)ColorConverter.ConvertFromString(
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
            catch (Exception exception)
            {
                StatusText.Text = "复制失败：" + exception.Message;
            }
        }

        private double GetBubbleMaxWidth()
        {
            var availableWidth = ConversationScroll.ActualWidth;
            if (availableWidth <= 0)
                return 430;
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
