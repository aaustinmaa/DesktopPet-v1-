using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.Serialization.Json;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public sealed class ActiveFocusStateService
    {
        public string StatePath =>
            Path.Combine(
                SettingsService.DataDirectory,
                "active-focus.json");

        public ActiveFocusStateData Load()
        {
            return Normalize(TryLoad(StatePath)) ??
                Normalize(TryLoad(StatePath + ".bak"));
        }

        public void Save(ActiveFocusStateData state)
        {
            var normalized = Normalize(Clone(state));
            if (normalized == null)
                throw new ArgumentException(
                    "进行中的番茄钟状态无效。",
                    nameof(state));

            Directory.CreateDirectory(SettingsService.DataDirectory);
            var temporaryPath = StatePath + ".tmp";
            var backupPath = StatePath + ".bak";
            if (File.Exists(temporaryPath))
                File.Delete(temporaryPath);

            try
            {
                using (var stream = File.Create(temporaryPath))
                {
                    var serializer = new DataContractJsonSerializer(
                        typeof(ActiveFocusStateData));
                    serializer.WriteObject(stream, normalized);
                    stream.Flush();
                }

                if (File.Exists(StatePath))
                    File.Replace(
                        temporaryPath,
                        StatePath,
                        backupPath,
                        true);
                else
                    File.Move(temporaryPath, StatePath);
            }
            finally
            {
                if (File.Exists(temporaryPath))
                    File.Delete(temporaryPath);
            }
        }

        public void Clear()
        {
            DeleteIfPresent(StatePath + ".tmp");
            DeleteIfPresent(StatePath);
            DeleteIfPresent(StatePath + ".bak");
        }

        private static ActiveFocusStateData TryLoad(string path)
        {
            try
            {
                if (!File.Exists(path))
                    return null;

                using (var stream = File.OpenRead(path))
                {
                    var serializer = new DataContractJsonSerializer(
                        typeof(ActiveFocusStateData));
                    return serializer.ReadObject(stream)
                        as ActiveFocusStateData;
                }
            }
            catch
            {
                return null;
            }
        }

        private static ActiveFocusStateData Normalize(
            ActiveFocusStateData state)
        {
            if (state == null ||
                state.PlannedMinutes < 1 ||
                double.IsNaN(state.RemainingSeconds) ||
                double.IsInfinity(state.RemainingSeconds) ||
                state.RemainingSeconds <= 0 ||
                state.RemainingSeconds >
                    state.PlannedMinutes * 60.0 + 1)
            {
                return null;
            }

            DateTimeOffset startedAt;
            DateTimeOffset savedAt;
            if (!TryParse(state.StartedAt, out startedAt) ||
                !TryParse(state.SavedAt, out savedAt))
            {
                return null;
            }

            state.Version = Math.Max(1, state.Version);
            state.StartedAt = startedAt.ToString(
                "o",
                CultureInfo.InvariantCulture);
            state.SavedAt = savedAt.ToString(
                "o",
                CultureInfo.InvariantCulture);
            if (state.Segments == null)
                state.Segments =
                    new List<ActiveFocusSegmentData>();

            var normalizedSegments =
                new List<ActiveFocusSegmentData>();
            foreach (var segment in state.Segments
                .Where(item => item != null))
            {
                DateTimeOffset segmentStart;
                DateTimeOffset segmentEnd;
                if (!TryParse(segment.StartedAt, out segmentStart) ||
                    !TryParse(segment.EndedAt, out segmentEnd) ||
                    segmentEnd <= segmentStart)
                {
                    continue;
                }

                normalizedSegments.Add(
                    new ActiveFocusSegmentData
                    {
                        StartedAt = segmentStart.ToString(
                            "o",
                            CultureInfo.InvariantCulture),
                        EndedAt = segmentEnd.ToString(
                            "o",
                            CultureInfo.InvariantCulture)
                    });
            }

            state.Segments = normalizedSegments
                .OrderBy(item => item.StartedAt, StringComparer.Ordinal)
                .ToList();
            return state;
        }

        private static bool TryParse(
            string value,
            out DateTimeOffset timestamp)
        {
            return DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out timestamp);
        }

        private static ActiveFocusStateData Clone(
            ActiveFocusStateData source)
        {
            if (source == null)
                return null;

            return new ActiveFocusStateData
            {
                Version = source.Version,
                StartedAt = source.StartedAt,
                PlannedMinutes = source.PlannedMinutes,
                RemainingSeconds = source.RemainingSeconds,
                WasPaused = source.WasPaused,
                SavedAt = source.SavedAt,
                Segments = (source.Segments ??
                    new List<ActiveFocusSegmentData>())
                    .Where(item => item != null)
                    .Select(item =>
                        new ActiveFocusSegmentData
                        {
                            StartedAt = item.StartedAt,
                            EndedAt = item.EndedAt
                        })
                    .ToList()
            };
        }

        private static void DeleteIfPresent(string path)
        {
            if (File.Exists(path))
                File.Delete(path);
        }
    }
}
