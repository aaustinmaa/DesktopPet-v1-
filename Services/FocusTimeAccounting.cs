using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace DesktopPet.Services
{
    public sealed class FocusTimeSegment
    {
        public FocusTimeSegment(DateTime startedAt, DateTime endedAt)
        {
            StartedAt = startedAt;
            EndedAt = endedAt;
        }

        public DateTime StartedAt { get; }

        public DateTime EndedAt { get; }
    }

    public static class FocusTimeAccounting
    {
        private const string DateFormat = "yyyy-MM-dd";
        private static readonly TimeSpan JournalDayEndsAt =
            TimeSpan.FromHours(21);

        public static DateTime GetJournalDate(DateTime instant)
        {
            var local = AsLocalTime(instant);
            return local.TimeOfDay >= JournalDayEndsAt
                ? local.Date.AddDays(1)
                : local.Date;
        }

        public static string GetJournalDateKey(DateTime instant)
        {
            return GetJournalDate(instant).ToString(
                DateFormat,
                CultureInfo.InvariantCulture);
        }

        public static int GetCompletedWholeMinutes(
            IEnumerable<FocusTimeSegment> segments,
            int maximumMinutes)
        {
            if (segments == null)
                throw new ArgumentNullException(nameof(segments));
            if (maximumMinutes < 0)
                throw new ArgumentOutOfRangeException(nameof(maximumMinutes));

            var totalTicks = GetValidSegments(segments)
                .Sum(segment => (segment.EndedAt - segment.StartedAt).Ticks);
            var wholeMinutes = totalTicks / TimeSpan.TicksPerMinute;
            return (int)Math.Min(maximumMinutes, wholeMinutes);
        }

        public static IDictionary<string, int> AllocateMinutes(
            IEnumerable<FocusTimeSegment> segments,
            int totalMinutes)
        {
            if (segments == null)
                throw new ArgumentNullException(nameof(segments));
            if (totalMinutes < 0)
                throw new ArgumentOutOfRangeException(nameof(totalMinutes));

            var ticksByDate = new Dictionary<string, long>(
                StringComparer.Ordinal);
            foreach (var segment in GetValidSegments(segments))
            {
                var cursor = AsLocalTime(segment.StartedAt);
                var end = AsLocalTime(segment.EndedAt);
                while (cursor < end)
                {
                    var journalDate = GetJournalDate(cursor);
                    var nextBoundary = journalDate.Add(JournalDayEndsAt);
                    var partEnd = end < nextBoundary ? end : nextBoundary;
                    var dateKey = journalDate.ToString(
                        DateFormat,
                        CultureInfo.InvariantCulture);
                    long existing;
                    ticksByDate.TryGetValue(dateKey, out existing);
                    ticksByDate[dateKey] =
                        checked(existing + (partEnd - cursor).Ticks);
                    cursor = partEnd;
                }
            }

            if (totalMinutes == 0 || ticksByDate.Count == 0)
                return new Dictionary<string, int>(StringComparer.Ordinal);

            var totalTicks = ticksByDate.Values.Sum();
            if (totalTicks <= 0)
                return new Dictionary<string, int>(StringComparer.Ordinal);

            var shares = ticksByDate
                .Select(item =>
                {
                    var exact =
                        totalMinutes * (double)item.Value / totalTicks;
                    var minutes = (int)Math.Floor(exact);
                    return new AllocationShare
                    {
                        Date = item.Key,
                        Minutes = minutes,
                        Remainder = exact - minutes
                    };
                })
                .OrderBy(item => item.Date, StringComparer.Ordinal)
                .ToList();

            var minutesLeft = totalMinutes -
                shares.Sum(item => item.Minutes);
            foreach (var share in shares
                .OrderByDescending(item => item.Remainder)
                .ThenBy(item => item.Date, StringComparer.Ordinal)
                .Take(minutesLeft))
            {
                share.Minutes++;
            }

            return shares
                .Where(item => item.Minutes > 0)
                .ToDictionary(
                    item => item.Date,
                    item => item.Minutes,
                    StringComparer.Ordinal);
        }

        private static IEnumerable<FocusTimeSegment> GetValidSegments(
            IEnumerable<FocusTimeSegment> segments)
        {
            return segments.Where(segment =>
                segment != null &&
                AsLocalTime(segment.EndedAt) >
                AsLocalTime(segment.StartedAt));
        }

        private static DateTime AsLocalTime(DateTime value)
        {
            if (value.Kind == DateTimeKind.Utc)
                return value.ToLocalTime();
            if (value.Kind == DateTimeKind.Unspecified)
                return DateTime.SpecifyKind(value, DateTimeKind.Local);
            return value;
        }

        private sealed class AllocationShare
        {
            public string Date { get; set; }

            public int Minutes { get; set; }

            public double Remainder { get; set; }
        }
    }
}
