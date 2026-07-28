using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using DesktopPet.Models;
using DesktopPet.Services;

namespace DesktopPet
{
    public partial class FocusJournalWindow : Window
    {
        private readonly FocusJournalService _service;
        private int _defaultFocusMinutes;
        private readonly CultureInfo _displayCulture =
            CultureInfo.GetCultureInfo("zh-CN");
        private DateTime _selectedDate;
        private DailyFocusRecord _currentDay;
        private ObservableCollection<FocusSessionViewModel> _sessions;
        private HashSet<string> _loadedSessionIds =
            new HashSet<string>(StringComparer.Ordinal);
        private bool _loading;
        private bool _saving;
        private bool _dirty;

        public FocusJournalWindow(
            FocusJournalService service,
            int defaultFocusMinutes)
        {
            InitializeComponent();
            _service = service ?? throw new ArgumentNullException(nameof(service));
            _defaultFocusMinutes = Math.Max(1, defaultFocusMinutes);
            _service.JournalChanged += FocusJournalService_JournalChanged;
            Loaded += (sender, args) => LoadDay(DateTime.Today);
            Closed += (sender, args) =>
                _service.JournalChanged -= FocusJournalService_JournalChanged;
        }

        public bool SavePendingChanges()
        {
            return !_dirty || TrySaveCurrentDay(false);
        }

        public void UpdateDefaultFocusMinutes(int minutes)
        {
            _defaultFocusMinutes = Math.Max(1, minutes);
        }

        public void RefreshFromStore()
        {
            if (_dirty)
            {
                StatusText.Text = "检测到新的自动记录；保存当前编辑时会自动合并。";
                return;
            }
            LoadDay(_selectedDate);
        }

        private void LoadDay(DateTime date)
        {
            _loading = true;
            try
            {
                _selectedDate = date.Date;
                _currentDay = _service.GetDay(_selectedDate);
                _loadedSessionIds = new HashSet<string>(
                    (_currentDay.Sessions ?? new List<FocusSessionRecord>())
                        .Where(item => item != null)
                        .Select(item => item.Id),
                    StringComparer.Ordinal);

                TargetCountBox.Text =
                    _currentDay.TargetCount.ToString(CultureInfo.InvariantCulture);
                MinuteAdjustmentBox.Text =
                    _currentDay.MinuteAdjustment.ToString(CultureInfo.InvariantCulture);
                DailyNotesBox.Text = _currentDay.DailyNotes ?? string.Empty;

                _sessions = new ObservableCollection<FocusSessionViewModel>(
                    (_currentDay.Sessions ?? new List<FocusSessionRecord>())
                        .Where(item => item != null)
                        .Select(CreateSessionViewModel));
                SessionsList.ItemsSource = _sessions;
                JournalDatePicker.SelectedDate = _selectedDate;
                Title = "苏无度 · " +
                    _selectedDate.ToString("yyyy年M月d日", _displayCulture) +
                    " 专注记录";
                StatusText.Text = _selectedDate == DateTime.Today
                    ? "正在查看今天。"
                    : "正在查看 " +
                      _selectedDate.ToString("yyyy年M月d日", _displayCulture) + "。";
                _dirty = false;
                UpdateSummary();
            }
            finally
            {
                _loading = false;
            }
        }

        private FocusSessionViewModel CreateSessionViewModel(
            FocusSessionRecord record)
        {
            var viewModel = new FocusSessionViewModel(record);
            viewModel.PropertyChanged += SessionViewModel_PropertyChanged;
            return viewModel;
        }

        private void SessionViewModel_PropertyChanged(
            object sender,
            PropertyChangedEventArgs e)
        {
            if (_loading) return;
            MarkDirty();
            UpdateSummary();
        }

        private void PreviousDay_Click(object sender, RoutedEventArgs e)
        {
            NavigateTo(_selectedDate.AddDays(-1));
        }

        private void NextDay_Click(object sender, RoutedEventArgs e)
        {
            NavigateTo(_selectedDate.AddDays(1));
        }

        private void Today_Click(object sender, RoutedEventArgs e)
        {
            NavigateTo(DateTime.Today);
        }

        private void JournalDatePicker_SelectedDateChanged(
            object sender,
            SelectionChangedEventArgs e)
        {
            if (_loading || !JournalDatePicker.SelectedDate.HasValue) return;
            NavigateTo(JournalDatePicker.SelectedDate.Value);
        }

        private void NavigateTo(DateTime date)
        {
            if (date.Date == _selectedDate) return;
            if (!SavePendingChanges())
            {
                _loading = true;
                JournalDatePicker.SelectedDate = _selectedDate;
                _loading = false;
                return;
            }
            LoadDay(date);
        }

