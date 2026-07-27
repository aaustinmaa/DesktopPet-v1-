using System;
using System.Text;
using DesktopPet.Services;

namespace DesktopPet.Tests
{
    internal static class CodexSmokeTest
    {
        private static int Main()
        {
            Console.OutputEncoding = Encoding.UTF8;
            try
            {
                return RunAsync().GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                return 1;
            }
        }

        private static async System.Threading.Tasks.Task<int> RunAsync()
        {
            using (var client = new CodexAppServerClient())
            {
                var status = await client.GetAccountStatusAsync();
                if (!status.IsSignedIn)
                {
                    Console.Error.WriteLine("SKIP: ChatGPT account is not signed in. " +
                        (status.Error ?? string.Empty));
                    return 2;
                }

                var models = await client.GetAvailableModelsAsync();
                if (models.Count == 0)
                {
                    Console.Error.WriteLine("FAIL: Codex returned no selectable models.");
                    return 3;
                }
                Console.WriteLine("Available models:");
                foreach (var model in models)
                {
                    Console.WriteLine("- " + model.DisplayLabel + " [" + model.ModelId + "]");
                }

                var reply = await client.SendCompanionMessageAsync(
                    "你好，这是模型回退测试。请在回复中包含“苏无度”。",
                    "苏无度",
                    "ChatGPT 5.6 sol",
                    "用户喜欢简洁、自然的中文回答。");
                Console.WriteLine(reply);
                if (reply.IndexOf("苏无度", StringComparison.Ordinal) < 0)
                {
                    Console.Error.WriteLine("FAIL: reply did not preserve the Chinese pet name.");
                    return 4;
                }
                return 0;
            }
        }
    }
}
