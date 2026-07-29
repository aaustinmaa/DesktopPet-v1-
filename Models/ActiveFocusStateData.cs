using System.Collections.Generic;
using System.Runtime.Serialization;

namespace DesktopPet.Models
{
    [DataContract]
    public sealed class ActiveFocusStateData
    {
        [DataMember(Order = 1)]
        public int Version { get; set; } = 1;

        [DataMember(Order = 2)]
        public string StartedAt { get; set; }

        [DataMember(Order = 3)]
        public int PlannedMinutes { get; set; }

        [DataMember(Order = 4)]
        public double RemainingSeconds { get; set; }

        [DataMember(Order = 5)]
        public bool WasPaused { get; set; }

        [DataMember(Order = 6)]
        public string SavedAt { get; set; }

        [DataMember(Order = 7)]
        public List<ActiveFocusSegmentData> Segments { get; set; } =
            new List<ActiveFocusSegmentData>();
    }

    [DataContract]
    public sealed class ActiveFocusSegmentData
    {
        [DataMember(Order = 1)]
        public string StartedAt { get; set; }

        [DataMember(Order = 2)]
        public string EndedAt { get; set; }
    }
}
