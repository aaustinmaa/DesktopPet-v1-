using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public class AiService : IDisposable
    {
        private readonly SecretService _secrets;
        private readonly AppSettings _settings;
        private readonly MemoryService _memory;
        private readonly string _threadId;
        private readonly JavaScriptSerializer _json = new JavaScriptSerializer();
        private CodexAppServerClient _codexClient;
        private bool _codexHasContext;

        public AiService(
            SecretService secrets,
            AppSettings settings,
            MemoryService memory,
            string threadId)
        {
            _secrets = secrets;
            _settings = settings;
            _memory = memory;
            _threadId = threadId;
        }

        public async Task<PetReply> GetReplyAsync(
            string userMessage,
            string screenshotPath = null)
        {
            var memoryUpdate = _memory.ProcessMemoryInstruction(
                userMessage, _settings.MemoryEnabled);
            var context = _memory.BuildContext(
                _settings.MemoryEnabled, _threadId, 24);
            _memory.RecordUserMessage(_threadId, userMessage);

            PetReply reply;
            switch ((_settings.AiProvider ?? string.Empty).ToLowerInvariant())
            {
                case "openai":
                    reply = await GetOpenAiReplyAsync(
                        userMessage, context, screenshotPath);
                    reply.ProviderLabel = "OpenAI API";
                    break;
                case "offline":
                    reply = OfflineReply(userMessage, memoryUpdate);
                    reply.ProviderLabel = "离线陪伴";
                    break;
                default:
                    reply = await GetCodexReplyAsync(
                        userMessage, context, screenshotPath);
                    reply.ProviderLabel = "ChatGPT · Codex";
                    break;
            }

            _memory.RecordAssistantMessage(_threadId, reply.Reply);
            return reply;
        }

        private async Task<PetReply> GetCodexReplyAsync(
            string userMessage,
            string context,
            string screenshotPath)
        {
            if (!CodexService.IsAvailable)
                throw new InvalidOperationException(
                    "未找到 Codex 运行组件，请重新下载完整的苏无度桌宠文件夹。");

            if (_codexClient == null)
                _codexClient = new CodexAppServerClient();
            var account = await _codexClient.GetAccountStatusAsync();
            if (!account.IsSignedIn)
                throw new InvalidOperationException(
                    "还没有连接 ChatGPT。请打开设置，点击“连接我的 ChatGPT”。");

            var raw = await _codexClient.SendCompanionMessageAsync(
                userMessage,
                _settings.PetName,
                _settings.CodexModel,
                _settings.CodexReasoningEffort,
                screenshotPath,
                _codexHasContext ? string.Empty : context);
            _codexHasContext = true;
            return ParsePetReply(raw);
        }

        private async Task<PetReply> GetOpenAiReplyAsync(
            string userMessage,
            string context,
            string screenshotPath)
        {
            var apiKey = _secrets.GetApiKey();
            if (string.IsNullOrWhiteSpace(apiKey))
                throw new InvalidOperationException(
                    "当前选择了 OpenAI API，但还没有填写 API key。请在设置中添加。");

            using (var client = new HttpClient { Timeout = TimeSpan.FromSeconds(90) })
            {
                client.DefaultRequestHeaders.Authorization =
                    new AuthenticationHeaderValue("Bearer", apiKey);
                var instructions =
                    "You are " + _settings.PetName + ", a warm pixel-art desktop companion for " +
                    "general conversation. Reply in the user's language. Be supportive, playful, " +
                    "practical, and concise. Return only compact JSON with keys reply, emotion, action. " +
                    "emotion must be one of idle,happy,working,question,success,error,sleeping,reminder," +
                    "waving,heart. action must be one of none,bounce,wave,heart.";
                var input = string.IsNullOrWhiteSpace(context)
                    ? userMessage
                    : "[本地记忆与最近聊天]\n" + context + "\n\n[当前消息]\n" + userMessage;
                if (!string.IsNullOrWhiteSpace(screenshotPath))
                {
                    input =
                        "[用户附带了点击发送瞬间的静态屏幕截图。请结合截图回答当前消息。]\n" +
                        input;
                }

                object requestInput = input;
                if (!string.IsNullOrWhiteSpace(screenshotPath) &&
                    File.Exists(screenshotPath))
                {
                    var imageBytes = File.ReadAllBytes(screenshotPath);
                    var imageUrl = "data:image/jpeg;base64," +
                        Convert.ToBase64String(imageBytes);
                    requestInput = new object[]
                    {
                        new Dictionary<string, object>
                        {
                            { "role", "user" },
                            {
                                "content", new object[]
                                {
                                    new Dictionary<string, object>
                                    {
                                        { "type", "input_text" },
                                        { "text", input }
                                    },
                                    new Dictionary<string, object>
                                    {
                                        { "type", "input_image" },
                                        { "image_url", imageUrl },
                                        { "detail", "high" }
                                    }
                                }
                            }
                        }
                    };
                }
                var request = new Dictionary<string, object>
                {
                    { "model", _settings.AiModel },
                    { "instructions", instructions },
                    { "input", requestInput },
                    { "max_output_tokens", 300 },
                    { "reasoning", new Dictionary<string, object>
                        {
                            { "effort", "low" }
                        }
                    },
                    { "text", new Dictionary<string, object>
                        {
                            { "verbosity", "low" }
                        }
                    }
                };

                var body = new StringContent(
                    _json.Serialize(request), Encoding.UTF8, "application/json");
                var response = await client.PostAsync(
                    "https://api.openai.com/v1/responses", body);
                var jsonText = await response.Content.ReadAsStringAsync();
                if (!response.IsSuccessStatusCode)
                    throw new InvalidOperationException(
                        ReadApiError(jsonText, (int)response.StatusCode));

                return ParsePetReply(ExtractOutputText(jsonText));
            }
        }

        private string ExtractOutputText(string responseJson)
        {
            var root = _json.DeserializeObject(responseJson) as Dictionary<string, object>;
            if (root == null) return string.Empty;

            object direct;
            if (root.TryGetValue("output_text", out direct) && direct != null)
                return direct.ToString();

            object outputObject;
            if (!root.TryGetValue("output", out outputObject)) return string.Empty;
            var outputItems = outputObject as ArrayList;
            if (outputItems == null && outputObject is object[])
                outputItems = new ArrayList((object[])outputObject);
            if (outputItems == null) return string.Empty;

            foreach (var item in outputItems)
            {
                var itemDictionary = item as Dictionary<string, object>;
                if (itemDictionary == null || !itemDictionary.ContainsKey("content")) continue;
                var contentItems = itemDictionary["content"] as ArrayList;
                if (contentItems == null && itemDictionary["content"] is object[])
                    contentItems = new ArrayList((object[])itemDictionary["content"]);
                if (contentItems == null) continue;

                foreach (var content in contentItems)
                {
                    var contentDictionary = content as Dictionary<string, object>;
                    if (contentDictionary == null) continue;
                    object text;
                    if (contentDictionary.TryGetValue("text", out text) && text != null)
                        return text.ToString();
                }
            }
            return string.Empty;
        }

        private PetReply ParsePetReply(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return new PetReply { Reply = "我在这里。", Emotion = PetState.Idle };

            var clean = text.Trim();
            if (clean.StartsWith("```", StringComparison.Ordinal))
            {
                var firstNewLine = clean.IndexOf('\n');
                var lastFence = clean.LastIndexOf("```", StringComparison.Ordinal);
                if (firstNewLine >= 0 && lastFence > firstNewLine)
                    clean = clean.Substring(
                        firstNewLine + 1, lastFence - firstNewLine - 1).Trim();
            }

            try
            {
                var data = _json.DeserializeObject(clean) as Dictionary<string, object>;
                if (data != null)
                {
                    var reply = data.ContainsKey("reply")
                        ? Convert.ToString(data["reply"])
                        : clean;
                    var emotion = data.ContainsKey("emotion")
                        ? Convert.ToString(data["emotion"])
                        : "idle";
                    var action = data.ContainsKey("action")
                        ? Convert.ToString(data["action"])
                        : "none";
                    return new PetReply
                    {
                        Reply = reply,
                        Emotion = ParseState(emotion),
                        Action = action
                    };
                }
            }
            catch
            {
                // A useful plain-text answer is better than failing on imperfect JSON.
            }
            return new PetReply { Reply = clean, Emotion = PetState.Idle };
        }

        private string ReadApiError(string jsonText, int statusCode)
        {
            try
            {
                var root = _json.DeserializeObject(jsonText) as Dictionary<string, object>;
                if (root != null && root.ContainsKey("error"))
                {
                    var error = root["error"] as Dictionary<string, object>;
                    if (error != null && error.ContainsKey("message"))
                        return "OpenAI API：" + Convert.ToString(error["message"]);
                }
            }
            catch { }
            return "OpenAI API 请求失败（HTTP " + statusCode + "）。";
        }

        private static PetReply OfflineReply(string message, MemoryUpdate memoryUpdate)
        {
            if (!string.IsNullOrWhiteSpace(memoryUpdate.RememberedFact))
            {
                return new PetReply
                {
                    Reply = "好，我记住了：" + memoryUpdate.RememberedFact,
                    Emotion = PetState.Happy,
                    Action = "heart",
                    IsOffline = true
                };
            }
            if (memoryUpdate.ForgottenCount > 0)
            {
                return new PetReply
                {
                    Reply = "好，我已经把那条记忆忘掉了。",
                    Emotion = PetState.Idle,
                    Action = "none",
                    IsOffline = true
                };
            }

            var lower = (message ?? string.Empty).ToLowerInvariant();
            if (lower.Contains("bug") || lower.Contains("错误") || lower.Contains("失败"))
                return new PetReply { Reply = "先别慌，我们把问题缩小到下一步就好。你已经在前进了。", Emotion = PetState.Question, Action = "bounce", IsOffline = true };
            if (lower.Contains("累") || lower.Contains("tired") || lower.Contains("休息"))
                return new PetReply { Reply = "休息五分钟吧。我替你守着桌面，回来再继续。", Emotion = PetState.Sleeping, Action = "none", IsOffline = true };
            if (lower.Contains("完成") || lower.Contains("done") || lower.Contains("成功"))
                return new PetReply { Reply = "做到了！这颗心今天为你跳得特别响。", Emotion = PetState.Success, Action = "heart", IsOffline = true };
            if (lower.Contains("你好") || lower.Contains("hello") || lower.Contains("hi"))
                return new PetReply { Reply = "你好呀，我一直在桌面这里陪着你。", Emotion = PetState.Waving, Action = "wave", IsOffline = true };
            return new PetReply { Reply = "我听见啦。离线时我只能做简单回应；连接 ChatGPT 后就能认真陪你聊任何话题。", Emotion = PetState.HeartPulse, Action = "heart", IsOffline = true };
        }

        public static PetState ParseState(string state)
        {
            switch ((state ?? string.Empty).Trim().ToLowerInvariant())
            {
                case "blink": return PetState.Blinking;
                case "happy": return PetState.Happy;
                case "working": return PetState.Working;
                case "question":
                case "confused": return PetState.Question;
                case "success": return PetState.Success;
                case "error":
                case "sad": return PetState.Error;
                case "sleep":
                case "sleeping": return PetState.Sleeping;
                case "reminder": return PetState.Reminder;
                case "wave":
                case "waving": return PetState.Waving;
                case "heart": return PetState.HeartPulse;
                default: return PetState.Idle;
            }
        }

        public void Dispose()
        {
            if (_codexClient != null)
            {
                _codexClient.Dispose();
                _codexClient = null;
            }
        }
    }
}
