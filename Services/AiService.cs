using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public class AiService
    {
        private readonly SecretService _secrets;
        private readonly AppSettings _settings;
        private readonly JavaScriptSerializer _json = new JavaScriptSerializer();

        public AiService(SecretService secrets, AppSettings settings)
        {
            _secrets = secrets;
            _settings = settings;
        }

        public async Task<PetReply> GetReplyAsync(string userMessage)
        {
            var apiKey = _secrets.GetApiKey();
            if (string.IsNullOrWhiteSpace(apiKey))
                return OfflineReply(userMessage);

            using (var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) })
            {
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
                var instructions =
                    "You are " + _settings.PetName + ", a tiny warm pixel-art desktop companion. " +
                    "Reply in the user's language, in one or two short sentences. Be supportive, playful, and practical. " +
                    "Return only compact JSON with keys reply, emotion, action. " +
                    "emotion must be one of idle,happy,working,question,success,error,sleeping,reminder,waving,heart. " +
                    "action must be one of none,bounce,wave,heart.";

                var request = new
                {
                    model = _settings.AiModel,
                    instructions,
                    input = userMessage,
                    max_output_tokens = 220,
                    reasoning = new { effort = "low" },
                    text = new { verbosity = "low" }
                };

                var body = new StringContent(_json.Serialize(request), Encoding.UTF8, "application/json");
                var response = await client.PostAsync("https://api.openai.com/v1/responses", body);
                var jsonText = await response.Content.ReadAsStringAsync();
                if (!response.IsSuccessStatusCode)
                    throw new InvalidOperationException(ReadApiError(jsonText, (int)response.StatusCode));

                var outputText = ExtractOutputText(jsonText);
                return ParsePetReply(outputText);
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
            var outputItems = outputObject as ArrayList ?? new ArrayList((object[])outputObject);
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
            if (clean.StartsWith("```"))
            {
                var firstNewLine = clean.IndexOf('\n');
                var lastFence = clean.LastIndexOf("```", StringComparison.Ordinal);
                if (firstNewLine >= 0 && lastFence > firstNewLine)
                    clean = clean.Substring(firstNewLine + 1, lastFence - firstNewLine - 1).Trim();
            }

            try
            {
                var data = _json.DeserializeObject(clean) as Dictionary<string, object>;
                if (data != null)
                {
                    var reply = data.ContainsKey("reply") ? Convert.ToString(data["reply"]) : clean;
                    var emotion = data.ContainsKey("emotion") ? Convert.ToString(data["emotion"]) : "idle";
                    var action = data.ContainsKey("action") ? Convert.ToString(data["action"]) : "none";
                    return new PetReply { Reply = reply, Emotion = ParseState(emotion), Action = action };
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

        private static PetReply OfflineReply(string message)
        {
            var lower = (message ?? string.Empty).ToLowerInvariant();
            if (lower.Contains("bug") || lower.Contains("错误") || lower.Contains("失败"))
                return new PetReply { Reply = "先别慌，我们把问题缩小到下一步就好。你已经在前进了。", Emotion = PetState.Question, Action = "bounce", IsOffline = true };
            if (lower.Contains("累") || lower.Contains("tired") || lower.Contains("休息"))
                return new PetReply { Reply = "休息五分钟吧。我替你守着桌面，回来再继续。", Emotion = PetState.Sleeping, Action = "none", IsOffline = true };
            if (lower.Contains("完成") || lower.Contains("done") || lower.Contains("成功"))
                return new PetReply { Reply = "做到了！这颗心今天为你跳得特别响。", Emotion = PetState.Success, Action = "heart", IsOffline = true };
            if (lower.Contains("你好") || lower.Contains("hello") || lower.Contains("hi"))
                return new PetReply { Reply = "你好呀，我一直在桌面这里陪着你。", Emotion = PetState.Waving, Action = "wave", IsOffline = true };
            return new PetReply { Reply = "我听见啦。没有配置 API key 时，我也会一直陪着你。", Emotion = PetState.HeartPulse, Action = "heart", IsOffline = true };
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
    }
}
