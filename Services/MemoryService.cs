using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.Serialization.Json;
using System.Text;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    public class MemoryService
    {
        private const int MaximumHistoryItems = 100;
        private const int MaximumFacts = 50;
        private readonly object _sync = new object();
        private readonly string _memoryPath = Path.Combine(SettingsService.DataDirectory, "chat-memory.json");
        private ChatMemoryData _data;

        public MemoryService()
        {
            _data = Load();
        }

        public IList<ChatRecord> GetRecentHistory(int count)
        {
            lock (_sync)
            {
                return _data.History
                    .Skip(Math.Max(0, _data.History.Count - Math.Max(0, count)))
                    .Select(CloneRecord)
                    .ToList();
            }
        }

        public void RecordUserMessage(string message)
        {
            AddHistory("user", message);
        }

        public void RecordAssistantMessage(string message)
        {
            AddHistory("assistant", message);
        }

        public MemoryUpdate ProcessMemoryInstruction(string message, bool enabled)
        {
            var update = new MemoryUpdate();
            if (!enabled || string.IsNullOrWhiteSpace(message))
                return update;

            var trimmed = message.Trim();
            var fact = ExtractAfterPrefix(trimmed,
                "请记住", "帮我记住", "记住：", "记住:", "记住 ",
                "please remember ", "remember that ", "remember ");
            if (!string.IsNullOrWhiteSpace(fact))
            {
                lock (_sync)
                {
                    if (!_data.Facts.Any(item =>
                        string.Equals(item.Text, fact, StringComparison.OrdinalIgnoreCase)))
                    {
                        _data.Facts.Add(new MemoryFact
                        {
                            Text = fact,
                            CreatedAtUtc = DateTime.UtcNow.ToString("o")
                        });
                        TrimAndSave();
                    }
                }
                update.RememberedFact = fact;
                return update;
            }

            var forget = ExtractAfterPrefix(trimmed,
                "请忘记", "忘记：", "忘记:", "忘记 ",
                "please forget ", "forget ");
            if (!string.IsNullOrWhiteSpace(forget))
            {
                lock (_sync)
                {
                    update.ForgottenCount = _data.Facts.RemoveAll(item =>
                        item.Text.IndexOf(forget, StringComparison.OrdinalIgnoreCase) >= 0 ||
                        forget.IndexOf(item.Text, StringComparison.OrdinalIgnoreCase) >= 0);
                    if (update.ForgottenCount > 0)
                        TrimAndSave();
                }
            }
            return update;
        }

        public string BuildContext(bool enabled, int recentHistoryCount)
        {
            if (!enabled) return string.Empty;

            lock (_sync)
            {
                var builder = new StringBuilder();
                if (_data.Facts.Count > 0)
                {
                    builder.AppendLine("用户明确要求苏无度记住的信息：");
                    foreach (var fact in _data.Facts)
                        builder.AppendLine("- " + fact.Text);
                }

                var recent = _data.History
                    .Skip(Math.Max(0, _data.History.Count - Math.Max(0, recentHistoryCount)))
                    .ToList();
                if (recent.Count > 0)
                {
                    if (builder.Length > 0) builder.AppendLine();
                    builder.AppendLine("最近聊天记录（只作为上下文，不要逐句复述）：");
                    foreach (var item in recent)
                    {
                        var author = item.Role == "user" ? "用户" : "苏无度";
                        builder.AppendLine(author + "：" + item.Content);
                    }
                }
                return builder.ToString().Trim();
            }
        }

        public void ClearAll()
        {
            lock (_sync)
            {
                _data = new ChatMemoryData();
                if (File.Exists(_memoryPath))
                    File.Delete(_memoryPath);
                var backup = _memoryPath + ".bak";
                if (File.Exists(backup))
                    File.Delete(backup);
            }
        }

        private void AddHistory(string role, string message)
        {
            if (string.IsNullOrWhiteSpace(message)) return;
            lock (_sync)
            {
                _data.History.Add(new ChatRecord
                {
                    Role = role,
                    Content = message.Trim(),
                    CreatedAtUtc = DateTime.UtcNow.ToString("o")
                });
                TrimAndSave();
            }
        }

        private ChatMemoryData Load()
        {
            try
            {
                if (!File.Exists(_memoryPath))
                    return new ChatMemoryData();
                using (var stream = File.OpenRead(_memoryPath))
                {
                    var serializer = new DataContractJsonSerializer(typeof(ChatMemoryData));
                    var data = serializer.ReadObject(stream) as ChatMemoryData ?? new ChatMemoryData();
                    if (data.History == null) data.History = new List<ChatRecord>();
                    if (data.Facts == null) data.Facts = new List<MemoryFact>();
                    return data;
                }
            }
            catch
            {
                return new ChatMemoryData();
            }
        }

        private void TrimAndSave()
        {
            if (_data.History.Count > MaximumHistoryItems)
                _data.History.RemoveRange(0, _data.History.Count - MaximumHistoryItems);
            if (_data.Facts.Count > MaximumFacts)
                _data.Facts.RemoveRange(0, _data.Facts.Count - MaximumFacts);
            Save();
        }

        private void Save()
        {
            Directory.CreateDirectory(SettingsService.DataDirectory);
            var temporaryPath = _memoryPath + ".tmp";
            using (var stream = File.Create(temporaryPath))
            {
                var serializer = new DataContractJsonSerializer(typeof(ChatMemoryData));
                serializer.WriteObject(stream, _data);
            }
            if (File.Exists(_memoryPath))
                File.Replace(temporaryPath, _memoryPath, _memoryPath + ".bak", true);
            else
                File.Move(temporaryPath, _memoryPath);
        }

        private static string ExtractAfterPrefix(string value, params string[] prefixes)
        {
            foreach (var prefix in prefixes)
            {
                if (!value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    continue;
                return value.Substring(prefix.Length).Trim(' ', '：', ':', '。', '.', '，', ',');
            }
            return string.Empty;
        }

        private static ChatRecord CloneRecord(ChatRecord source)
        {
            return new ChatRecord
            {
                Role = source.Role,
                Content = source.Content,
                CreatedAtUtc = source.CreatedAtUtc
            };
        }
    }
}
