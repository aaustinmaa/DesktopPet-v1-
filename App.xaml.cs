using System;
using System.IO;
using System.Threading;
using System.Windows;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class App : Application
    {
        private const string MutexName = @"Local\PixelHeartDesktopPet";
        private const string WakeEventName = @"Local\PixelHeartDesktopPet.Wake";
        private Mutex _singleInstanceMutex;
        private EventWaitHandle _wakeEvent;
        private Thread _wakeThread;
        private bool _ownsMutex;
        private volatile bool _isShuttingDown;

        protected override void OnStartup(StartupEventArgs e)
        {
            bool createdNew;
            _singleInstanceMutex = new Mutex(true, MutexName, out createdNew);
            _ownsMutex = createdNew;
            if (!createdNew)
            {
                if (!WakeExistingInstance())
                {
                    MessageBox.Show("苏无度已经在运行，但暂时无法唤醒。请双击桌面右下角托盘图标。",
                        "苏无度桌宠", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                Shutdown();
                return;
            }

            _wakeEvent = new EventWaitHandle(false, EventResetMode.AutoReset, WakeEventName);

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
            }
            MainWindow = window;
            window.Show();
            StartWakeListener();
        }

        private static bool WakeExistingInstance()
        {
            try
            {
                using (var wakeEvent = EventWaitHandle.OpenExisting(WakeEventName))
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

        private void StartWakeListener()
        {
            _wakeThread = new Thread(() =>
            {
                while (!_isShuttingDown)
                {
                    _wakeEvent.WaitOne();
                    if (_isShuttingDown) break;

                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        var window = MainWindow as MainWindow;
                        if (window != null)
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
                if (_wakeThread != null && _wakeThread.IsAlive)
                    _wakeThread.Join(500);
                _wakeEvent.Dispose();
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
