using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public static class FocusJournalFormatter
    {
        public static string BuildPlainText(DailyFocusRecord day)
        {
            if (day == null)
                throw new ArgumentNullException(nameof(day));

            var builder = new StringBuilder();
            builder.AppendLine((day.Date ?? string.Empty) + " 专注记录");
            builder.AppendLine();
            AppendSummary(builder, day, string.Empty);
            builder.AppendLine();
            builder.AppendLine("番茄钟：");
            AppendPlainSessions(builder, day.Sessions);

            if (!string.IsNullOrWhiteSpace(day.DailyNotes))
            {
                builder.AppendLine();
                builder.AppendLine("今日 Notes：");
                builder.AppendLine(day.DailyNotes.Trim());
            }

            return builder.ToString().TrimEnd();
        }

        public static string BuildMarkdown(IEnumerable<DailyFocusRecord> days)
        {
            if (days == null)
                throw new ArgumentNullException(nameof(days));

            var records = days
                .Where(day => day != null)
                .OrderBy(day => day.Date, StringComparer.Ordinal)
                .ToList();
            var builder = new StringBuilder();
            builder.AppendLine("# 专注记录");

            if (records.Count == 0)
            {
                builder.AppendLine();
                builder.AppendLine("所选日期范围内没有记录。");
                return builder.ToString().TrimEnd();
            }

            foreach (var day in records)
            {
                builder.AppendLine();
                builder.AppendLine("## " + EscapeInline(day.Date));
                builder.AppendLine();
                AppendSummary(builder, day, "- ");
                builder.AppendLine();
                builder.AppendLine("### 番茄钟");
                builder.AppendLine();
                AppendMarkdownSessions(builder, day.Sessions);

                if (!string.IsNullOrWhiteSpace(day.DailyNotes))
                {
                    builder.AppendLine();
                    builder.AppendLine("### 今日 Notes");
                    builder.AppendLine();
                    builder.AppendLine(day.DailyNotes.Trim());
                }
            }

            return builder.ToString().TrimEnd();
        }

        private static void AppendSummary(
            StringBuilder builder,
            DailyFocusRecord day,
            string prefix)
        {
            builder.AppendLine(prefix + "目标：" + day.TargetCount + " 个");
            builder.AppendLine(prefix + "完成：" + day.CompletedCount + " 个");
            builder.AppendLine(prefix + "番茄钟时间：" + day.SessionMinutes + " 分钟");
            builder.AppendLine(
                prefix + "分钟调整：" + FormatSignedMinutes(day.MinuteAdjustment));
            builder.AppendLine(prefix + "最终计入：" + day.TotalMinutes + " 分钟");
        }

        private static void AppendPlainSessions(
            StringBuilder builder,
            IList<FocusSessionRecord> sessions)
        {
            var records = sessions ?? new List<FocusSessionRecord>();
            if (records.Count == 0)
            {
                builder.AppendLine("无");
                return;
            }

            for (var index = 0; index < records.Count; index++)
            {
                var session = records[index];
                if (session == null)
                    continue;
                builder.Append(index + 1);
                builder.Append(". ");
                builder.Append(FormatSessionTime(session));
                builder.Append("（");
                builder.Append(session.PlannedMinutes);
                builder.Append(" 分钟）");
                if (!session.CountsTowardGoal)
                    builder.Append(" [不计入完成数]");
                if (!string.IsNullOrWhiteSpace(session.Notes))
                {
                    builder.Append(" — ");
                    builder.Append(session.Notes.Trim());
                }
                builder.AppendLine();
            }
        }

        private static void AppendMarkdownSessions(
            StringBuilder builder,
            IList<FocusSessionRecord> sessions)
        {
            var records = sessions ?? new List<FocusSessionRecord>();
            if (records.Count == 0)
            {
                builder.AppendLine("无");
                return;
            }

            var visibleIndex = 1;
            foreach (var session in records.Where(item => item != null))
            {
                builder.Append(visibleIndex++);
                builder.Append(". `");
                builder.Append(FormatSessionTime(session));
                builder.Append("` · ");
                builder.Append(session.PlannedMinutes);
                builder.Append(" 分钟");
                if (!session.CountsTowardGoal)
                    builder.Append(" · 不计入完成数");
                if (!string.IsNullOrWhiteSpace(session.Notes))
                {
                    builder.Append(" — ");
                    builder.Append(EscapeInline(CollapseLines(session.Notes)));
                }
                builder.AppendLine();
            }
        }

        private static string FormatSessionTime(FocusSessionRecord session)
        {
            DateTimeOffset start;
            DateTimeOffset completion;
            var hasStart = TryParseTimestamp(session.StartedAt, out start);
            var hasCompletion = TryParseTimestamp(session.CompletedAt, out completion);

            if (hasStart && hasCompletion)
            {
                return start.LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture) +
                    "–" +
                    completion.LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture);
            }
            if (hasCompletion)
                return completion.LocalDateTime.ToString("HH:mm", CultureInfo.InvariantCulture);
            if (string.Equals(
                session.Source,
                FocusSessionRecord.ManualSource,
                StringComparison.OrdinalIgnoreCase))
            {
                return "手动补记";
            }
            return "时间未记录";
        }

        private static bool TryParseTimestamp(string value, out DateTimeOffset timestamp)
        {
            return DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out timestamp);
        }

        private static string FormatSignedMinutes(int minutes)
        {
            return (minutes > 0 ? "+" : string.Empty) +
                minutes.ToString(CultureInfo.InvariantCulture) +
                " 分钟";
        }

        private static string CollapseLines(string value)
        {
            return value
                .Replace("\r\n", " ")
                .Replace('\r', ' ')
                .Replace('\n', ' ')
                .Trim();
        }

        private static string EscapeInline(string value)
        {
            return (value ?? string.Empty)
                .Replace("\\", "\\\\")
                .Replace("*", "\\*")
                .Replace("_", "\\_")
                .Replace("`", "\\`")
                .Replace("[", "\\[")
                .Replace("]", "\\]");
        }
    }
}
