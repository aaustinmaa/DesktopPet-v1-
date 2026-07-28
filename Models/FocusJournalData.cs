using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.Serialization;

namespace DesktopPet.Models
{
    [DataContract]
    public class FocusJournalData
    {
        [DataMember(Order = 1)]
        public int Version { get; set; } = 1;

        [DataMember(Order = 2)]
        public List<DailyFocusRecord> Days { get; set; } = new List<DailyFocusRecord>();
    }

    [DataContract]
    public class DailyFocusRecord
    {
        [DataMember(Order = 1)]
        public string Date { get; set; }

        [DataMember(Order = 2)]
        public int TargetCount { get; set; }

        [DataMember(Order = 3)]
        public int MinuteAdjustment { get; set; }

        [DataMember(Order = 4)]
        public string DailyNotes { get; set; }

        [DataMember(Order = 5)]
        public List<FocusSessionRecord> Sessions { get; set; } = new List<FocusSessionRecord>();

        public int CompletedCount
        {
            get
            {
                return (Sessions ?? new List<FocusSessionRecord>())
                    .Count(session => session != null && session.CountsTowardGoal);
            }
        }

        public int SessionMinutes
        {
            get
            {
                return (Sessions ?? new List<FocusSessionRecord>())
                    .Where(session => session != null && session.CountsTowardGoal)
                    .Sum(session => Math.Max(0, session.PlannedMinutes));
            }
        }

        public int TotalMinutes => SessionMinutes + MinuteAdjustment;
    }

    [DataContract]
    public class FocusSessionRecord
    {
        public const string AutomaticSource = "automatic";
        public const string ManualSource = "manual";

        [DataMember(Order = 1)]
        public string Id { get; set; }

        [DataMember(Order = 2)]
        public string Source { get; set; }

        [DataMember(Order = 3)]
        public string StartedAt { get; set; }

        [DataMember(Order = 4)]
        public string CompletedAt { get; set; }

        [DataMember(Order = 5)]
        public int PlannedMinutes { get; set; }

        [DataMember(Order = 6)]
        public bool CountsTowardGoal { get; set; } = true;

        [DataMember(Order = 7)]
        public string Notes { get; set; }
    }
}
