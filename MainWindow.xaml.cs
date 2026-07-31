using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
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
        private static readonly TimeSpan FocusStateCheckpointInterval =
            TimeSpan.FromSeconds(5);
        private readonly SettingsService _settingsService;
        private readonly SecretService _secretService = new SecretService();
        private readonly CommandService _commandService = new CommandService();
        private readonly SoundService _soundService = new SoundService();
        private readonly FocusJournalService _focusJournalService =
            FocusJournalService.Shared;
        private readonly ActiveFocusStateService _activeFocusStateService =
            new ActiveFocusStateService();
        private AppSettings _settings;
        private SpriteAnimator _animator;
        private HammerAnimator _hammerAnimator;
        private Forms.NotifyIcon _trayIcon;
        private readonly Random _random = new Random();
        private readonly DispatcherTimer _behaviorTimer = new DispatcherTimer();
        private readonly DispatcherTimer _specialActionTimer = new DispatcherTimer();
        private readonly DispatcherTimer _hydrationTimer = new DispatcherTimer();
        private readonly DispatcherTimer _focusTimer = new DispatcherTimer();
        private readonly DispatcherTimer _focusCountdownTimer = new DispatcherTimer();
        private readonly DispatcherTimer _commandTimer = new DispatcherTimer();
        private readonly DispatcherTimer _bubbleTimer = new DispatcherTimer();
        private readonly DispatcherTimer _doubleClickTimer = new DispatcherTimer();
        private readonly List<FocusTimeSegment> _activeFocusSegments =
            new List<FocusTimeSegment>();
        private DateTime? _focusEnds;
        private DateTime? _activeFocusStartedAt;
        private DateTime? _activeFocusSegmentStartedAt;
        private DateTime _lastFocusStateSavedAt = DateTime.MinValue;
        private int _activeFocusPlannedMinutes;
        private DateTime? _nextRandomCueAt;
        private DateTime? _randomCueBreakEndsAt;
        private DateTime? _focusCountdownVisibleUntil;
        private DateTime? _firstSleepingHammerHitAt;
        private PetState _focusPauseBaseState = PetState.Idle;
        private bool _focusPaused;
        private TimeSpan _pausedFocusRemaining;
        private TimeSpan? _pausedNextRandomCueRemaining;
        private TimeSpan? _pausedRandomCueBreakRemaining;
        private bool _workingMode;
        private bool _manualRestMode;
        private bool _sleepWakePending;
        private bool _clickThrough;
        private bool _allowExit;
        private IntPtr _windowHandle;
        private HwndSource _source;
        private SpeechBubbleWindow _speechBubbleWindow;
        private LauncherWindow _launcherWindow;
        private FocusJournalWindow _focusJournalWindow;
        private WanderController _wanderController;
        private Forms.ToolStripMenuItem _trayStartFocusItem;
        private Forms.ToolStripMenuItem _trayPauseFocusItem;
        private Forms.ToolStripMenuItem _trayStopFocusItem;

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
            _specialActionTimer.Tick += SpecialActionTimer_Tick;
            _hydrationTimer.Tick += HydrationTimer_Tick;
            _focusTimer.Interval = TimeSpan.FromSeconds(1);
            _focusTimer.Tick += FocusTimer_Tick;
            _focusCountdownTimer.Interval = TimeSpan.FromMilliseconds(100);
            _focusCountdownTimer.Tick += FocusCountdownTimer_Tick;
            _commandTimer.Interval = TimeSpan.FromSeconds(1);
            _commandTimer.Tick += CommandTimer_Tick;
            _doubleClickTimer.Interval = TimeSpan.FromMilliseconds(
                Forms.SystemInformation.DoubleClickTime + 75);
            _doubleClickTimer.Tick += DoubleClickTimer_Tick;
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
            _animator = new SpriteAnimator(
                PetImage,
                SleepZzzLayer,
                new[] { SleepZSmallImage, SleepZMediumImage, SleepZLargeImage },
                new[] { SleepZSmallScale, SleepZMediumScale, SleepZLargeScale },
                new[]
                {
                    SleepZSmallTranslate,
                    SleepZMediumTranslate,
                    SleepZLargeTranslate
                },
                GetBasePetState);
            _hammerAnimator = new HammerAnimator(HammerImage);
            _hammerAnimator.Completed += HammerAnimator_Completed;
            _wanderController = new WanderController(
                this,
                CanAutoWander,
                () => _settings.WanderMinIdleSeconds,
                () => _settings.WanderMaxIdleSeconds,
                _random);
            _wanderController.SetEnabled(_settings.AutoWander);
            CreateSpeechBubbleWindow();
            CreateTrayIcon();
            ConfigureHydrationTimer();
            _behaviorTimer.Start();
            ScheduleNextSpecialAction();
            _commandTimer.Start();

            if (!_settings.FirstRunComplete)
            {
                _settings.FirstRunComplete = true;
                _settingsService.Save(_settings);
                ShowBubble("你好，我是" + _settings.PetName + "！双击开始专注，三击和我聊天，右键查看更多功能。", 7);
                _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(4));
            }

            RestoreActiveFocusState();
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
            ApplyPetScale(_settings.PetScale);
            Topmost = _settings.Topmost;
            if (_speechBubbleWindow != null)
            {
                _speechBubbleWindow.Topmost = _settings.Topmost;
                PositionSpeechBubble();
            }
            TopmostItem.IsChecked = _settings.Topmost;
            WanderItem.IsChecked = _settings.AutoWander;
            _wanderController?.SetEnabled(_settings.AutoWander);
            if (StartupService.IsEnabled() != _settings.StartWithWindows)
                StartupService.SetEnabled(_settings.StartWithWindows);
            ConfigureHydrationTimer();
            ApplyRandomCueSettings();
        }

        private void ApplyPetScale(double scale)
        {
            Width = 210 * scale;
            Height = 238 * scale;
            HammerImage.Width = 90 * scale;
            HammerImage.Height = 90 * scale;
            _wanderController?.RefreshWindowBounds();
            PositionSpeechBubble();
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
                var workArea = DisplayService.GetPrimaryWorkingArea(this);
                Left = workArea.Right - Width - 24;
                Top = workArea.Bottom - Height - 18;
            }
            KeepOnScreen();
        }

        private bool IsVisiblePosition(double left, double top)
        {
            return DisplayService.IsPositionVisible(this, left, top, Width, Height);
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
            if (_focusEnds.HasValue || _workingMode) return;

            if (_manualRestMode)
            {
                if (_animator.CurrentState == PetState.Idle)
                {
                    _firstSleepingHammerHitAt = null;
                    _sleepWakePending = false;
                    _animator.SetState(PetState.Sleeping);
                }
                return;
            }

            if (NativeMethods.GetSystemIdleTime() > TimeSpan.FromMinutes(5))
            {
                if (_animator.CurrentState == PetState.Idle)
                {
                    _firstSleepingHammerHitAt = null;
                    _sleepWakePending = false;
                    _animator.SetState(PetState.Sleeping);
                }
                return;
            }

            if (_animator.CurrentState == PetState.Sleeping)
            {
                _firstSleepingHammerHitAt = null;
                _sleepWakePending = false;
                _animator.SetState(PetState.Idle);
                ShowBubble("欢迎回来。", 3);
            }

        }

        private bool CanAutoWander()
        {
            return _settings != null &&
                   _settings.AutoWander &&
                   IsVisible &&
                   !_focusEnds.HasValue &&
                   !_workingMode &&
                   !_manualRestMode &&
                   NativeMethods.GetSystemIdleTime() <= TimeSpan.FromMinutes(5) &&
                   _animator != null &&
                   _animator.CurrentState == PetState.Idle;
        }

        private PetState GetBasePetState()
        {
            if (_focusEnds.HasValue)
            {
                if (_focusPaused) return _focusPauseBaseState;
                if (_randomCueBreakEndsAt.HasValue) return PetState.Reminder;
                return PetState.Working;
            }
            return GetNonFocusBasePetState();
        }

        private PetState GetNonFocusBasePetState()
        {
            if (_workingMode) return PetState.Working;
            if (_manualRestMode ||
                NativeMethods.GetSystemIdleTime() > TimeSpan.FromMinutes(5))
                return PetState.Sleeping;
            return PetState.Idle;
        }

        private PetState CaptureFocusPauseBaseState()
        {
            if (_workingMode) return PetState.Working;
            if (_manualRestMode) return PetState.Sleeping;
            if (_animator != null &&
                (_animator.CurrentState == PetState.Working ||
                 _animator.CurrentState == PetState.Sleeping))
                return _animator.CurrentState;
            return NativeMethods.GetSystemIdleTime() > TimeSpan.FromMinutes(5)
                ? PetState.Sleeping
                : PetState.Idle;
        }

        private void ApplyBasePetState()
        {
            if (_animator == null) return;
            var baseState = GetBasePetState();
            if (_animator.CurrentState != baseState)
                _animator.SetState(baseState);
        }

        private void ScheduleNextSpecialAction()
        {
            _specialActionTimer.Stop();
            _specialActionTimer.Interval =
                TimeSpan.FromSeconds(_random.Next(20, 31));
            _specialActionTimer.Start();
        }

        private void SpecialActionTimer_Tick(object sender, EventArgs e)
        {
            _specialActionTimer.Stop();
            var canPlay =
                GetBasePetState() == PetState.Idle &&
                _animator.CurrentState == PetState.Idle;

            if (canPlay)
            {
                var choice = _random.Next(3);
                if (choice == 0)
                    _animator.SetState(PetState.Blinking);
                else if (choice == 1)
                    _animator.SetState(PetState.HeartPulse);
                else
                    _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(3));
            }

            ScheduleNextSpecialAction();
        }

        private void HydrationTimer_Tick(object sender, EventArgs e)
        {
            Notify("喝水时间", "休息一下，喝几口水吧。");
            _animator.SetState(PetState.Reminder, TimeSpan.FromSeconds(6));
            ShowBubble("喝水时间到啦！让眼睛也离开屏幕一会儿。", 7);
        }

        private void StartFocus_Click(object sender, RoutedEventArgs e)
        {
            var hadActiveFocus = _focusEnds.HasValue;
            if (!hadActiveFocus)
                _focusPauseBaseState = CaptureFocusPauseBaseState();
            var now = DateTime.Now;
            var interruptedMessage = hadActiveFocus
                ? RecordInterruptedFocus(now)
                : string.Empty;
            _focusTimer.Stop();
            ClearPersistedActiveFocusState();
            ResetFocusPauseState();
            ResetFocusTracking();
            BeginFocusTracking(now, _settings.FocusMinutes);
            _focusEnds = now.AddMinutes(_settings.FocusMinutes);
            ResetRandomCues();
            ScheduleNextRandomCue(now);
            _focusTimer.Start();
            UpdateFocusMenuState();
            ApplyBasePetState();
            _soundService.PlayFocusStart(_settings.FocusStartSound);
            PersistActiveFocusState(true);
            ShowBubble(
                (string.IsNullOrWhiteSpace(interruptedMessage)
                    ? string.Empty
                    : "上一个番茄钟：" + interruptedMessage + " ") +
                "专注 " + _settings.FocusMinutes +
                " 分钟，开始！我陪你一起。",
                string.IsNullOrWhiteSpace(interruptedMessage) ? 5 : 8);
        }

        private void FocusTimer_Tick(object sender, EventArgs e)
        {
            if (!_focusEnds.HasValue) return;
            var now = DateTime.Now;
            var remaining = _focusEnds.Value - now;
            if (remaining <= TimeSpan.Zero)
            {
                CompleteFocus();
                return;
            }

            PersistActiveFocusState(false);
            ProcessRandomCues(now);
        }

        private void PauseFocus_Click(object sender, RoutedEventArgs e)
        {
            if (!_focusEnds.HasValue) return;
            if (_focusPaused)
                ResumeFocus();
            else
                PauseFocus();
        }

        private void PauseFocus()
        {
            var now = DateTime.Now;
            _pausedFocusRemaining = ClampRemaining(_focusEnds.Value - now);
            if (_pausedFocusRemaining <= TimeSpan.Zero)
            {
                CompleteFocus();
                return;
            }

            CloseActiveFocusSegment(now);
            _pausedNextRandomCueRemaining =
                GetRemainingUntil(_nextRandomCueAt, now);
            _pausedRandomCueBreakRemaining =
                GetRemainingUntil(_randomCueBreakEndsAt, now);
            _nextRandomCueAt = null;
            _randomCueBreakEndsAt = null;
            _focusPaused = true;
            _focusTimer.Stop();
            UpdateFocusMenuState();
            ApplyBasePetState();
            PersistActiveFocusState(true);
            ShowBubble(
                "番茄钟已暂停。还剩 " +
                FormatFocusRemaining(_pausedFocusRemaining) + "。",
                4);
        }

        private void ResumeFocus()
        {
            if (!_focusPaused || !_focusEnds.HasValue) return;

            var now = DateTime.Now;
            _focusEnds = now.Add(_pausedFocusRemaining);
            _activeFocusSegmentStartedAt = now;
            _focusPaused = false;

            if (_settings.RandomCueEnabled &&
                _pausedRandomCueBreakRemaining.HasValue)
            {
                _randomCueBreakEndsAt =
                    now.Add(_pausedRandomCueBreakRemaining.Value);
                _nextRandomCueAt = null;
                ApplyBasePetState();
            }
            else
            {
                _randomCueBreakEndsAt = null;
                if (_settings.RandomCueEnabled &&
                    _pausedNextRandomCueRemaining.HasValue)
                {
                    var candidate =
                        now.Add(_pausedNextRandomCueRemaining.Value);
                    if (candidate.AddSeconds(_settings.RandomCueBreakSeconds) <
                        _focusEnds.Value)
                        _nextRandomCueAt = candidate;
                    else
                        _nextRandomCueAt = null;
                }
                else
                {
                    ScheduleNextRandomCue(now);
                }
                ApplyBasePetState();
            }

            _pausedNextRandomCueRemaining = null;
            _pausedRandomCueBreakRemaining = null;
            _focusTimer.Start();
            UpdateFocusMenuState();
            _soundService.PlayFocusStart(_settings.FocusStartSound);
            PersistActiveFocusState(true);
            ShowFocusCountdown();
        }

        private void StopFocus_Click(object sender, RoutedEventArgs e)
        {
            if (!_focusEnds.HasValue) return;
            var settlementMessage = RecordInterruptedFocus(DateTime.Now);
            _focusTimer.Stop();
            _focusEnds = null;
            ResetFocusTracking();
            ResetFocusPauseState();
            ResetRandomCues();
            ClearPersistedActiveFocusState();
            UpdateFocusMenuState();
            ApplyBasePetState();
            ShowBubble(
                "计时已停止。" + settlementMessage +
                " 随时都可以重新开始。",
                7);
        }

        private void CompleteFocus()
        {
            var completedAt = DateTime.Now;
            var accountingEnd = _focusEnds.HasValue &&
                _focusEnds.Value < completedAt
                ? _focusEnds.Value
                : completedAt;
            CloseActiveFocusSegment(accountingEnd);
            var recordMessage = RecordCompletedFocus(completedAt);
            _focusTimer.Stop();
            _focusEnds = null;
            ResetFocusTracking();
            ResetFocusPauseState();
            ResetRandomCues();
            ClearPersistedActiveFocusState();
            UpdateFocusMenuState();
            _animator.SetState(PetState.Success, TimeSpan.FromSeconds(8));
            _soundService.PlayFocusComplete(_settings.FocusCompleteSound);
            Notify("专注完成", recordMessage + " 做得好，起来活动一下吧。");
            ShowBubble(
                "专注完成！" + recordMessage + " 做得好，起来活动一下吧。",
                8);
        }

        private string RecordCompletedFocus(DateTime completedAt)
        {
            var plannedMinutes = Math.Max(
                1,
                _activeFocusPlannedMinutes > 0
                    ? _activeFocusPlannedMinutes
                    : _settings.FocusMinutes);
            var startedAt = _activeFocusStartedAt ??
                completedAt.AddMinutes(-plannedMinutes);
            var minuteAllocations = AllocateActiveFocusMinutes(
                plannedMinutes,
                completedAt);

            try
            {
                if (_focusJournalWindow != null)
                    _focusJournalWindow.SavePendingChanges();
                _focusJournalService.RecordCompletedSession(
                    startedAt,
                    completedAt,
                    plannedMinutes,
                    minuteAllocations);
                var journalDate =
                    FocusTimeAccounting.GetJournalDate(completedAt);
                var day = _focusJournalService.GetDay(journalDate);
                if (_focusJournalWindow != null)
                    _focusJournalWindow.RefreshFromStore();
                var countMessage = day.TargetCount > 0
                    ? "今天已自动记录第 " + day.CompletedCount +
                      " / " + day.TargetCount + " 个番茄钟。"
                    : "今天已自动记录第 " + day.CompletedCount + " 个番茄钟。";
                return countMessage +
                    FormatCrossDayAllocation(minuteAllocations);
            }
            catch
            {
                return "自动记录暂时保存失败，请稍后手动补记。";
            }
        }

        private string RecordInterruptedFocus(DateTime stoppedAt)
        {
            var plannedMinutes = Math.Max(
                1,
                _activeFocusPlannedMinutes > 0
                    ? _activeFocusPlannedMinutes
                    : _settings.FocusMinutes);
            var accountingEnd = !_focusPaused &&
                _focusEnds.HasValue &&
                _focusEnds.Value < stoppedAt
                ? _focusEnds.Value
                : stoppedAt;
            CloseActiveFocusSegment(accountingEnd);
            var completedMinutes =
                FocusTimeAccounting.GetCompletedWholeMinutes(
                    _activeFocusSegments,
                    plannedMinutes);
            if (completedMinutes <= 0)
                return "尚未完成 1 分钟，没有写入专注记录。";

            var minuteAllocations = AllocateActiveFocusMinutes(
                completedMinutes,
                accountingEnd);
            var startedAt = _activeFocusStartedAt ??
                accountingEnd.AddMinutes(-completedMinutes);

            try
            {
                if (_focusJournalWindow != null)
                    _focusJournalWindow.SavePendingChanges();

                string result;
                if (completedMinutes >= plannedMinutes)
                {
                    _focusJournalService.RecordCompletedSession(
                        startedAt,
                        accountingEnd,
                        plannedMinutes,
                        minuteAllocations);
                    result = "已凑齐完整番茄钟并自动记录。" +
                        FormatCrossDayAllocation(minuteAllocations);
                }
                else
                {
                    _focusJournalService.AddMinuteAdjustments(
                        minuteAllocations);
                    result = "已完成 " + completedMinutes +
                        " 分钟，" +
                        FormatMinuteAdjustmentResult(minuteAllocations);
                }

                if (_focusJournalWindow != null)
                    _focusJournalWindow.RefreshFromStore();
                return result;
            }
            catch
            {
                return "本次已完成 " + completedMinutes +
                    " 分钟，但自动保存失败，请手动补记。";
            }
        }

        private void BeginFocusTracking(
            DateTime startedAt,
            int plannedMinutes)
        {
            _activeFocusSegments.Clear();
            _activeFocusStartedAt = startedAt;
            _activeFocusSegmentStartedAt = startedAt;
            _activeFocusPlannedMinutes = Math.Max(1, plannedMinutes);
        }

        private void CloseActiveFocusSegment(DateTime endedAt)
        {
            if (!_activeFocusSegmentStartedAt.HasValue)
                return;

            var startedAt = _activeFocusSegmentStartedAt.Value;
            if (endedAt > startedAt)
            {
                _activeFocusSegments.Add(
                    new FocusTimeSegment(startedAt, endedAt));
            }
            _activeFocusSegmentStartedAt = null;
        }

        private void ResetFocusTracking()
        {
            _activeFocusSegments.Clear();
            _activeFocusStartedAt = null;
            _activeFocusSegmentStartedAt = null;
            _activeFocusPlannedMinutes = 0;
        }

        private void PersistActiveFocusState(bool force)
        {
            if (!_focusEnds.HasValue)
                return;

            var now = DateTime.Now;
            if (!force &&
                now - _lastFocusStateSavedAt <
                FocusStateCheckpointInterval)
            {
                return;
            }

            var remaining = GetCurrentFocusRemaining();
            if (!remaining.HasValue ||
                remaining.Value <= TimeSpan.Zero)
            {
                return;
            }

            try
            {
                _activeFocusStateService.Save(
                    CreateActiveFocusStateSnapshot(
                        now,
                        remaining.Value));
                _lastFocusStateSavedAt = now;
            }
            catch
            {
                // The timer remains usable even if this checkpoint fails.
            }
        }

        private ActiveFocusStateData CreateActiveFocusStateSnapshot(
            DateTime savedAt,
            TimeSpan remaining)
        {
            var segments = _activeFocusSegments
                .Select(segment =>
                    new ActiveFocusSegmentData
                    {
                        StartedAt = ToIsoTimestamp(
                            segment.StartedAt),
                        EndedAt = ToIsoTimestamp(
                            segment.EndedAt)
                    })
                .ToList();

            if (!_focusPaused &&
                _activeFocusSegmentStartedAt.HasValue)
            {
                var segmentEnd = _focusEnds.HasValue &&
                    _focusEnds.Value < savedAt
                    ? _focusEnds.Value
                    : savedAt;
                if (segmentEnd >
                    _activeFocusSegmentStartedAt.Value)
                {
                    segments.Add(new ActiveFocusSegmentData
                    {
                        StartedAt = ToIsoTimestamp(
                            _activeFocusSegmentStartedAt.Value),
                        EndedAt = ToIsoTimestamp(segmentEnd)
                    });
                }
            }

            var plannedMinutes = Math.Max(
                1,
                _activeFocusPlannedMinutes > 0
                    ? _activeFocusPlannedMinutes
                    : _settings.FocusMinutes);
            var startedAt = _activeFocusStartedAt ??
                savedAt.AddMinutes(-plannedMinutes);
            return new ActiveFocusStateData
            {
                Version = 1,
                StartedAt = ToIsoTimestamp(startedAt),
                PlannedMinutes = plannedMinutes,
                RemainingSeconds = Math.Max(
                    0.001,
                    remaining.TotalSeconds),
                WasPaused = _focusPaused,
                SavedAt = ToIsoTimestamp(savedAt),
                Segments = segments
            };
        }

        private bool RestoreActiveFocusState()
        {
            ActiveFocusStateData state;
            try
            {
                state = _activeFocusStateService.Load();
            }
            catch
            {
                return false;
            }
            if (state == null)
                return false;

            DateTime startedAt;
            if (!TryParseLocalTimestamp(
                state.StartedAt,
                out startedAt))
            {
                return false;
            }

            var remaining = TimeSpan.FromSeconds(
                Math.Min(
                    state.PlannedMinutes * 60.0,
                    state.RemainingSeconds));
            if (remaining <= TimeSpan.Zero)
                return false;

            ResetRandomCues();
            ResetFocusPauseState();
            ResetFocusTracking();
            _focusPauseBaseState = CaptureFocusPauseBaseState();
            _activeFocusStartedAt = startedAt;
            _activeFocusPlannedMinutes =
                state.PlannedMinutes;
            foreach (var savedSegment in state.Segments ??
                new List<ActiveFocusSegmentData>())
            {
                DateTime segmentStart;
                DateTime segmentEnd;
                if (!TryParseLocalTimestamp(
                        savedSegment.StartedAt,
                        out segmentStart) ||
                    !TryParseLocalTimestamp(
                        savedSegment.EndedAt,
                        out segmentEnd) ||
                    segmentEnd <= segmentStart)
                {
                    continue;
                }
                _activeFocusSegments.Add(
                    new FocusTimeSegment(
                        segmentStart,
                        segmentEnd));
            }

            var now = DateTime.Now;
            _activeFocusSegmentStartedAt = null;
            _pausedFocusRemaining = remaining;
            _focusEnds = now.Add(remaining);
            _focusPaused = true;
            _lastFocusStateSavedAt = now;
            UpdateFocusMenuState();
            ApplyBasePetState();
            ShowBubble(
                "已恢复上次的番茄钟，目前为暂停状态，还剩 " +
                FormatFocusRemaining(remaining) +
                "。双击苏无度即可继续。",
                9);
            return true;
        }

        private void ClearPersistedActiveFocusState()
        {
            try
            {
                _activeFocusStateService.Clear();
            }
            catch
            {
                // A later checkpoint can safely replace a stale file.
            }
            _lastFocusStateSavedAt = DateTime.MinValue;
        }

        private static string ToIsoTimestamp(DateTime timestamp)
        {
            var local = timestamp.Kind == DateTimeKind.Utc
                ? timestamp.ToLocalTime()
                : timestamp.Kind == DateTimeKind.Unspecified
                    ? DateTime.SpecifyKind(
                        timestamp,
                        DateTimeKind.Local)
                    : timestamp;
            return new DateTimeOffset(local).ToString(
                "o",
                CultureInfo.InvariantCulture);
        }

        private static bool TryParseLocalTimestamp(
            string value,
            out DateTime timestamp)
        {
            DateTimeOffset parsed;
            if (DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out parsed))
            {
                timestamp = parsed.LocalDateTime;
                return true;
            }

            timestamp = default(DateTime);
            return false;
        }

        private IDictionary<string, int> AllocateActiveFocusMinutes(
            int minutes,
            DateTime fallbackInstant)
        {
            var allocations = FocusTimeAccounting.AllocateMinutes(
                _activeFocusSegments,
                minutes);
            if (allocations.Values.Sum() == minutes)
                return allocations;

            return new Dictionary<string, int>(StringComparer.Ordinal)
            {
                {
                    FocusTimeAccounting.GetJournalDateKey(fallbackInstant),
                    minutes
                }
            };
        }

        private static string FormatCrossDayAllocation(
            IDictionary<string, int> allocations)
        {
            if (allocations == null || allocations.Count <= 1)
                return string.Empty;

            return " 分钟已按晚上 9 点拆分：" +
                FormatAllocationList(allocations) + "。";
        }

        private static string FormatMinuteAdjustmentResult(
            IDictionary<string, int> allocations)
        {
            if (allocations.Count == 1)
            {
                var allocation = allocations.First();
                return FormatJournalDate(allocation.Key) +
                    "的“今日分钟调整”已增加 " +
                    allocation.Value + " 分钟。";
            }

            return "已按晚上 9 点拆分并加入对应日期的“今日分钟调整”：" +
                FormatAllocationList(allocations) + "。";
        }

        private static string FormatAllocationList(
            IDictionary<string, int> allocations)
        {
            return string.Join(
                "、",
                allocations
                    .OrderBy(item => item.Key, StringComparer.Ordinal)
                    .Select(item =>
                        FormatJournalDate(item.Key) + " " +
                        item.Value + " 分钟"));
        }

        private static string FormatJournalDate(string dateKey)
        {
            DateTime date;
            return DateTime.TryParseExact(
                dateKey,
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out date)
                ? date.ToString("M月d日", CultureInfo.GetCultureInfo("zh-CN"))
                : dateKey;
        }

        private void ResetFocusPauseState()
        {
            _focusPaused = false;
            _pausedFocusRemaining = TimeSpan.Zero;
            _pausedNextRandomCueRemaining = null;
            _pausedRandomCueBreakRemaining = null;
        }

        private static TimeSpan? GetRemainingUntil(DateTime? target, DateTime now)
        {
            return target.HasValue
                ? (TimeSpan?)ClampRemaining(target.Value - now)
                : null;
        }

        private static TimeSpan ClampRemaining(TimeSpan remaining)
        {
            return remaining < TimeSpan.Zero ? TimeSpan.Zero : remaining;
        }

        private void ApplyRandomCueSettings()
        {
            if (!_focusEnds.HasValue) return;
            if (_focusPaused) return;

            if (!_settings.RandomCueEnabled)
            {
                var wasTakingBreak = _randomCueBreakEndsAt.HasValue;
                ResetRandomCues();
                if (wasTakingBreak && _animator != null)
                    ApplyBasePetState();
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
                ApplyBasePetState();
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
            _wanderController?.PauseForUserInteraction();

            if (e.ClickCount >= 3)
            {
                _doubleClickTimer.Stop();
                if (e.ClickCount == 3)
                {
                    StopFocusCountdownDisplay();
                    HideSpeechBubble();
                    OpenChat();
                }
                _wanderController?.ResumeAfterUserInteraction(false);
                e.Handled = true;
                return;
            }

            if (e.ClickCount == 2)
            {
                _doubleClickTimer.Stop();
                _doubleClickTimer.Start();
                _wanderController?.ResumeAfterUserInteraction(false);
                e.Handled = true;
                return;
            }

            var startingLeft = Left;
            var startingTop = Top;
            try
            {
                DragMove();
                KeepOnScreen();
                SaveWindowPosition();
            }
            catch (InvalidOperationException) { }
            var wasDragged =
                Math.Abs(Left - startingLeft) > 2 ||
                Math.Abs(Top - startingTop) > 2;
            _wanderController?.ResumeAfterUserInteraction(wasDragged);
            if (!wasDragged)
            {
                var wasSleeping = _animator.CurrentState == PetState.Sleeping;
                var shouldPlayIdleHitReaction =
                    _animator.CurrentState == PetState.Idle &&
                    GetBasePetState() == PetState.Idle;
                if (shouldPlayIdleHitReaction)
                    _animator.SetState(PetState.Hit);
                PlayHammerStrike();
                if (wasSleeping)
                    RegisterSleepingHammerHit();
                if (_focusEnds.HasValue)
                    ShowFocusCountdown();
            }
        }

        private void RegisterSleepingHammerHit()
        {
            var now = DateTime.Now;
            if (!_firstSleepingHammerHitAt.HasValue ||
                now - _firstSleepingHammerHitAt.Value > TimeSpan.FromSeconds(4))
            {
                _firstSleepingHammerHitAt = now;
                return;
            }

            _firstSleepingHammerHitAt = null;
            _sleepWakePending = true;
        }

        private void HammerAnimator_Completed(object sender, EventArgs e)
        {
            if (!_sleepWakePending) return;
            _sleepWakePending = false;
            if (_animator == null ||
                _animator.CurrentState != PetState.Sleeping)
                return;

            var fadeOut = new DoubleAnimation(
                1,
                0.35,
                TimeSpan.FromMilliseconds(240))
            {
                BeginTime = TimeSpan.FromMilliseconds(120),
                FillBehavior = FillBehavior.HoldEnd
            };
            fadeOut.Completed += (completedSender, completedArgs) =>
            {
                _manualRestMode = false;
                RestModeItem.IsChecked = false;
                if (_focusEnds.HasValue &&
                    _focusPauseBaseState == PetState.Sleeping)
                    _focusPauseBaseState = PetState.Idle;
                ApplyBasePetState();

                var fadeIn = new DoubleAnimation(
                    0.35,
                    1,
                    TimeSpan.FromMilliseconds(480))
                {
                    FillBehavior = FillBehavior.Stop
                };
                fadeIn.Completed += (fadeSender, fadeArgs) =>
                {
                    PetImage.BeginAnimation(UIElement.OpacityProperty, null);
                    PetImage.Opacity = 1;
                    ShowBubble("好啦好啦，我醒了！", 3);
                };
                PetImage.BeginAnimation(UIElement.OpacityProperty, fadeIn);
            };
            PetImage.BeginAnimation(UIElement.OpacityProperty, fadeOut);
        }

        private void DoubleClickTimer_Tick(object sender, EventArgs e)
        {
            _doubleClickTimer.Stop();
            StopFocusCountdownDisplay();
            HideSpeechBubble();
            if (!_focusEnds.HasValue)
                StartFocus_Click(this, null);
            else if (_focusPaused)
                ResumeFocus();
            else
                PauseFocus();
        }

        private void PetImage_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
        {
            _wanderController?.PauseForUserInteraction();
            PetMenu.IsOpen = true;
            e.Handled = true;
        }

        private void PetMenu_Closed(object sender, RoutedEventArgs e)
        {
            _wanderController?.ResumeAfterUserInteraction(false);
        }

        private void PlayHammerStrike()
        {
            if (_hammerAnimator == null) return;

            var scale = _settings == null ? 1 : _settings.PetScale;
            HammerRotate.BeginAnimation(
                System.Windows.Media.RotateTransform.AngleProperty,
                CreateHammerRotationAnimation());
            HammerTranslate.BeginAnimation(
                System.Windows.Media.TranslateTransform.XProperty,
                CreateHammerHorizontalAnimation(scale));
            HammerTranslate.BeginAnimation(
                System.Windows.Media.TranslateTransform.YProperty,
                CreateHammerVerticalAnimation(scale));

            var reactionY = new DoubleAnimationUsingKeyFrames();
            reactionY.KeyFrames.Add(new EasingDoubleKeyFrame(
                0,
                KeyTime.FromTimeSpan(TimeSpan.Zero)));
            reactionY.KeyFrames.Add(new EasingDoubleKeyFrame(
                0,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(360))));
            reactionY.KeyFrames.Add(new EasingDoubleKeyFrame(
                3 * scale,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(430)),
                new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            reactionY.KeyFrames.Add(new EasingDoubleKeyFrame(
                0,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(650)),
                new BackEase
                {
                    Amplitude = 0.15,
                    EasingMode = EasingMode.EaseOut
                }));
            PetTranslate.BeginAnimation(
                System.Windows.Media.TranslateTransform.YProperty,
                reactionY);

            PetBounceScale.BeginAnimation(
                System.Windows.Media.ScaleTransform.ScaleXProperty,
                CreateReactionScaleAnimation(1.018));
            PetBounceScale.BeginAnimation(
                System.Windows.Media.ScaleTransform.ScaleYProperty,
                CreateReactionScaleAnimation(0.975));
            _hammerAnimator.Play();
        }

        private static DoubleAnimationUsingKeyFrames CreateHammerRotationAnimation()
        {
            var animation = new DoubleAnimationUsingKeyFrames();
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                -42,
                KeyTime.FromTimeSpan(TimeSpan.Zero)));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                -28,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(120)),
                new QuadraticEase { EasingMode = EasingMode.EaseInOut }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                4,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(260)),
                new QuadraticEase { EasingMode = EasingMode.EaseIn }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                58,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(430)),
                new CubicEase { EasingMode = EasingMode.EaseIn }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                43,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(620)),
                new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            return animation;
        }

        private static DoubleAnimationUsingKeyFrames CreateHammerHorizontalAnimation(
            double scale)
        {
            var animation = new DoubleAnimationUsingKeyFrames();
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                28 * scale,
                KeyTime.FromTimeSpan(TimeSpan.Zero)));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                18 * scale,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(180)),
                new QuadraticEase { EasingMode = EasingMode.EaseInOut }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                -4 * scale,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(430)),
                new CubicEase { EasingMode = EasingMode.EaseIn }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                0,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(620)),
                new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            return animation;
        }

        private static DoubleAnimationUsingKeyFrames CreateHammerVerticalAnimation(
            double scale)
        {
            var animation = new DoubleAnimationUsingKeyFrames();
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                -34 * scale,
                KeyTime.FromTimeSpan(TimeSpan.Zero)));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                -26 * scale,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(180)),
                new QuadraticEase { EasingMode = EasingMode.EaseInOut }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                14 * scale,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(430)),
                new CubicEase { EasingMode = EasingMode.EaseIn }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                7 * scale,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(620)),
                new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            return animation;
        }

        private static DoubleAnimationUsingKeyFrames CreateReactionScaleAnimation(
            double impactValue)
        {
            var animation = new DoubleAnimationUsingKeyFrames();
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                1,
                KeyTime.FromTimeSpan(TimeSpan.Zero)));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                1,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(360))));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                impactValue,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(430)),
                new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(
                1,
                KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(650)),
                new BackEase
                {
                    Amplitude = 0.12,
                    EasingMode = EasingMode.EaseOut
                }));
            return animation;
        }

        public void ShowBubble(string message, int seconds = 5)
        {
            if (string.IsNullOrWhiteSpace(message)) return;
            StopFocusCountdownDisplay();
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

        private void ShowFocusCountdown()
        {
            if (!_focusEnds.HasValue) return;
            if (_speechBubbleWindow == null)
                CreateSpeechBubbleWindow();

            _bubbleTimer.Stop();
            _focusCountdownVisibleUntil = DateTime.Now.AddSeconds(4);
            UpdateFocusCountdownBubble();
            PositionSpeechBubble();
            if (IsVisible && !_speechBubbleWindow.IsVisible)
                _speechBubbleWindow.Show();
            _focusCountdownTimer.Start();
        }

        private void FocusCountdownTimer_Tick(object sender, EventArgs e)
        {
            if (!_focusEnds.HasValue ||
                !_focusCountdownVisibleUntil.HasValue ||
                DateTime.Now >= _focusCountdownVisibleUntil.Value)
            {
                StopFocusCountdownDisplay();
                HideSpeechBubble();
                return;
            }

            UpdateFocusCountdownBubble();
        }

        private void UpdateFocusCountdownBubble()
        {
            var remaining = GetCurrentFocusRemaining();
            if (!remaining.HasValue || _speechBubbleWindow == null) return;
            _speechBubbleWindow.SetMessage(
                _focusPaused
                    ? "番茄钟已暂停：还剩 " +
                      FormatFocusRemaining(remaining.Value)
                    : "番茄钟剩余：" +
                      FormatFocusRemaining(remaining.Value));
        }

        private TimeSpan? GetCurrentFocusRemaining()
        {
            if (!_focusEnds.HasValue) return null;
            return _focusPaused
                ? _pausedFocusRemaining
                : ClampRemaining(_focusEnds.Value - DateTime.Now);
        }

        private static string FormatFocusRemaining(TimeSpan remaining)
        {
            var totalSeconds = Math.Max(0,
                (int)Math.Ceiling(remaining.TotalSeconds));
            return (totalSeconds / 60) + " 分 " +
                   (totalSeconds % 60) + " 秒";
        }

        private void StopFocusCountdownDisplay()
        {
            _focusCountdownTimer.Stop();
            _focusCountdownVisibleUntil = null;
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
            var workArea = DisplayService.GetWorkingAreaForWindow(this);
            var desiredLeft = Left + (Width - _speechBubbleWindow.Width) / 2;
            var maximumLeft = Math.Max(workArea.Left,
                workArea.Right - _speechBubbleWindow.Width);
            _speechBubbleWindow.Left = Math.Max(workArea.Left,
                Math.Min(desiredLeft, maximumLeft));
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
                revertAfterSeconds <= 0
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
        }

        private void PetAction_Click(object sender, RoutedEventArgs e)
        {
            var item = sender as MenuItem;
            if (item == null) return;

            PetState state;
            TimeSpan duration;
            switch (item.Tag as string)
            {
                case "Heart":
                    state = PetState.HeartPulse;
                    duration = TimeSpan.FromSeconds(3);
                    break;
                case "Blink":
                    state = PetState.Blinking;
                    duration = TimeSpan.FromMilliseconds(1450);
                    break;
                case "Wave":
                    state = PetState.Waving;
                    duration = TimeSpan.FromSeconds(3);
                    break;
                default:
                    return;
            }

            _animator.SetState(state, duration);
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

        internal void SetScreenVisionEnabled(bool enabled)
        {
            _settings.ScreenVisionEnabled = enabled;
            _settingsService.Save(_settings);
        }

        private void WorkMode_Click(object sender, RoutedEventArgs e)
        {
            _workingMode = WorkModeItem.IsChecked;
            if (_workingMode)
            {
                _manualRestMode = false;
                RestModeItem.IsChecked = false;
            }
            if (_focusEnds.HasValue)
                _focusPauseBaseState =
                    _workingMode ? PetState.Working : PetState.Idle;
            ApplyBasePetState();
            ShowBubble(_workingMode ? "工作模式启动。我会安静陪你。" : "工作完成了吗？辛苦啦。", 4);
        }

        private void RestMode_Click(object sender, RoutedEventArgs e)
        {
            _firstSleepingHammerHitAt = null;
            _sleepWakePending = false;
            _manualRestMode = RestModeItem.IsChecked;
            if (_manualRestMode)
            {
                _workingMode = false;
                WorkModeItem.IsChecked = false;
            }
            if (_focusEnds.HasValue)
                _focusPauseBaseState =
                    _manualRestMode ? PetState.Sleeping : PetState.Idle;
            if (_manualRestMode)
            {
                ApplyBasePetState();
                ShowBubble("我先休息一会儿。右键再点一次就能叫醒我。", 4);
                return;
            }

            ApplyBasePetState();
            ShowBubble("我醒啦。", 3);
        }

        private void Wander_Click(object sender, RoutedEventArgs e)
        {
            _settings.AutoWander = WanderItem.IsChecked;
            _settingsService.Save(_settings);
            _wanderController?.SetEnabled(_settings.AutoWander);
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

        private void KeepOnScreen()
        {
            var work = DisplayService.GetWorkingAreaForWindow(this);
            var maximumLeft = Math.Max(work.Left, work.Right - Width);
            var maximumTop = Math.Max(work.Top, work.Bottom - Height);
            var preferredTop = work.Top + SpeechBubbleHeight - SpeechBubbleTailOverlap;
            var minimumTop = Math.Min(preferredTop, maximumTop);
            Left = Math.Max(work.Left, Math.Min(Left, maximumLeft));
            Top = Math.Max(minimumTop, Math.Min(Top, maximumTop));
        }

        private void Settings_Click(object sender, RoutedEventArgs e)
        {
            OpenSettings(this);
        }

        private void FocusJournal_Click(object sender, RoutedEventArgs e)
        {
            ShowFocusJournal();
        }

        private void Launcher_Click(object sender, RoutedEventArgs e) => ShowLauncher();

        internal AppSettings OpenSettings(Window owner)
        {
            _wanderController?.PauseForUserInteraction();
            ToggleClickThrough(false);
            var dialog = new SettingsWindow(_settings.Clone(), _secretService)
            {
                Owner = owner ?? this,
                Topmost = Topmost
            };
            dialog.PetScalePreviewChanged += scale =>
            {
                ApplyPetScale(scale);
                KeepOnScreen();
            };
            if (dialog.ShowDialog() == true)
            {
                _settings = dialog.ResultSettings;
                _settingsService.Save(_settings);
                ApplySettings();
                KeepOnScreen();
                ShowBubble("设置保存好了。", 3);
                _wanderController?.ResumeAfterUserInteraction(false);
                return _settings.Clone();
            }
            ApplyPetScale(_settings.PetScale);
            KeepOnScreen();
            _wanderController?.ResumeAfterUserInteraction(false);
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

        public void ShowLauncher()
        {
            ToggleClickThrough(false);
            if (_launcherWindow == null)
            {
                _launcherWindow = new LauncherWindow(this);
                _launcherWindow.Closed += (sender, args) => _launcherWindow = null;
            }

            if (!_launcherWindow.IsVisible)
                _launcherWindow.Show();
            if (_launcherWindow.WindowState == WindowState.Minimized)
                _launcherWindow.WindowState = WindowState.Normal;

            _launcherWindow.Topmost = true;
            _launcherWindow.Activate();
            _launcherWindow.Dispatcher.BeginInvoke(new Action(() =>
            {
                if (_launcherWindow != null)
                    _launcherWindow.Topmost = false;
            }), DispatcherPriority.ApplicationIdle);
        }

        public void ShowFocusJournal()
        {
            ToggleClickThrough(false);
            if (_focusJournalWindow == null)
            {
                _focusJournalWindow = new FocusJournalWindow(
                    _focusJournalService,
                    _settings.FocusMinutes);
                _focusJournalWindow.Closed +=
                    (sender, args) => _focusJournalWindow = null;
            }
            else
            {
                _focusJournalWindow.UpdateDefaultFocusMinutes(
                    _settings.FocusMinutes);
                _focusJournalWindow.RefreshFromStore();
            }

            if (!_focusJournalWindow.IsVisible)
                _focusJournalWindow.Show();
            if (_focusJournalWindow.WindowState == WindowState.Minimized)
                _focusJournalWindow.WindowState = WindowState.Normal;
            _focusJournalWindow.Activate();
        }

        internal void ShowFromLauncher() => ShowFromTray();

        internal void OpenChatFromLauncher() => OpenChat();

        internal void OpenSettingsFromLauncher(Window owner) => OpenSettings(owner);

        internal void OpenHelpFromLauncher() => Help_Click(this, null);

        internal void OpenFocusJournalFromLauncher() => ShowFocusJournal();

        internal void TuckAwayFromLauncher() => TuckAway_Click(this, null);

        internal void ExitFromLauncher() => ExitApplication();

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
            menu.Opening += (s, e) =>
                Dispatcher.Invoke(() =>
                    _wanderController?.PauseForUserInteraction());
            menu.Closed += (s, e) =>
                Dispatcher.Invoke(() =>
                    _wanderController?.ResumeAfterUserInteraction(false));
            menu.Items.Add("叫醒桌宠", null, (s, e) => Dispatcher.Invoke(ShowFromTray));
            menu.Items.Add("打开启动面板", null, (s, e) => Dispatcher.Invoke(ShowLauncher));
            menu.Items.Add("聊聊天", null, (s, e) => Dispatcher.Invoke(OpenChat));
            menu.Items.Add("恢复鼠标交互 (Ctrl+Alt+P)", null,
                (s, e) => Dispatcher.Invoke(() => ToggleClickThrough(false)));
            _trayStartFocusItem = menu.Items.Add(
                "开始专注", null,
                (s, e) => Dispatcher.Invoke(() => StartFocus_Click(s, null)))
                as Forms.ToolStripMenuItem;
            _trayPauseFocusItem = menu.Items.Add(
                "暂停专注", null,
                (s, e) => Dispatcher.Invoke(() => PauseFocus_Click(s, null)))
                as Forms.ToolStripMenuItem;
            _trayStopFocusItem = menu.Items.Add(
                "停止专注", null,
                (s, e) => Dispatcher.Invoke(() => StopFocus_Click(s, null)))
                as Forms.ToolStripMenuItem;
            menu.Items.Add(
                "今日专注记录", null,
                (s, e) => Dispatcher.Invoke(ShowFocusJournal));
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("使用说明书", null, (s, e) => Dispatcher.Invoke(() => Help_Click(s, null)));
            menu.Items.Add("设置", null, (s, e) => Dispatcher.Invoke(() => Settings_Click(s, null)));
            menu.Items.Add("退出", null, (s, e) => Dispatcher.Invoke(ExitApplication));
            _trayIcon.ContextMenuStrip = menu;
            UpdateFocusMenuState();
        }

        private void UpdateFocusMenuState()
        {
            var hasFocus = _focusEnds.HasValue;
            StartFocusItem.Header = hasFocus
                ? "↻ 重新开始专注计时"
                : "⏱ 开始专注计时";
            PauseFocusItem.IsEnabled = hasFocus;
            PauseFocusItem.Header = _focusPaused
                ? "▶ 继续专注计时"
                : "⏸ 暂停专注计时";
            StopFocusItem.IsEnabled = hasFocus;

            if (_trayStartFocusItem != null)
                _trayStartFocusItem.Text = hasFocus ? "重新开始专注" : "开始专注";
            if (_trayPauseFocusItem != null)
            {
                _trayPauseFocusItem.Enabled = hasFocus;
                _trayPauseFocusItem.Text =
                    _focusPaused ? "继续专注" : "暂停专注";
            }
            if (_trayStopFocusItem != null)
                _trayStopFocusItem.Enabled = hasFocus;
        }

        private void ShowFromTray()
        {
            ToggleClickThrough(false);
            Show();
            WindowState = WindowState.Normal;
            Activate();
            Topmost = _settings.Topmost;
            _animator.SetState(PetState.Waving, TimeSpan.FromSeconds(3));
            _wanderController?.ResumeAfterUserInteraction(false);
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
                var workArea = DisplayService.GetPrimaryWorkingArea(this);
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
            PersistActiveFocusState(true);
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
            _specialActionTimer.Stop();
            _hydrationTimer.Stop();
            _focusTimer.Stop();
            _focusCountdownTimer.Stop();
            _commandTimer.Stop();
            _bubbleTimer.Stop();
            _doubleClickTimer.Stop();
            if (_wanderController != null) _wanderController.Dispose();
            if (_speechBubbleWindow != null)
            {
                _speechBubbleWindow.Close();
                _speechBubbleWindow = null;
            }
            if (_animator != null) _animator.Dispose();
            if (_hammerAnimator != null) _hammerAnimator.Dispose();
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