        private void AddManualSession_Click(object sender, RoutedEventArgs e)
        {
            var completion = _selectedDate == DateTime.Today
                ? DateTime.Now
                : _selectedDate.AddHours(12);
            completion = DateTime.SpecifyKind(completion, DateTimeKind.Local);
            var record = new FocusSessionRecord
            {
                Id = Guid.NewGuid().ToString("D"),
                Source = FocusSessionRecord.ManualSource,
                StartedAt = new DateTimeOffset(
                    completion.AddMinutes(-_defaultFocusMinutes)).ToString(
                        "o", CultureInfo.InvariantCulture),
                CompletedAt = new DateTimeOffset(completion).ToString(
                    "o", CultureInfo.InvariantCulture),
                PlannedMinutes = _defaultFocusMinutes,
                CountsTowardGoal = true,
                Notes = string.Empty
            };
            var viewModel = CreateSessionViewModel(record);
            viewModel.IsExpanded = true;
            _sessions.Add(viewModel);
            MarkDirty();
            UpdateSummary();
        }

        private void DeleteSession_Click(object sender, RoutedEventArgs e)
        {
            var element = sender as FrameworkElement;
            var viewModel = element == null
                ? null
                : element.DataContext as FocusSessionViewModel;
            if (viewModel == null) return;

            var result = MessageBox.Show(
                this,
                "确定删除这条番茄钟记录吗？",
                "删除记录",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);
            if (result != MessageBoxResult.Yes) return;

            viewModel.PropertyChanged -= SessionViewModel_PropertyChanged;
            _sessions.Remove(viewModel);
            MarkDirty();
            UpdateSummary();
        }

        private void DayField_Changed(object sender, TextChangedEventArgs e)
        {
            if (_loading) return;
            MarkDirty();
            UpdateSummary();
        }

        private void SessionField_Changed(object sender, RoutedEventArgs e)
        {
            if (_loading) return;
            MarkDirty();
            UpdateSummary();
        }

        private void SessionText_Changed(object sender, TextChangedEventArgs e)
        {
            SessionField_Changed(sender, e);
        }

        private void MarkDirty()
        {
            _dirty = true;
            StatusText.Text = "有尚未保存的修改。";
        }

