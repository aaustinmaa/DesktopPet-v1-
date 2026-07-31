using System.Collections.Generic;
using System.Runtime.Serialization;

namespace DesktopPet.Models
{
    [DataContract]
    public class ChatMemoryData
    {
        [DataMember] public int Version { get; set; } = 2;
        [DataMember] public List<ChatThreadData> Threads { get; set; } =
            new List<ChatThreadData>();
        // Version 1 stored every message in one flat history. Keep this member
        // for a lossless migration into a regular thread.
        [DataMember] public List<ChatRecord> History { get; set; } = new List<ChatRecord>();
        [DataMember] public List<MemoryFact> Facts { get; set; } = new List<MemoryFact>();
    }

    [DataContract]
    public class ChatThreadData
    {
        [DataMember] public string Id { get; set; }
        [DataMember] public string Title { get; set; }
        [DataMember] public string Summary { get; set; }
        [DataMember] public string CreatedAtUtc { get; set; }
        [DataMember] public string UpdatedAtUtc { get; set; }
        [DataMember] public bool IsArchived { get; set; }
        [DataMember] public List<ChatRecord> Messages { get; set; } =
            new List<ChatRecord>();
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
        public string DefaultReasoningEffort { get; set; }
        public List<CodexReasoningEffortOption> SupportedReasoningEfforts { get; set; } =
            new List<CodexReasoningEffortOption>();

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

    public class CodexReasoningEffortOption
    {
        public string Effort { get; set; }
        public string Description { get; set; }
        public bool IsModelDefault { get; set; }

        public string DisplayLabel
        {
            get
            {
                if (string.IsNullOrWhiteSpace(Effort))
                    return "自动选择（模型默认）";
                return GetLocalizedName(Effort) +
                    (IsModelDefault ? " · 默认" : string.Empty);
            }
        }

        private static string GetLocalizedName(string effort)
        {
            switch ((effort ?? string.Empty).Trim().ToLowerInvariant())
            {
                case "minimal": return "极简 · Minimal";
                case "low": return "较快 · Low";
                case "medium": return "均衡 · Medium";
                case "high": return "深入 · High";
                case "xhigh": return "更深入 · XHigh";
                case "max": return "最大 · Max";
                case "ultra": return "极致 · Ultra";
                default: return effort;
            }
        }
    }
}
