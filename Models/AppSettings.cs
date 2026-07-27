using System.Runtime.Serialization;

namespace DesktopPet.Models
{
    [DataContract]
    public class AppSettings
    {
        [DataMember] public double WindowLeft { get; set; } = double.NaN;
        [DataMember] public double WindowTop { get; set; } = double.NaN;
        [DataMember] public double PetScale { get; set; } = 0.82;
        [DataMember] public bool Topmost { get; set; } = true;
        [DataMember] public bool StartWithWindows { get; set; } = false;
        [DataMember] public bool AutoWander { get; set; } = false;
        [DataMember] public bool HydrationEnabled { get; set; } = true;
        [DataMember] public int HydrationMinutes { get; set; } = 45;
        [DataMember] public int FocusMinutes { get; set; } = 25;
        [DataMember] public string PetName { get; set; } = "苏无度";
        [DataMember] public string AiModel { get; set; } = "gpt-5.6-sol";
        [DataMember] public bool FirstRunComplete { get; set; } = false;

        public AppSettings Clone()
        {
            return (AppSettings)MemberwiseClone();
        }

        public void Normalize()
        {
            if (PetScale < 0.55) PetScale = 0.55;
            if (PetScale > 1.5) PetScale = 1.5;
            if (HydrationMinutes < 10) HydrationMinutes = 10;
            if (HydrationMinutes > 240) HydrationMinutes = 240;
            if (FocusMinutes < 1) FocusMinutes = 1;
            if (FocusMinutes > 120) FocusMinutes = 120;
            if (string.IsNullOrWhiteSpace(PetName) || PetName == "小心心")
                PetName = "苏无度";
            if (string.IsNullOrWhiteSpace(AiModel)) AiModel = "gpt-5.6-sol";
        }
    }
}
