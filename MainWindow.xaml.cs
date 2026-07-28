using System;
using System.ComponentModel;
using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using DesktopPet.Models;
using DesktopPet.Services;
using Forms = System.Windows.Forms;

namespace DesktopPet
{
    public partial class MainWindow : Window
    {
        private const double SpeechBubbleHeight = 96;
        private const double SpeechBubbleTailOverlap = 6;
        private readonly SettingsService _settingsService;
        private readonly SecretService _secretService = new SecretService();
        private readonly CommandService _commandService = new CommandService();
        private readonly SoundService _soundService = new SoundService();
        private AppSettings _settings;
        private SpriteAnimator _animator;
        private Forms.NotifyIcon _trayIcon;
        private readonly Random _random = new Random();
        private readonly DispatcherTimer _behaviorTimer = new DispatcherTimer();
        private readonly DispatcherTimer _hydrationTimer = new DispatcherTimer();
        private readonly DispatcherTimer _focusTimer = new DispatcherTimer();
        private readonly DispatcherTimer _commandTimer = new DispatcherTimer();
        private readonly DispatcherTimer _bubbleTimer = new DispatcherTimer();
        private DateTime? _focusEnds;
        private DateTime? _nextRandomCueAt;
        private DateTime? _randomCueBreakEndsAt;
        private bool _workingMode;
        private bool _clickThrough;
        private bool _allowExit;
        private IntPtr _windowHandle;
        private HwndSource _source;
        private SpeechBubbleWindow _speechBubbleWindow;

        public MainWindow(SettingsService settingsService)
        {
            InitializeComponent();
            _settingsService = settingsService;
            _settings = _settingsService.Load();

            Loaded += MainWindow_Loaded;
            SourceInitialized += MainWindow_SourceInitialized;
            Closing += MainWindow_Closing;
            LocationChanged += (s, e) =>
            {
                SaveWindowPosition();
                PositionSpeechBubble();
            };
            SizeChanged += (s, e) => PositionSpeechBubble();

            _behaviorTimer.Interval = TimeSpan.FromSeconds(8);
            _behaviorTimer.Tick += BehaviorTimer_Tick;
            _hydrationTimer.Tick += HydrationTimer_Tick;
            _focusTimer.Interval = TimeSpan.FromSeconds(1);
            _focusTimer.Tick += FocusTimer_Tick;
            _commandTimer.Interval = TimeSpan.FromSeconds(1);
            _commandTimer.Tick += CommandTimer_Tick;
            _bubbleTimer.Tick += (s, e) =>
            {
                _bubbleTimer.Stop();
                HideSpeechBubble();
            };
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            ApplySettings();
            RestoreWindowPosition();
            _animator = new SpriteAnimator(PetImage);
            CreateSpeechBubbleWindow();
            CreateTrayIcon();
            ConfigureHydrationTimer();
            _behaviorTimer.Start();
            _commandTimer.Start();

            if (!_settings.FirstRunComplete)
            {
                _settings.FirstRunComplete = true;
                _settingsService.Save(_settings);
                ShowBubble("你好，我是" + _settings.PetName + "！双击我聊天，右键查看更多功能。", 7);
                _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(4));
            }
        }

        private void MainWindow_SourceInitialized(object sender, EventArgs e)
        {
            _windowHandle = new WindowInteropHelper(this).Handle;
            _source = HwndSource.FromHwnd(_windowHandle);
            if (_source != null) _source.AddHook(WindowMessageHook);
            NativeMethods.RegisterHotKey(_windowHandle, NativeMethods.HotkeyId,
                NativeMethods.ModAlt | NativeMethods.ModControl, NativeMethods.VkP);
        }

