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
        private const int MaximumFacts = 50;
        private const int CrossChatThreadCount = 6;
        private const int SummaryMessageCount = 2;
        private const int SummaryMessageLength = 90;
        private const int MaximumTitleLength = 24;
        private readonly object _sync = new object();
        private readonly string _memoryPath;
        private ChatMemoryData _data;

        public static MemoryService Shared { get; } = new MemoryService();

        public MemoryService()
            : this(Path.Combine(
                SettingsService.DataDirectory,
                "chat-memory.json"))
        {
        }

        internal MemoryService(string memoryPath)
        {
            _memoryPath = memoryPath;
            _data = Load();
        }

        public ChatThreadData CreateThread()
        {
            lock (_sync)
            {
                var now = DateTime.UtcNow.ToString("o");
                var thread = new ChatThreadData
                {
                    Id = Guid.NewGuid().ToString("N"),
                    Title = "新聊天",
                    Summary = string.Empty,
                    CreatedAtUtc = now,
                    UpdatedAtUtc = now,
                    IsArchived = false,
                    Messages = new List<ChatRecord>()
                };
                _data.Threads.Add(thread);
                Save();
                return CloneThread(thread);
            }
        }

        public IList<ChatThreadData> GetThreads(bool archived)
        {
            lock (_sync)
            {
                return _data.Threads
                    .Where(thread => thread.IsArchived == archived)
                    .OrderByDescending(thread => ParseDate(thread.UpdatedAtUtc))
                    .Select(CloneThread)
                    .ToList();
            }
        }

        public ChatThreadData GetThread(string threadId)
        {
            lock (_sync)
            {
                var thread = FindThread(threadId);
                return thread == null ? null : CloneThread(thread);
            }
        }

        public void RecordUserMessage(string threadId, string message)
        {
            AddHistory(threadId, "user", message);
        }

        public void RecordAssistantMessage(string threadId, string message)
        {
            AddHistory(threadId, "assistant", message);
        }

        public void SetArchived(string threadId, bool archived)
        {
            lock (_sync)
            {
                var thread = FindThread(threadId);
                if (thread == null) return;
                thread.IsArchived = archived;
                thread.UpdatedAtUtc = DateTime.UtcNow.ToString("o");
                Save();
            }
        }

        public bool RemoveThreadIfEmpty(string threadId)
        {
            lock (_sync)
            {
                var thread = FindThread(threadId);
                if (thread == null ||
                    (thread.Messages != null && thread.Messages.Count > 0))
                    return false;
                _data.Threads.Remove(thread);
                Save();
                return true;
            }
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
                        TrimFacts();
                        Save();
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
                        Save();
                }
            }
            return update;
        }

        public string BuildContext(
            bool crossChatMemoryEnabled,
            string currentThreadId,
            int currentChatHistoryCount)
        {
            lock (_sync)
            {
                var builder = new StringBuilder();
                if (crossChatMemoryEnabled)
                {
                    if (_data.Facts.Count > 0)
                    {
                        builder.AppendLine("[用户记忆]");
                        builder.AppendLine("用户明确要求苏无度记住的信息：");
                        foreach (var fact in _data.Facts)
                            builder.AppendLine("- " + fact.Text);
                    }

                    var otherThreads = _data.Threads
                        .Where(thread =>
                            !string.Equals(thread.Id, currentThreadId,
                                StringComparison.OrdinalIgnoreCase) &&
                            thread.Messages != null &&
                            thread.Messages.Count > 0 &&
                            !string.IsNullOrWhiteSpace(thread.Summary))
                        .OrderByDescending(thread => ParseDate(thread.UpdatedAtUtc))
                        .Take(CrossChatThreadCount)
                        .ToList();
                    if (otherThreads.Count > 0)
                    {
                        if (builder.Length > 0) builder.AppendLine();
                        builder.AppendLine("[跨聊天精简记忆]");
                        builder.AppendLine("以下只用于理解用户近期关注点，不要逐条复述：");
                        foreach (var thread in otherThreads)
                            builder.AppendLine("- " + thread.Title + "：" + thread.Summary);
                    }
                }

                var currentThread = FindThread(currentThreadId);
                if (currentThread != null && currentThread.Messages != null)
                {
                    var recent = currentThread.Messages
                        .Skip(Math.Max(
                            0,
                            currentThread.Messages.Count -
                            Math.Max(0, currentChatHistoryCount)))
                        .ToList();
                    if (recent.Count > 0)
                    {
                        if (builder.Length > 0) builder.AppendLine();
                        builder.AppendLine("[当前聊天记录]");
                        foreach (var item in recent)
                        {
                            var author = item.Role == "user" ? "用户" : "苏无度";
                            builder.AppendLine(author + "：" + item.Content);
                        }
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

        private void AddHistory(string threadId, string role, string message)
        {
            if (string.IsNullOrWhiteSpace(message)) return;
            lock (_sync)
            {
                var thread = FindThread(threadId);
                if (thread == null)
                {
                    var now = DateTime.UtcNow.ToString("o");
                    thread = new ChatThreadData
                    {
                        Id = string.IsNullOrWhiteSpace(threadId)
                            ? Guid.NewGuid().ToString("N")
                            : threadId,
                        Title = "新聊天",
                        Summary = string.Empty,
                        CreatedAtUtc = now,
                        UpdatedAtUtc = now,
                        Messages = new List<ChatRecord>()
                    };
                    _data.Threads.Add(thread);
                }

                if (thread.Messages == null)
                    thread.Messages = new List<ChatRecord>();
                var cleanMessage = message.Trim();
                thread.Messages.Add(new ChatRecord
                {
                    Role = role,
                    Content = cleanMessage,
                    CreatedAtUtc = DateTime.UtcNow.ToString("o")
                });
                thread.UpdatedAtUtc = DateTime.UtcNow.ToString("o");
                if (role == "user")
                {
                    if (thread.Messages.Count(item => item.Role == "user") == 1)
                        thread.Title = GenerateTitle(cleanMessage);
                    thread.Summary = GenerateSummary(thread);
                    if (thread.IsArchived)
                        thread.IsArchived = false;
                }
                Save();
            }
        }

        private ChatMemoryData Load()
        {
            try
            {
                if (!File.Exists(_memoryPath))
                    return new ChatMemoryData();
                ChatMemoryData data;
                using (var stream = File.OpenRead(_memoryPath))
                {
                    var serializer = new DataContractJsonSerializer(typeof(ChatMemoryData));
                    data = serializer.ReadObject(stream) as ChatMemoryData ??
                        new ChatMemoryData();
                }
                if (Normalize(data))
                    SaveData(data);
                return data;
            }
            catch
            {
                return new ChatMemoryData();
            }
        }

        private static bool Normalize(ChatMemoryData data)
        {
            var changed = false;
            if (data.Threads == null)
            {
                data.Threads = new List<ChatThreadData>();
                changed = true;
            }
            if (data.History == null)
            {
                data.History = new List<ChatRecord>();
                changed = true;
            }
            if (data.Facts == null)
            {
                data.Facts = new List<MemoryFact>();
                changed = true;
            }

            if (data.History.Count > 0)
            {
                var createdAt = data.History
                    .Select(item => item.CreatedAtUtc)
                    .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ??
                    DateTime.UtcNow.ToString("o");
                var updatedAt = data.History
                    .Select(item => item.CreatedAtUtc)
                    .LastOrDefault(value => !string.IsNullOrWhiteSpace(value)) ??
                    createdAt;
                var migrated = new ChatThreadData
                {
                    Id = Guid.NewGuid().ToString("N"),
                    Title = "之前的聊天",
                    CreatedAtUtc = createdAt,
                    UpdatedAtUtc = updatedAt,
                    Messages = data.History.Select(CloneRecord).ToList()
                };
                migrated.Summary = GenerateSummary(migrated);
                data.Threads.Add(migrated);
                data.History.Clear();
                changed = true;
            }

            var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var thread in data.Threads)
            {
                if (thread.Messages == null)
                {
                    thread.Messages = new List<ChatRecord>();
                    changed = true;
                }
                if (string.IsNullOrWhiteSpace(thread.Id) || !seenIds.Add(thread.Id))
                {
                    thread.Id = Guid.NewGuid().ToString("N");
                    seenIds.Add(thread.Id);
                    changed = true;
                }
                if (string.IsNullOrWhiteSpace(thread.Title))
                {
                    thread.Title = thread.Messages.Count == 0
                        ? "新聊天"
                        : GenerateTitle(
                            thread.Messages.FirstOrDefault(item => item.Role == "user")?.Content);
                    changed = true;
                }
                if (string.IsNullOrWhiteSpace(thread.CreatedAtUtc))
                {
                    thread.CreatedAtUtc = DateTime.UtcNow.ToString("o");
                    changed = true;
                }
                if (string.IsNullOrWhiteSpace(thread.UpdatedAtUtc))
                {
                    thread.UpdatedAtUtc = thread.CreatedAtUtc;
                    changed = true;
                }
                if (thread.Summary == null)
                {
                    thread.Summary = GenerateSummary(thread);
                    changed = true;
                }
            }
            if (data.Version != 2)
            {
                data.Version = 2;
                changed = true;
            }
            return changed;
        }

        private void TrimFacts()
        {
            if (_data.Facts.Count > MaximumFacts)
                _data.Facts.RemoveRange(0, _data.Facts.Count - MaximumFacts);
        }

        private void Save()
        {
            SaveData(_data);
        }

        private void SaveData(ChatMemoryData data)
        {
            Directory.CreateDirectory(SettingsService.DataDirectory);
            var temporaryPath = _memoryPath + ".tmp";
            using (var stream = File.Create(temporaryPath))
            {
                var serializer = new DataContractJsonSerializer(typeof(ChatMemoryData));
                serializer.WriteObject(stream, data);
            }
            if (File.Exists(_memoryPath))
                File.Replace(temporaryPath, _memoryPath, _memoryPath + ".bak", true);
            else
                File.Move(temporaryPath, _memoryPath);
        }

        private ChatThreadData FindThread(string threadId)
        {
            return _data.Threads.FirstOrDefault(thread =>
                string.Equals(thread.Id, threadId, StringComparison.OrdinalIgnoreCase));
        }

        private static string GenerateTitle(string message)
        {
            var clean = CollapseWhitespace(message);
            if (string.IsNullOrWhiteSpace(clean))
                return "新聊天";
            clean = clean.Trim(' ', '。', '.', '！', '!', '？', '?', '，', ',', '：', ':');
            if (clean.Length > MaximumTitleLength)
                clean = clean.Substring(0, MaximumTitleLength).Trim() + "…";
            return string.IsNullOrWhiteSpace(clean) ? "新聊天" : clean;
        }

        private static string GenerateSummary(ChatThreadData thread)
        {
            if (thread == null || thread.Messages == null)
                return string.Empty;
            return string.Join("；", thread.Messages
                .Where(item =>
                    item.Role == "user" &&
                    !string.IsNullOrWhiteSpace(item.Content))
                .Reverse()
                .Take(SummaryMessageCount)
                .Reverse()
                .Select(item => Truncate(CollapseWhitespace(item.Content),
                    SummaryMessageLength)));
        }

        private static string CollapseWhitespace(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return string.Empty;
            var builder = new StringBuilder();
            var previousWasWhitespace = false;
            foreach (var character in value.Trim())
            {
                if (char.IsWhiteSpace(character))
                {
                    if (!previousWasWhitespace)
                        builder.Append(' ');
                    previousWasWhitespace = true;
                }
                else
                {
                    builder.Append(character);
                    previousWasWhitespace = false;
                }
            }
            return builder.ToString();
        }

        private static string Truncate(string value, int maximumLength)
        {
            if (string.IsNullOrEmpty(value) || value.Length <= maximumLength)
                return value ?? string.Empty;
            return value.Substring(0, maximumLength).Trim() + "…";
        }

        private static string ExtractAfterPrefix(string value, params string[] prefixes)
        {
            foreach (var prefix in prefixes)
            {
                if (!value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    continue;
                return value.Substring(prefix.Length)
                    .Trim(' ', '：', ':', '。', '.', '，', ',');
            }
            return string.Empty;
        }

        private static DateTime ParseDate(string value)
        {
            DateTime parsed;
            return DateTime.TryParse(value, out parsed) ? parsed : DateTime.MinValue;
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

        private static ChatThreadData CloneThread(ChatThreadData source)
        {
            return new ChatThreadData
            {
                Id = source.Id,
                Title = source.Title,
                Summary = source.Summary,
                CreatedAtUtc = source.CreatedAtUtc,
                UpdatedAtUtc = source.UpdatedAtUtc,
                IsArchived = source.IsArchived,
                Messages = (source.Messages ?? new List<ChatRecord>())
                    .Select(CloneRecord)
                    .ToList()
            };
        }
    }
}
