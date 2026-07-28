using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.Serialization.Json;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public sealed class FocusJournalService
    {
        private const string DateFormat = "yyyy-MM-dd";
        private static readonly Lazy<FocusJournalService> SharedService =
            new Lazy<FocusJournalService>(() => new FocusJournalService(), true);

        private readonly object _sync = new object();
        private FocusJournalData _data;

        public FocusJournalService()
        {
            _data = Load();
        }

        public static FocusJournalService Shared => SharedService.Value;

        public static FocusJournalService Instance => Shared;

        public string JournalPath =>
            Path.Combine(SettingsService.DataDirectory, "focus-journal.json");

        public event EventHandler JournalChanged;

        public DailyFocusRecord GetDay(DateTime date)
        {
            return GetDay(ToDateKey(date));
        }

        public DailyFocusRecord GetDay(string date)
        {
            var dateKey = ValidateDateKey(date);
            lock (_sync)
            {
                var day = _data.Days.FirstOrDefault(item =>
                    string.Equals(item.Date, dateKey, StringComparison.Ordinal));
                return day == null
                    ? CreateEmptyDay(dateKey)
                    : CloneDay(day);
            }
        }

        public void SaveDay(DailyFocusRecord day)
        {
            if (day == null)
                throw new ArgumentNullException(nameof(day));

            var savedDay = CloneDay(day);
            NormalizeDay(savedDay, true);

            lock (_sync)
            {
                var existingIndex = _data.Days.FindIndex(item =>
                    string.Equals(item.Date, savedDay.Date, StringComparison.Ordinal));
                if (existingIndex >= 0)
                    _data.Days[existingIndex] = savedDay;
                else
                    _data.Days.Add(savedDay);

                SortDaysUnsafe();
                SaveUnsafe();
            }

            RaiseJournalChanged();
        }

        public FocusSessionRecord RecordCompletedSession(
            DateTime startedAt,
            DateTime completedAt,
            int plannedMinutes,
            string notes = null)
        {
            if (plannedMinutes < 0)
                throw new ArgumentOutOfRangeException(nameof(plannedMinutes));

            var localStart = AsLocalTime(startedAt);
            var localCompletion = AsLocalTime(completedAt);
            var session = new FocusSessionRecord
            {
                Id = Guid.NewGuid().ToString("D"),
                Source = FocusSessionRecord.AutomaticSource,
                StartedAt = localStart.ToString("o", CultureInfo.InvariantCulture),
                CompletedAt = localCompletion.ToString("o", CultureInfo.InvariantCulture),
                PlannedMinutes = plannedMinutes,
                CountsTowardGoal = true,
                Notes = notes ?? string.Empty
            };

            return RecordCompletedSession(session);
        }

        public FocusSessionRecord RecordCompletedSession(FocusSessionRecord session)
        {
            if (session == null)
                throw new ArgumentNullException(nameof(session));

            var savedSession = CloneSession(session);
            NormalizeSession(savedSession);
            var completedAt = ParseRequiredTimestamp(
                savedSession.CompletedAt, nameof(session.CompletedAt));
            var dateKey = completedAt.LocalDateTime.ToString(DateFormat, CultureInfo.InvariantCulture);

            lock (_sync)
            {
                var day = _data.Days.FirstOrDefault(item =>
                    string.Equals(item.Date, dateKey, StringComparison.Ordinal));
                if (day == null)
                {
                    day = CreateEmptyDay(dateKey);
                    _data.Days.Add(day);
                }

                var existingIndex = day.Sessions.FindIndex(item =>
                    string.Equals(item.Id, savedSession.Id, StringComparison.Ordinal));
                if (existingIndex >= 0)
                    day.Sessions[existingIndex] = savedSession;
                else
                    day.Sessions.Add(savedSession);

                SortDaysUnsafe();
                SaveUnsafe();
            }

            RaiseJournalChanged();
            return CloneSession(savedSession);
        }

        public IList<DailyFocusRecord> GetRange(DateTime startDate, DateTime endDate)
        {
            return GetRange(ToDateKey(startDate), ToDateKey(endDate));
        }

        public IList<DailyFocusRecord> GetRange(string startDate, string endDate)
        {
            var startKey = ValidateDateKey(startDate);
            var endKey = ValidateDateKey(endDate);
            if (string.CompareOrdinal(startKey, endKey) > 0)
                throw new ArgumentException("开始日期不能晚于结束日期。");

            lock (_sync)
            {
                return _data.Days
                    .Where(day =>
                        string.CompareOrdinal(day.Date, startKey) >= 0 &&
                        string.CompareOrdinal(day.Date, endKey) <= 0)
                    .OrderBy(day => day.Date, StringComparer.Ordinal)
                    .Select(CloneDay)
                    .ToList();
            }
        }

        private FocusJournalData Load()
        {
            var loaded = TryLoad(JournalPath);
            if (loaded == null)
                loaded = TryLoad(JournalPath + ".bak");
            if (loaded == null)
                loaded = new FocusJournalData();

            NormalizeData(loaded);
            return loaded;
        }

        private static FocusJournalData TryLoad(string path)
        {
            try
            {
                if (!File.Exists(path))
                    return null;

                using (var stream = File.OpenRead(path))
                {
                    var serializer = new DataContractJsonSerializer(typeof(FocusJournalData));
                    return serializer.ReadObject(stream) as FocusJournalData;
                }
            }
            catch
            {
                return null;
            }
        }

        private void SaveUnsafe()
        {
            Directory.CreateDirectory(SettingsService.DataDirectory);
            var temporaryPath = JournalPath + ".tmp";
            var backupPath = JournalPath + ".bak";

            if (File.Exists(temporaryPath))
                File.Delete(temporaryPath);

            try
            {
                using (var stream = File.Create(temporaryPath))
                {
                    var serializer = new DataContractJsonSerializer(typeof(FocusJournalData));
                    serializer.WriteObject(stream, _data);
                    stream.Flush();
                }

                if (File.Exists(JournalPath))
                    File.Replace(temporaryPath, JournalPath, backupPath, true);
                else
                    File.Move(temporaryPath, JournalPath);
            }
            finally
            {
                if (File.Exists(temporaryPath))
                    File.Delete(temporaryPath);
            }
        }

        private void SortDaysUnsafe()
        {
            _data.Days.Sort((left, right) =>
                string.CompareOrdinal(left.Date, right.Date));
        }

        private void RaiseJournalChanged()
        {
            var handler = JournalChanged;
            if (handler != null)
                handler(this, EventArgs.Empty);
        }

        private static void NormalizeData(FocusJournalData data)
        {
            if (data.Version <= 0)
                data.Version = 1;
            if (data.Days == null)
                data.Days = new List<DailyFocusRecord>();

            var normalizedDays = new Dictionary<string, DailyFocusRecord>(
                StringComparer.Ordinal);
            foreach (var sourceDay in data.Days.Where(day => day != null))
            {
                try
                {
                    NormalizeDay(sourceDay, true);
                    normalizedDays[sourceDay.Date] = sourceDay;
                }
                catch (ArgumentException)
                {
                    // Ignore corrupt records while preserving all other readable days.
                }
            }

            data.Days = normalizedDays.Values
                .OrderBy(day => day.Date, StringComparer.Ordinal)
                .ToList();
        }

        private static void NormalizeDay(DailyFocusRecord day, bool requireDate)
        {
            if (requireDate)
                day.Date = ValidateDateKey(day.Date);
            if (day.TargetCount < 0)
                day.TargetCount = 0;
            if (day.DailyNotes == null)
                day.DailyNotes = string.Empty;
            if (day.Sessions == null)
                day.Sessions = new List<FocusSessionRecord>();

            var normalizedSessions = new List<FocusSessionRecord>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var session in day.Sessions.Where(item => item != null))
            {
                NormalizeSession(session);
                if (!ids.Add(session.Id))
                    session.Id = Guid.NewGuid().ToString("D");
                ids.Add(session.Id);
                normalizedSessions.Add(session);
            }
            day.Sessions = normalizedSessions;
        }

        private static void NormalizeSession(FocusSessionRecord session)
        {
            if (string.IsNullOrWhiteSpace(session.Id))
                session.Id = Guid.NewGuid().ToString("D");
            else
                session.Id = session.Id.Trim();

            session.Source = string.Equals(
                session.Source,
                FocusSessionRecord.AutomaticSource,
                StringComparison.OrdinalIgnoreCase)
                ? FocusSessionRecord.AutomaticSource
                : FocusSessionRecord.ManualSource;
            session.StartedAt = NormalizeOptionalTimestamp(session.StartedAt);
            session.CompletedAt = NormalizeOptionalTimestamp(session.CompletedAt);
            if (session.PlannedMinutes < 0)
                session.PlannedMinutes = 0;
            if (session.Notes == null)
                session.Notes = string.Empty;
        }

        private static string NormalizeOptionalTimestamp(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return string.Empty;

            DateTimeOffset parsed;
            return DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out parsed)
                ? parsed.ToString("o", CultureInfo.InvariantCulture)
                : string.Empty;
        }

        private static DateTimeOffset ParseRequiredTimestamp(string value, string parameterName)
        {
            DateTimeOffset parsed;
            if (string.IsNullOrWhiteSpace(value) ||
                !DateTimeOffset.TryParse(
                    value,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out parsed))
            {
                throw new ArgumentException("完成时间必须是有效的 ISO 8601 时间。", parameterName);
            }
            return parsed;
        }

        private static DateTime AsLocalTime(DateTime value)
        {
            if (value.Kind == DateTimeKind.Utc)
                return value.ToLocalTime();
            if (value.Kind == DateTimeKind.Unspecified)
                return DateTime.SpecifyKind(value, DateTimeKind.Local);
            return value;
        }

        private static string ToDateKey(DateTime value)
        {
            return AsLocalTime(value).Date.ToString(DateFormat, CultureInfo.InvariantCulture);
        }

        private static string ValidateDateKey(string value)
        {
            DateTime parsed;
            if (string.IsNullOrWhiteSpace(value) ||
                !DateTime.TryParseExact(
                    value.Trim(),
                    DateFormat,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out parsed))
            {
                throw new ArgumentException("日期必须使用 yyyy-MM-dd 格式。", nameof(value));
            }
            return parsed.ToString(DateFormat, CultureInfo.InvariantCulture);
        }

        private static DailyFocusRecord CreateEmptyDay(string dateKey)
        {
            return new DailyFocusRecord
            {
                Date = dateKey,
                DailyNotes = string.Empty,
                Sessions = new List<FocusSessionRecord>()
            };
        }

        private static DailyFocusRecord CloneDay(DailyFocusRecord source)
        {
            return new DailyFocusRecord
            {
                Date = source.Date,
                TargetCount = source.TargetCount,
                MinuteAdjustment = source.MinuteAdjustment,
                DailyNotes = source.DailyNotes,
                Sessions = (source.Sessions ?? new List<FocusSessionRecord>())
                    .Where(session => session != null)
                    .Select(CloneSession)
                    .ToList()
            };
        }

        private static FocusSessionRecord CloneSession(FocusSessionRecord source)
        {
            return new FocusSessionRecord
            {
                Id = source.Id,
                Source = source.Source,
                StartedAt = source.StartedAt,
                CompletedAt = source.CompletedAt,
                PlannedMinutes = source.PlannedMinutes,
                CountsTowardGoal = source.CountsTowardGoal,
                Notes = source.Notes
            };
        }
    }
}
