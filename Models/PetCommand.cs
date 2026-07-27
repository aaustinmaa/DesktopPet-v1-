namespace DesktopPet.Models
{
    public class PetCommand
    {
        public string State { get; set; }
        public string Message { get; set; }
    }

    public class PetReply
    {
        public string Reply { get; set; }
        public PetState Emotion { get; set; }
        public string Action { get; set; }
        public bool IsOffline { get; set; }
        public string ProviderLabel { get; set; }
    }
}
