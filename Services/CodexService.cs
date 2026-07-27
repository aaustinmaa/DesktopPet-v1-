using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public static class CodexService
    {
        public static bool IsAvailable => CodexLocator.FindExecutable() != null;

        public static async Task<CodexAccountStatus> GetAccountStatusAsync()
        {
            using (var client = new CodexAppServerClient())
                return await client.GetAccountStatusAsync();
        }

        public static async Task<CodexAccountStatus> LoginAsync()
        {
            using (var client = new CodexAppServerClient())
                return await client.LoginWithChatGptAsync();
        }

        public static async Task LogoutAsync()
        {
            using (var client = new CodexAppServerClient())
                await client.LogoutAsync();
        }

        public static async Task<IList<CodexModelOption>> GetAvailableModelsAsync()
        {
            using (var client = new CodexAppServerClient())
                return await client.GetAvailableModelsAsync();
        }
    }
}
