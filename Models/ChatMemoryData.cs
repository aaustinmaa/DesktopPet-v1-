using System.Collections.Generic;
using System.Runtime.Serialization;

namespace DesktopPet.Models
{
    [DataContract]
    public class ChatMemoryData
    {
        [DataMember] public int Version { get; set; } = 1;
        [DataMember] public List<ChatRecord> History { get; set; } = new List<ChatRecord>();
        [DataMember] public List<MemoryFact> Facts { get; set; } = new List<MemoryFact>();
    }

    [DataContract]
    public class ChatRecord
    {
        [DataMember] public string Role { get; set; }
        [DataMember] public string Content { get; set; }
        [DataMember] public string CreatedAtUtc { get; set; }
    }

    [DataContract]
    public class MemoryFact
    {
        [DataMember] public string Text { get; set; }
        [DataMember] public string CreatedAtUtc { get; set; }
    }

    public class MemoryUpdate
    {
        public string RememberedFact { get; set; }
        public int ForgottenCount { get; set; }
    }

    public class CodexAccountStatus
    {
        public bool IsAvailable { get; set; }
        public bool IsSignedIn { get; set; }
        public string Email { get; set; }
        public string PlanType { get; set; }
        public string Error { get; set; }
    }

    public class CodexModelOption
    {
        public string ModelId { get; set; }
        public string DisplayName { get; set; }
        public string Description { get; set; }
        public bool IsDefault { get; set; }

        public string DisplayLabel
        {
            get
            {
                if (string.IsNullOrWhiteSpace(ModelId))
                    return "自动选择（推荐）";
                return DisplayName + (IsDefault ? " · 默认" : string.Empty);
            }
        }
    }
}