        private void UpdateSummary()
        {
            if (_sessions == null) return;
            int target;
            int adjustment;
            int.TryParse(TargetCountBox.Text, out target);
            int.TryParse(MinuteAdjustmentBox.Text, out adjustment);

            var completed = _sessions.Count(item => item.CountsTowardGoal);
            var minutes = _sessions
                .Where(item => item.CountsTowardGoal)
                .Sum(item => item.GetMinutesOrZero());
            CompletedSummaryText.Text = completed + " / " + Math.Max(0, target);
            SessionMinutesText.Text = minutes + " 分钟";
            TotalMinutesText.Text = (minutes + adjustment) + " 分钟";
            GoalProgress.Maximum = target > 0 ? target : 1;
            GoalProgress.Value = target > 0
                ? Math.Min(GoalProgress.Maximum, Math.Max(0, completed))
                : 0;
            EmptySessionsText.Visibility = _sessions.Count == 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        private bool TrySaveCurrentDay(bool showFeedback)
        {
            if (_currentDay == null) return true;

            int target;
            if (!int.TryParse(TargetCountBox.Text, out target) ||
                target < 0 || target > 999)
            {
                ShowValidationMessage("今日目标请输入 0–999 之间的整数。");
                return false;
            }

            int adjustment;
            if (!int.TryParse(MinuteAdjustmentBox.Text, out adjustment) ||
                adjustment < -10000 || adjustment > 10000)
            {
                ShowValidationMessage(
                    "今日分钟调整请输入 -10000 到 10000 之间的整数。");
                return false;
            }

            var records = new List<FocusSessionRecord>();
            foreach (var viewModel in _sessions)
            {
                int minutes;
                if (!int.TryParse(viewModel.MinutesText, out minutes) ||
                    minutes < 1 || minutes > 1440)
                {
                    ShowValidationMessage(
                        "每个番茄钟的分钟数请输入 1–1440 之间的整数。");
                    viewModel.IsExpanded = true;
                    return false;
                }
                records.Add(viewModel.ToRecord(minutes));
            }

            var latest = _service.GetDay(_selectedDate);
            var currentIds = new HashSet<string>(
                records.Select(item => item.Id),
                StringComparer.Ordinal);
            foreach (var external in latest.Sessions ??
                     new List<FocusSessionRecord>())
            {
                if (external == null ||
                    _loadedSessionIds.Contains(external.Id) ||
                    currentIds.Contains(external.Id))
                    continue;
                records.Add(external);
                currentIds.Add(external.Id);
            }

            _currentDay.TargetCount = target;
            _currentDay.MinuteAdjustment = adjustment;
            _currentDay.DailyNotes = DailyNotesBox.Text ?? string.Empty;
            _currentDay.Sessions = records;

            try
            {
                _saving = true;
                _service.SaveDay(_currentDay);
                _dirty = false;
                LoadDay(_selectedDate);
                if (showFeedback)
                    StatusText.Text = "已保存。";
                return true;
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    this,
                    "暂时无法保存专注记录：\n" + exception.Message,
                    "专注记录",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return false;
            }
            finally
            {
                _saving = false;
            }
        }

        private void ShowValidationMessage(string message)
        {
            MessageBox.Show(
                this,
                message,
                "专注记录",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            TrySaveCurrentDay(true);
        }

        private void CopyDay_Click(object sender, RoutedEventArgs e)
        {
            if (!SavePendingChanges()) return;
            try
            {
                var day = _service.GetDay(_selectedDate);
                Clipboard.SetText(FocusJournalFormatter.BuildPlainText(day));
                StatusText.Text = "已把当天记录复制为纯文本。";
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    this,
                    "暂时无法复制：\n" + exception.Message,
                    "专注记录",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }

        private void ExportMarkdown_Click(object sender, RoutedEventArgs e)
        {
            if (!SavePendingChanges()) return;
            var dialog = new FocusExportWindow(_service, _selectedDate)
            {
                Owner = this
            };
            dialog.ShowDialog();
        }

        private void FocusJournalService_JournalChanged(
            object sender,
            EventArgs e)
        {
            if (_saving || !IsLoaded) return;
            Dispatcher.BeginInvoke(new Action(() =>
            {
                if (_saving || !IsLoaded) return;
                RefreshFromStore();
            }), DispatcherPriority.Background);
        }

        private void Window_Closing(object sender, CancelEventArgs e)
        {
            if (!_dirty) return;
            if (!TrySaveCurrentDay(false))
                e.Cancel = true;
        }

        private sealed class FocusSessionViewModel : INotifyPropertyChanged
        {
            private readonly FocusSessionRecord _record;
            private string _minutesText;
            private bool _countsTowardGoal;
            private string _notes;
            private bool _isExpanded;

            public FocusSessionViewModel(FocusSessionRecord record)
            {
                _record = record;
                _minutesText = record.PlannedMinutes.ToString(
                    CultureInfo.InvariantCulture);
                _countsTowardGoal = record.CountsTowardGoal;
                _notes = record.Notes ?? string.Empty;
            }

            public string Header
            {
                get
                {
                    var source = string.Equals(
                        _record.Source,
                        FocusSessionRecord.AutomaticSource,
                        StringComparison.OrdinalIgnoreCase)
                        ? "自动记录"
                        : "手动补记";
                    DateTimeOffset start;
                    DateTimeOffset completed;
                    var time = DateTimeOffset.TryParse(
                                   _record.StartedAt,
                                   CultureInfo.InvariantCulture,
                                   DateTimeStyles.None,
                                   out start) &&
                               DateTimeOffset.TryParse(
                                   _record.CompletedAt,
                                   CultureInfo.InvariantCulture,
                                   DateTimeStyles.None,
                                   out completed)
                        ? start.LocalDateTime.ToString("HH:mm") + "–" +
                          completed.LocalDateTime.ToString("HH:mm")
                        : "时间未记录";
                    return source + " · " + time + " · " +
                           MinutesText + " 分钟" +
                           (CountsTowardGoal ? string.Empty : " · 不计入");
                }
            }

            public string MinutesText
            {
                get { return _minutesText; }
                set
                {
                    if (_minutesText == value) return;
                    _minutesText = value;
                    RaisePropertyChanged("MinutesText");
                    RaisePropertyChanged("Header");
                }
            }

            public bool CountsTowardGoal
            {
                get { return _countsTowardGoal; }
                set
                {
                    if (_countsTowardGoal == value) return;
                    _countsTowardGoal = value;
                    RaisePropertyChanged("CountsTowardGoal");
                    RaisePropertyChanged("Header");
                }
            }

            public string Notes
            {
                get { return _notes; }
                set
                {
                    if (_notes == value) return;
                    _notes = value;
                    RaisePropertyChanged("Notes");
                }
            }

            public bool IsExpanded
            {
                get { return _isExpanded; }
                set
                {
                    if (_isExpanded == value) return;
                    _isExpanded = value;
                    RaisePropertyChanged("IsExpanded");
                }
            }

            public int GetMinutesOrZero()
            {
                int value;
                return int.TryParse(MinutesText, out value)
                    ? Math.Max(0, value)
                    : 0;
            }

            public FocusSessionRecord ToRecord(int minutes)
            {
                return new FocusSessionRecord
                {
                    Id = _record.Id,
                    Source = _record.Source,
                    StartedAt = _record.StartedAt,
                    CompletedAt = _record.CompletedAt,
                    PlannedMinutes = minutes,
                    CountsTowardGoal = CountsTowardGoal,
                    Notes = Notes ?? string.Empty
                };
            }

            public event PropertyChangedEventHandler PropertyChanged;

            private void RaisePropertyChanged(string propertyName)
            {
                var handler = PropertyChanged;
                if (handler != null)
                    handler(this, new PropertyChangedEventArgs(propertyName));
            }
        }
    }
}
