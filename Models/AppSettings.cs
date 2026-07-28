using System.Runtime.Serialization;

namespace DesktopPet.Models
{
    [DataContract]
    public class AppSettings
    {
        [DataMember] public int SettingsVersion { get; set; } = 5;
        [DataMember] public double WindowLeft { get; set; } = double.NaN;
        [DataMember] public double WindowTop { get; set; } = double.NaN;
        [DataMember] public double PetScale { get; set; } = 0.82;
        [DataMember] public bool Topmost { get; set; } = true;
        [DataMember] public bool StartWithWindows { get; set; } = false;
        [DataMember] public bool AutoWander { get; set; } = false;
        [DataMember] public bool HydrationEnabled { get; set; } = true;
        [DataMember] public int HydrationMinutes { get; set; } = 45;
        [DataMember] public int FocusMinutes { get; set; } = 25;
        [DataMember] public string FocusStartSound { get; set; } = "gentle";
        [DataMember] public string FocusCompleteSound { get; set; } = "bell";
        [DataMember] public bool RandomCueEnabled { get; set; } = true;
        [DataMember] public int RandomCueMinMinutes { get; set; } = 3;
        [DataMember] public int RandomCueMaxMinutes { get; set; } = 5;
        [DataMember] public int RandomCueBreakSeconds { get; set; } = 10;
        [DataMember] public string RandomCueBreakSound { get; set; } = "bell";
        [DataMember] public string RandomCueResumeSound { get; set; } = "pixel";
        [DataMember] public string PetName { get; set; } = "苏无度";
        [DataMember] public string AiProvider { get; set; } = "codex";
        [DataMember] public string AiModel { get; set; } = "gpt-5.6-sol";
        [DataMember] public string CodexModel { get; set; } = "";
        [DataMember] public string CodexReasoningEffort { get; set; } = "";
        [DataMember] public bool MemoryEnabled { get; set; } = true;
        [DataMember] public bool FirstRunComplete { get; set; } = false;

        public AppSettings Clone()
        {
            return (AppSettings)MemberwiseClone();
        }

        public void Normalize()
        {
            if (SettingsVersion < 2)
            {
                AiProvider = "codex";
                MemoryEnabled = true;
            }
            if (SettingsVersion < 3)
                CodexReasoningEffort = string.Empty;
            if (SettingsVersion < 4)
            {
                FocusStartSound = "gentle";
                FocusCompleteSound = "bell";
            }
            if (SettingsVersion < 5)
            {
                RandomCueEnabled = true;
                RandomCueMinMinutes = 3;
                RandomCueMaxMinutes = 5;
                RandomCueBreakSeconds = 10;
                RandomCueBreakSound = "bell";
                RandomCueResumeSound = "pixel";
            }
            SettingsVersion = 5;
            if (PetScale < 0.55) PetScale = 0.55;
            if (PetScale > 1.5) PetScale = 1.5;
            if (HydrationMinutes < 10) HydrationMinutes = 10;
            if (HydrationMinutes > 240) HydrationMinutes = 240;
            if (FocusMinutes < 1) FocusMinutes = 1;
            if (FocusMinutes > 120) FocusMinutes = 120;
            if (RandomCueMinMinutes < 1) RandomCueMinMinutes = 1;
            if (RandomCueMinMinutes > 120) RandomCueMinMinutes = 120;
            if (RandomCueMaxMinutes < RandomCueMinMinutes)
                RandomCueMaxMinutes = RandomCueMinMinutes;
            if (RandomCueMaxMinutes > 120) RandomCueMaxMinutes = 120;
            if (RandomCueBreakSeconds < 1) RandomCueBreakSeconds = 1;
            if (RandomCueBreakSeconds > 300) RandomCueBreakSeconds = 300;
            if (!Services.SoundService.IsValidSoundId(FocusStartSound))
                FocusStartSound = "gentle";
            if (!Services.SoundService.IsValidSoundId(FocusCompleteSound))
                FocusCompleteSound = "bell";
            if (!Services.SoundService.IsValidSoundId(RandomCueBreakSound))
                RandomCueBreakSound = "bell";
            if (!Services.SoundService.IsValidSoundId(RandomCueResumeSound))
                RandomCueResumeSound = "pixel";
            if (string.IsNullOrWhiteSpace(PetName) || PetName == "小心心")
                PetName = "苏无度";
            AiProvider = (AiProvider ?? string.Empty).Trim().ToLowerInvariant();
            if (AiProvider != "codex" && AiProvider != "openai" && AiProvider != "offline")
                AiProvider = "codex";
            if (string.IsNullOrWhiteSpace(AiModel)) AiModel = "gpt-5.6-sol";
            if (CodexModel == null) CodexModel = string.Empty;
            if (CodexReasoningEffort == null) CodexReasoningEffort = string.Empty;
        }
    }
}
