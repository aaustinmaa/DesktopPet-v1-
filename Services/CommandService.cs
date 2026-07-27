using System;
using System.IO;
using System.Web.Script.Serialization;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public class CommandService
    {
        private readonly string _commandPath = Path.Combine(SettingsService.DataDirectory, "command.json");
        private readonly JavaScriptSerializer _serializer = new JavaScriptSerializer();

        public string CommandPath => _commandPath;

        public PetCommand TryRead()
        {
            try
            {
                if (!File.Exists(_commandPath)) return null;
                var json = File.ReadAllText(_commandPath);
                var command = _serializer.Deserialize<PetCommand>(json);
                File.Delete(_commandPath);
                return command;
            }
            catch
            {
                return null;
            }
        }
    }
}