        private IntPtr WindowMessageHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == NativeMethods.WmHotkey && wParam.ToInt32() == NativeMethods.HotkeyId)
            {
                ToggleClickThrough(false);
                if (!IsVisible) ShowFromTray();
                handled = true;
            }
            return IntPtr.Zero;
        }

        private void ApplySettings()
        {
            _settings.Normalize();
            Width = 210 * _settings.PetScale;
            Height = 238 * _settings.PetScale;
            Topmost = _settings.Topmost;
            if (_speechBubbleWindow != null)
            {
                _speechBubbleWindow.Topmost = _settings.Topmost;
                PositionSpeechBubble();
            }
            TopmostItem.IsChecked = _settings.Topmost;
            WanderItem.IsChecked = _settings.AutoWander;
            if (StartupService.IsEnabled() != _settings.StartWithWindows)
                StartupService.SetEnabled(_settings.StartWithWindows);
            ConfigureHydrationTimer();
            ApplyRandomCueSettings();
        }

        private void RestoreWindowPosition()
        {
            if (IsVisiblePosition(_settings.WindowLeft, _settings.WindowTop))
            {
                Left = _settings.WindowLeft;
                Top = _settings.WindowTop;
            }
            else
            {
                var workArea = SystemParameters.WorkArea;
                Left = workArea.Right - Width - 24;
                Top = workArea.Bottom - Height - 18;
            }
            KeepOnScreen();
        }

        private bool IsVisiblePosition(double left, double top)
        {
            if (double.IsNaN(left) || double.IsNaN(top)) return false;
            return left + 40 > SystemParameters.VirtualScreenLeft &&
                   top + 40 > SystemParameters.VirtualScreenTop &&
                   left < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 20 &&
                   top < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 20;
        }

        private void SaveWindowPosition()
        {
            if (!IsLoaded || double.IsNaN(Left) || double.IsNaN(Top)) return;
            _settings.WindowLeft = Left;
            _settings.WindowTop = Top;
        }

        private void ConfigureHydrationTimer()
        {
            _hydrationTimer.Stop();
            if (_settings == null || !_settings.HydrationEnabled) return;
            _hydrationTimer.Interval = TimeSpan.FromMinutes(_settings.HydrationMinutes);
            _hydrationTimer.Start();
        }

        private void BehaviorTimer_Tick(object sender, EventArgs e)
        {
            if (_workingMode || _focusEnds.HasValue) return;
            if (NativeMethods.GetSystemIdleTime() > TimeSpan.FromMinutes(5))
            {
                _animator.SetState(PetState.Sleeping);
                return;
            }

            if (_animator.CurrentState == PetState.Sleeping)
            {
                _animator.SetState(PetState.Idle);
                ShowBubble("欢迎回来。", 3);
            }

            var choice = _random.Next(5);
            if (choice == 0) _animator.SetState(PetState.Blinking, TimeSpan.FromSeconds(2));
            else if (choice == 1) _animator.SetState(PetState.HeartPulse, TimeSpan.FromSeconds(3));
            else if (choice == 2) _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(3));

            if (_settings.AutoWander && _random.NextDouble() < 0.45)
                Wander();
        }

        private void Wander()
        {
            var work = SystemParameters.WorkArea;
            var minimumTop = work.Top + SpeechBubbleHeight - SpeechBubbleTailOverlap;
            var targetLeft = Math.Max(work.Left, Math.Min(work.Right - Width,
                Left + _random.Next(-100, 101)));
            var targetTop = Math.Max(minimumTop, Math.Min(work.Bottom - Height,
                Top + _random.Next(-40, 41)));
            var duration = new Duration(TimeSpan.FromSeconds(1.4));
            var leftAnimation = new DoubleAnimation(targetLeft, duration)
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
            };
            var topAnimation = new DoubleAnimation(targetTop, duration)
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }
            };
            leftAnimation.Completed += (s, e) =>
            {
                BeginAnimation(LeftProperty, null);
                BeginAnimation(TopProperty, null);
                Left = targetLeft;
                Top = targetTop;
                SaveWindowPosition();
            };
            BeginAnimation(LeftProperty, leftAnimation);
            BeginAnimation(TopProperty, topAnimation);
        }

        private void HydrationTimer_Tick(object sender, EventArgs e)
        {
            Notify("喝水时间", "休息一下，喝几口水吧。");
            _animator.SetState(PetState.Reminder, TimeSpan.FromSeconds(6));
            ShowBubble("喝水时间到啦！让眼睛也离开屏幕一会儿。", 7);
        }

        private void StartFocus_Click(object sender, RoutedEventArgs e)
        {
            var now = DateTime.Now;
            _focusEnds = now.AddMinutes(_settings.FocusMinutes);
            ResetRandomCues();
            ScheduleNextRandomCue(now);
            StopFocusItem.IsEnabled = true;
            _focusTimer.Start();
            _animator.SetState(PetState.Working);
            _soundService.PlayFocusStart(_settings.FocusStartSound);
            ShowBubble("专注 " + _settings.FocusMinutes + " 分钟，开始！我陪你一起。", 5);
        }

        private void FocusTimer_Tick(object sender, EventArgs e)
        {
            if (!_focusEnds.HasValue) return;
            var now = DateTime.Now;
            var remaining = _focusEnds.Value - now;
            if (remaining <= TimeSpan.Zero)
            {
                _focusTimer.Stop();
                _focusEnds = null;
                ResetRandomCues();
                StopFocusItem.IsEnabled = false;
                _animator.SetState(PetState.Success, TimeSpan.FromSeconds(8));
                _soundService.PlayFocusComplete(_settings.FocusCompleteSound);
                Notify("专注完成", "做得好！起来活动一下吧。");
                ShowBubble("专注完成！做得好，起来活动一下吧。", 8);
                return;
            }

            ProcessRandomCues(now);
        }

        private void StopFocus_Click(object sender, RoutedEventArgs e)
        {
            _focusTimer.Stop();
            _focusEnds = null;
            ResetRandomCues();
            StopFocusItem.IsEnabled = false;
            if (!_workingMode) _animator.SetState(PetState.Idle);
            ShowBubble("计时已停止。随时都可以重新开始。", 4);
        }

        private void ApplyRandomCueSettings()
        {
            if (!_focusEnds.HasValue) return;

            if (!_settings.RandomCueEnabled)
            {
                var wasTakingBreak = _randomCueBreakEndsAt.HasValue;
                ResetRandomCues();
                if (wasTakingBreak && _animator != null)
                    _animator.SetState(PetState.Working);
                return;
            }

            if (!_randomCueBreakEndsAt.HasValue)
                ScheduleNextRandomCue(DateTime.Now);
        }

        private void ScheduleNextRandomCue(DateTime now)
        {
            _nextRandomCueAt = null;
            if (!_settings.RandomCueEnabled || !_focusEnds.HasValue ||
                _randomCueBreakEndsAt.HasValue)
                return;

            var minimumSeconds = _settings.RandomCueMinMinutes * 60;
            var maximumSeconds = _settings.RandomCueMaxMinutes * 60;
            var randomSeconds = _random.Next(minimumSeconds, maximumSeconds + 1);
            var candidate = now.AddSeconds(randomSeconds);
            var breakWouldEndAt =
                candidate.AddSeconds(_settings.RandomCueBreakSeconds);
            if (breakWouldEndAt < _focusEnds.Value)
                _nextRandomCueAt = candidate;
        }

        private void ProcessRandomCues(DateTime now)
        {
            if (!_settings.RandomCueEnabled) return;

            if (_randomCueBreakEndsAt.HasValue)
            {
                if (now < _randomCueBreakEndsAt.Value) return;

                _randomCueBreakEndsAt = null;
                _soundService.PlayRandomResume(_settings.RandomCueResumeSound);
                _animator.SetState(PetState.Working);
                ShowBubble("微休息结束，听到第二声就继续工作吧。", 4);
                ScheduleNextRandomCue(now);
                return;
            }

            if (!_nextRandomCueAt.HasValue || now < _nextRandomCueAt.Value) return;

            _nextRandomCueAt = null;
            _randomCueBreakEndsAt = now.AddSeconds(_settings.RandomCueBreakSeconds);
            _soundService.PlayRandomBreak(_settings.RandomCueBreakSound);
            _animator.SetState(PetState.Reminder);
            ShowBubble(
                "第一声：休息 " + _settings.RandomCueBreakSeconds +
                " 秒。听到第二声再继续工作。",
                _settings.RandomCueBreakSeconds + 1);
        }

        private void ResetRandomCues()
        {
            _nextRandomCueAt = null;
            _randomCueBreakEndsAt = null;
        }

        private void CommandTimer_Tick(object sender, EventArgs e)
        {
            var command = _commandService.TryRead();
            if (command == null) return;
            var state = AiService.ParseState(command.State);
            _animator.SetState(state, state == PetState.Working || state == PetState.Sleeping
                ? (TimeSpan?)null
                : TimeSpan.FromSeconds(6));
            if (!string.IsNullOrWhiteSpace(command.Message))
                ShowBubble(command.Message, 6);
        }

        private void PetImage_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount >= 2)
            {
                OpenChat();
                e.Handled = true;
                return;
            }

            try
            {
                DragMove();
                KeepOnScreen();
                SaveWindowPosition();
            }
            catch (InvalidOperationException) { }
            Bounce();
        }

        private void PetImage_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
        {
            PetMenu.IsOpen = true;
            e.Handled = true;
        }

        public void Bounce()
        {
            var up = new DoubleAnimationUsingKeyFrames();
            up.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.Zero)));
            up.KeyFrames.Add(new EasingDoubleKeyFrame(-12, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(130))));
            up.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(360))));
            PetTranslate.BeginAnimation(System.Windows.Media.TranslateTransform.YProperty, up);

            var squashX = new DoubleAnimationUsingKeyFrames();
            squashX.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.Zero)));
            squashX.KeyFrames.Add(new EasingDoubleKeyFrame(1.08, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(100))));
            squashX.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(360))));
            PetBounceScale.BeginAnimation(System.Windows.Media.ScaleTransform.ScaleXProperty, squashX);
        }

        public void ShowBubble(string message, int seconds = 5)
        {
            if (string.IsNullOrWhiteSpace(message)) return;
            if (_speechBubbleWindow == null)
                CreateSpeechBubbleWindow();
            _speechBubbleWindow.SetMessage(message);
            PositionSpeechBubble();
            if (IsVisible && !_speechBubbleWindow.IsVisible)
                _speechBubbleWindow.Show();
            _bubbleTimer.Stop();
            _bubbleTimer.Interval = TimeSpan.FromSeconds(seconds);
            _bubbleTimer.Start();
        }

        private void CreateSpeechBubbleWindow()
        {
            if (_speechBubbleWindow != null) return;
            _speechBubbleWindow = new SpeechBubbleWindow
            {
                Owner = this,
                Topmost = Topmost,
                ShowInTaskbar = ShowInTaskbar,
                Title = ShowInTaskbar ? "苏无度气泡 Preview" : "苏无度气泡"
            };
            PositionSpeechBubble();
        }

        private void PositionSpeechBubble()
        {
            if (_speechBubbleWindow == null || double.IsNaN(Left) || double.IsNaN(Top))
                return;

            _speechBubbleWindow.Width = Math.Max(184, Width);
            _speechBubbleWindow.Left = Left + (Width - _speechBubbleWindow.Width) / 2;
            _speechBubbleWindow.Top = Top - _speechBubbleWindow.Height + SpeechBubbleTailOverlap;
        }

        private void HideSpeechBubble()
        {
            if (_speechBubbleWindow != null && _speechBubbleWindow.IsVisible)
                _speechBubbleWindow.Hide();
        }

        public void SetPetState(PetState state, int revertAfterSeconds = 5)
        {
            if (_animator == null) return;
            _animator.SetState(state,
                state == PetState.Working || state == PetState.Sleeping || revertAfterSeconds <= 0
                    ? (TimeSpan?)null
                    : TimeSpan.FromSeconds(revertAfterSeconds));
        }

        private void Cheer_Click(object sender, RoutedEventArgs e)
        {
            var cheers = new[]
            {
                "你不需要一次解决所有事，只要完成眼前这一小步。",
                "我看到你在努力。休息不是后退，是补充能量。",
                "今天已经做得很好啦，剩下的我们慢慢来。",
                "这个红心是给你的。继续加油！"
            };
            ShowBubble(cheers[_random.Next(cheers.Length)], 6);
            _animator.SetState(PetState.HeartPulse, TimeSpan.FromSeconds(5));
            Bounce();
        }

        private void Chat_Click(object sender, RoutedEventArgs e) => OpenChat();

        private void OpenChat()
        {
            ToggleClickThrough(false);
            var chat = new ChatWindow(_settings, _secretService, this)
            {
                Owner = this,
                Topmost = Topmost
            };
            chat.Show();
            _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(3));
        }

        private void WorkMode_Click(object sender, RoutedEventArgs e)
        {
            _workingMode = WorkModeItem.IsChecked;
            _animator.SetState(_workingMode ? PetState.Working : PetState.Idle);
            ShowBubble(_workingMode ? "工作模式启动。我会安静陪你。" : "工作完成了吗？辛苦啦。", 4);
        }

        private void Wander_Click(object sender, RoutedEventArgs e)
        {
            _settings.AutoWander = WanderItem.IsChecked;
            _settingsService.Save(_settings);
            if (_settings.AutoWander) Wander();
        }

        private void Topmost_Click(object sender, RoutedEventArgs e)
        {
            _settings.Topmost = TopmostItem.IsChecked;
            Topmost = _settings.Topmost;
            if (_speechBubbleWindow != null)
                _speechBubbleWindow.Topmost = _settings.Topmost;
            _settingsService.Save(_settings);
        }

        private void ClickThrough_Click(object sender, RoutedEventArgs e)
        {
            ToggleClickThrough(ClickThroughItem.IsChecked);
        }

        private void ToggleClickThrough(bool enabled)
        {
            if (_windowHandle == IntPtr.Zero) return;
            _clickThrough = enabled;
            ClickThroughItem.IsChecked = enabled;
            var style = NativeMethods.GetWindowLong(_windowHandle, NativeMethods.GwlExStyle);
            if (enabled) style |= NativeMethods.WsExTransparent;
            else style &= ~NativeMethods.WsExTransparent;
            NativeMethods.SetWindowLong(_windowHandle, NativeMethods.GwlExStyle, style);
            if (enabled)
            {
                ShowBubble("鼠标穿透已开启。按 Ctrl+Alt+P 或托盘菜单恢复。", 5);
                _trayIcon.ShowBalloonTip(3000, "鼠标穿透已开启",
                    "按 Ctrl+Alt+P 可随时恢复交互。", Forms.ToolTipIcon.Info);
            }
        }

        private void Size_Click(object sender, RoutedEventArgs e)
        {
            var item = sender as MenuItem;
            double scale;
            if (item != null && double.TryParse(Convert.ToString(item.Tag),
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out scale))
            {
                _settings.PetScale = scale;
                ApplySettings();
                KeepOnScreen();
                _settingsService.Save(_settings);
            }
        }

        private void KeepOnScreen()
        {
            var work = SystemParameters.WorkArea;
            var minimumTop = work.Top + SpeechBubbleHeight - SpeechBubbleTailOverlap;
            Left = Math.Max(work.Left, Math.Min(Left, work.Right - Width));
            Top = Math.Max(minimumTop, Math.Min(Top, work.Bottom - Height));
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            OpenSettings(this);
        }

        internal AppSettings OpenSettings(Window owner)
        {
            ToggleClickThrough(false);
            var dialog = new SettingsWindow(_settings.Clone(), _secretService)
            {
                Owner = owner ?? this,
                Topmost = Topmost
            };
            if (dialog.ShowDialog() == true)
            {
                _settings = dialog.ResultSettings;
                _settingsService.Save(_settings);
                ApplySettings();
                KeepOnScreen();
                ShowBubble("设置保存好了。", 3);
                return _settings.Clone();
            }
            return null;
        }

        private void Help_Click(object sender, RoutedEventArgs e)
        {
            ToggleClickThrough(false);
            var help = new HelpWindow
            {
                Owner = this,
                Topmost = Topmost
            };
            help.Show();
        }

        private void TuckAway_Click(object sender, RoutedEventArgs e)
        {
            HideSpeechBubble();
            Hide();
            _trayIcon.ShowBalloonTip(2500, "桌宠已收起来",
                "双击托盘图标可以把我叫回来。", Forms.ToolTipIcon.Info);
        }

        private void Exit_Click(object sender, RoutedEventArgs e) => ExitApplication();

        private void CreateTrayIcon()
        {
            _trayIcon = new Forms.NotifyIcon
            {
                Text = "苏无度桌宠",
                Visible = true
            };
            var iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "app.ico");
            try
            {
                _trayIcon.Icon = File.Exists(iconPath) ? new Icon(iconPath) : SystemIcons.Application;
            }
            catch (ArgumentException)
            {
                _trayIcon.Icon = SystemIcons.Application;
            }
            _trayIcon.DoubleClick += (s, e) => Dispatcher.Invoke(ShowFromTray);

            var menu = new Forms.ContextMenuStrip();
            menu.Items.Add("叫醒桌宠", null, (s, e) => Dispatcher.Invoke(ShowFromTray));
            menu.Items.Add("聊聊天", null, (s, e) => Dispatcher.Invoke(OpenChat));
            menu.Items.Add("恢复鼠标交互 (Ctrl+Alt+P)", null,
                (s, e) => Dispatcher.Invoke(() => ToggleClickThrough(false)));
            menu.Items.Add("开始专注", null, (s, e) => Dispatcher.Invoke(() => StartFocus_Click(s, null)));
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("使用说明书", null, (s, e) => Dispatcher.Invoke(() => Help_Click(s, null)));
            menu.Items.Add("设置", null, (s, e) => Dispatcher.Invoke(() => Settings_Click(s, null)));
            menu.Items.Add("退出", null, (s, e) => Dispatcher.Invoke(ExitApplication));
            _trayIcon.ContextMenuStrip = menu;
        }

        private void ShowFromTray()
        {
            ToggleClickThrough(false);
            Show();
            WindowState = WindowState.Normal;
            Activate();
            Topmost = _settings.Topmost;
            _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(3));
        }

        public void WakeFromSecondLaunch()
        {
            if (!IsLoaded)
            {
                RoutedEventHandler loadedHandler = null;
                loadedHandler = (sender, args) =>
                {
                    Loaded -= loadedHandler;
                    WakeFromSecondLaunch();
                };
                Loaded += loadedHandler;
                return;
            }

            ToggleClickThrough(false);
            if (!IsVisible) Show();
            WindowState = WindowState.Normal;

            if (!IsVisiblePosition(Left, Top))
            {
                var workArea = SystemParameters.WorkArea;
                Left = workArea.Right - Width - 24;
                Top = workArea.Bottom - Height - 18;
            }

            Activate();
            Topmost = true;
            Dispatcher.BeginInvoke(new Action(() =>
            {
                Topmost = _settings.Topmost;
                Activate();
            }), DispatcherPriority.ApplicationIdle);

            ShowBubble("我回来啦！", 3);
            if (_animator != null)
                _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(3));
        }

        private void Notify(string title, string message)
        {
            if (!IsVisible) Show();
            _trayIcon.ShowBalloonTip(5000, title, message, Forms.ToolTipIcon.Info);
        }

        private void MainWindow_Closing(object sender, CancelEventArgs e)
        {
            SaveWindowPosition();
            try { _settingsService.Save(_settings); } catch { }
            if (!_allowExit)
            {
                _allowExit = true;
            }
            Cleanup();
        }

        private void ExitApplication()
        {
            _allowExit = true;
            Close();
            Application.Current.Shutdown();
        }

        private void Cleanup()
        {
            _behaviorTimer.Stop();
            _hydrationTimer.Stop();
            _focusTimer.Stop();
            _commandTimer.Stop();
            _bubbleTimer.Stop();
            if (_speechBubbleWindow != null)
            {
                _speechBubbleWindow.Close();
                _speechBubbleWindow = null;
            }
            if (_animator != null) _animator.Dispose();
            _soundService.Dispose();
            if (_source != null) _source.RemoveHook(WindowMessageHook);
            if (_windowHandle != IntPtr.Zero)
                NativeMethods.UnregisterHotKey(_windowHandle, NativeMethods.HotkeyId);
            if (_trayIcon != null)
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
            }
        }
    }
}
