using System;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class App : Application
    {
        private const string MutexName = @"Local\PixelHeartDesktopPet";
        private const string WakeEventName = @"Local\PixelHeartDesktopPet.Wake";
        private const string LauncherEventName = @"Local\PixelHeartDesktopPet.Launcher";
        private Mutex _singleInstanceMutex;
        private EventWaitHandle _wakeEvent;
        private EventWaitHandle _launcherEvent;
        private Thread _wakeThread;
        private bool _ownsMutex;
        private volatile bool _isShuttingDown;

        protected override void OnStartup(StartupEventArgs e)
        {
            RegisterTextInputCaretBehavior();
            var manualLaunch = Array.IndexOf(e.Args, "--startup") < 0 &&
                               Array.IndexOf(e.Args, "--background") < 0;
            try
            {
                NativeMethods.SetCurrentProcessExplicitAppUserModelID(
                    "SuWuDu.DesktopPet.Application");
            }
            catch
            {
                // Shell integration must never prevent the pet from starting.
            }
            StartShortcutRegistration();

            bool createdNew;
            _singleInstanceMutex = new Mutex(true, MutexName, out createdNew);
            _ownsMutex = createdNew;
            if (!createdNew)
            {
                if (!SignalExistingInstance(manualLaunch ? LauncherEventName : WakeEventName))
                {
                    MessageBox.Show("苏无度已经在运行，但暂时无法唤醒。请双击桌面右下角托盘图标。",
                        "苏无度桌宠", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                Shutdown();
                return;
            }

            _wakeEvent = new EventWaitHandle(false, EventResetMode.AutoReset, WakeEventName);
            _launcherEvent =
                new EventWaitHandle(false, EventResetMode.AutoReset, LauncherEventName);

            DispatcherUnhandledException += (sender, args) =>
            {
                LogError(args.Exception);
                MessageBox.Show("桌宠遇到了一个问题，已经写入日志：\n" + args.Exception.Message,
                    "苏无度桌宠", MessageBoxButton.OK, MessageBoxImage.Error);
                args.Handled = true;
            };

            AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
            {
                LogError(args.ExceptionObject as Exception);
            };

            base.OnStartup(e);
            var settingsService = new SettingsService();
            var window = new MainWindow(settingsService);
            if (Array.IndexOf(e.Args, "--preview") >= 0)
            {
                window.ShowInTaskbar = true;
                window.Title = "苏无度桌宠 Preview";
                window.Loaded += (sender, args) =>
                    window.ShowBubble("气泡测试：苏无度的大小不会改变，气泡区域可以鼠标穿透。", 10);
            }
            MainWindow = window;
            window.Show();
            if (manualLaunch)
                window.ShowLauncher();
            StartWakeListener();
        }

        private static void RegisterTextInputCaretBehavior()
        {
            EventManager.RegisterClassHandler(
                typeof(TextBox),
                UIElement.PreviewMouseLeftButtonDownEvent,
                new MouseButtonEventHandler(TextBox_PreviewMouseLeftButtonDown),
                true);
            EventManager.RegisterClassHandler(
                typeof(TextBox),
                Keyboard.GotKeyboardFocusEvent,
                new KeyboardFocusChangedEventHandler(TextBox_GotKeyboardFocus),
                true);
        }

        private static void TextBox_PreviewMouseLeftButtonDown(
            object sender,
            MouseButtonEventArgs e)
        {
            var textBox = sender as TextBox;
            if (textBox == null ||
                textBox.IsReadOnly ||
                !textBox.IsEnabled ||
                textBox.IsKeyboardFocusWithin)
                return;

            e.Handled = true;
            textBox.Focus();
            MoveCaretToEnd(textBox);
        }

        private static void TextBox_GotKeyboardFocus(
            object sender,
            KeyboardFocusChangedEventArgs e)
        {
            var textBox = sender as TextBox;
            if (textBox == null ||
                textBox.IsReadOnly ||
                !textBox.IsEnabled ||
                !textBox.IsKeyboardFocused)
                return;

            MoveCaretToEnd(textBox);
        }

        private static void MoveCaretToEnd(TextBox textBox)
        {
            textBox.CaretIndex = textBox.Text == null
                ? 0
                : textBox.Text.Length;
            textBox.SelectionLength = 0;
            textBox.ScrollToEnd();
        }

        private static bool SignalExistingInstance(string eventName)
        {
            try
            {
                using (var wakeEvent = EventWaitHandle.OpenExisting(eventName))
                {
                    return wakeEvent.Set();
                }
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
        }

        private static void StartShortcutRegistration()
        {
            var shortcutThread = new Thread(() =>
            {
                try
                {
                    ApplicationIntegrationService.EnsureStartMenuShortcut();
                }
                catch (Exception exception)
                {
                    LogError(exception);
                }
            })
            {
                IsBackground = true,
                Name = "SuWuDu.ShortcutRegistration"
            };
            shortcutThread.SetApartmentState(ApartmentState.STA);
            shortcutThread.Start();
        }

        private void StartWakeListener()
        {
            _wakeThread = new Thread(() =>
            {
                var handles = new WaitHandle[] { _wakeEvent, _launcherEvent };
                while (!_isShuttingDown)
                {
                    var signaled = WaitHandle.WaitAny(handles);
                    if (_isShuttingDown) break;
                    var requestedAction = signaled;

                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var window = MainWindow as MainWindow;
                        if (window == null) return;
                        if (requestedAction == 1)
                        {
                            window.WakeFromSecondLaunch();
                            window.ShowLauncher();
                        }
                        else
                            window.WakeFromSecondLaunch();
                    }));
                }
            })
            {
                IsBackground = true,
                Name = "DesktopPet.WakeListener"
            };
            _wakeThread.Start();
        }

        private static void LogError(Exception exception)
        {
            try
            {
                Directory.CreateDirectory(SettingsService.DataDirectory);
                File.AppendAllText(
                    Path.Combine(SettingsService.DataDirectory, "error.log"),
                    DateTime.Now.ToString("u") + Environment.NewLine +
                    (exception == null ? "Unknown error" : exception.ToString()) +
                    Environment.NewLine + Environment.NewLine);
            }
            catch
            {
                // Logging must never crash the pet.
            }
        }

        protected override void OnExit(ExitEventArgs e)
        {
            _isShuttingDown = true;
            if (_wakeEvent != null)
            {
                _wakeEvent.Set();
                _launcherEvent?.Set();
                if (_wakeThread != null && _wakeThread.IsAlive)
                    _wakeThread.Join(500);
                _wakeEvent.Dispose();
                _launcherEvent?.Dispose();
            }

            if (_singleInstanceMutex != null)
            {
                if (_ownsMutex)
                    _singleInstanceMutex.ReleaseMutex();
                _singleInstanceMutex.Dispose();
            }
            base.OnExit(e);
        }
    }
}
