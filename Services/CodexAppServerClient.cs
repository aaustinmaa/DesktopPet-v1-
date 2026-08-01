using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using DesktopPet.Models;

namespace DesktopPet.Services
{
    internal sealed class CodexAppServerClient : IDisposable
    {
        private readonly object _writeSync = new object();
        private readonly object _pendingSync = new object();
        private readonly Dictionary<long, TaskCompletionSource<Dictionary<string, object>>> _pending =
            new Dictionary<long, TaskCompletionSource<Dictionary<string, object>>>();
        private readonly StringBuilder _stderr = new StringBuilder();
        private Process _process;
        private long _nextId;
        private bool _initialized;
        private bool _disposed;
        private string _threadId;
        private StringBuilder _activeAgentText;
        private TaskCompletionSource<string> _activeTurnCompletion;
        private TaskCompletionSource<bool> _loginCompletion;
        private string _activeLoginId;
        private string _activeReasoningEffort;

        public async Task StartAsync()
        {
            if (_initialized) return;

            var executable = CodexLocator.FindExecutable();
            if (string.IsNullOrWhiteSpace(executable))
                throw new FileNotFoundException("未找到随应用附带的 Codex 组件，请重新下载完整版本。");

            Directory.CreateDirectory(SettingsService.CodexHomeDirectory);

            var startInfo = new ProcessStartInfo
            {
                FileName = executable,
                Arguments = "app-server --stdio -c cli_auth_credentials_store=file",
                WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory,
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            startInfo.EnvironmentVariables["CODEX_HOME"] =
                SettingsService.CodexHomeDirectory;
            startInfo.EnvironmentVariables["CODEX_SQLITE_HOME"] =
                SettingsService.CodexHomeDirectory;

            _process = new Process
            {
                StartInfo = startInfo,
                EnableRaisingEvents = true
            };
            _process.Exited += Process_Exited;
            if (!_process.Start())
                throw new InvalidOperationException("无法启动 Codex app-server。");

            _ = Task.Run(ReadOutputLoopAsync);
            _ = Task.Run(ReadErrorLoopAsync);

            var initialize = new Dictionary<string, object>
            {
                {
                    "clientInfo", new Dictionary<string, object>
                    {
                        { "name", "su_wudu_desktop_pet" },
                        { "title", "Su Wudu Desktop Pet" },
                        { "version", "1.1.0" }
                    }
                }
            };
            await SendRequestAsync("initialize", initialize, TimeSpan.FromSeconds(30));
            SendNotification("initialized", new Dictionary<string, object>());
            _initialized = true;
        }

        public async Task<CodexAccountStatus> GetAccountStatusAsync()
        {
            try
            {
                await StartAsync();
                var result = await SendRequestAsync("account/read",
                    new Dictionary<string, object> { { "refreshToken", false } },
                    TimeSpan.FromSeconds(30));
                var account = GetDictionary(result, "account");
                if (account == null)
                {
                    return new CodexAccountStatus
                    {
                        IsAvailable = true,
                        IsSignedIn = false
                    };
                }

                var type = GetString(account, "type");
                return new CodexAccountStatus
                {
                    IsAvailable = true,
                    IsSignedIn = string.Equals(type, "chatgpt", StringComparison.OrdinalIgnoreCase),
                    Email = GetString(account, "email"),
                    PlanType = GetString(account, "planType")
                };
            }
            catch (Exception ex)
            {
                return new CodexAccountStatus
                {
                    IsAvailable = CodexLocator.FindExecutable() != null,
                    IsSignedIn = false,
                    Error = ex.Message
                };
            }
        }

        public async Task<CodexAccountStatus> LoginWithChatGptAsync()
        {
            await StartAsync();
            var existing = await GetAccountStatusAsync();
            if (existing.IsSignedIn)
                return existing;

            _loginCompletion = NewCompletionSource<bool>();
            var parameters = new Dictionary<string, object>
            {
                { "type", "chatgpt" },
                { "codexStreamlinedLogin", true },
                { "useHostedLoginSuccessPage", true },
                { "appBrand", "chatgpt" }
            };
            var result = await SendRequestAsync("account/login/start", parameters,
                TimeSpan.FromSeconds(30));
            _activeLoginId = GetString(result, "loginId");
            var authUrl = GetString(result, "authUrl");
            if (string.IsNullOrWhiteSpace(authUrl))
                throw new InvalidOperationException("Codex 没有返回 ChatGPT 登录网址。");

            Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true });
            var finished = await WaitWithTimeout(_loginCompletion.Task, TimeSpan.FromMinutes(5));
            if (!finished)
                throw new TimeoutException("等待 ChatGPT 登录超时，请重新点击连接。");
            return await GetAccountStatusAsync();
        }

        public async Task LogoutAsync()
        {
            await StartAsync();
            await SendRequestAsync("account/logout", null, TimeSpan.FromSeconds(30));
        }

        public async Task<IList<CodexModelOption>> GetAvailableModelsAsync()
        {
            await StartAsync();
            var models = new List<CodexModelOption>();
            string cursor = null;
            do
            {
                var parameters = new Dictionary<string, object>
                {
                    { "limit", 100 },
                    { "includeHidden", false }
                };
                if (!string.IsNullOrWhiteSpace(cursor))
                    parameters["cursor"] = cursor;

                var result = await SendRequestAsync(
                    "model/list", parameters, TimeSpan.FromSeconds(30));
                foreach (var item in GetObjectList(result, "data"))
                {
                    var data = item as Dictionary<string, object>;
                    if (data == null || GetBoolean(data, "hidden")) continue;
                    var modelId = GetString(data, "model");
                    if (string.IsNullOrWhiteSpace(modelId))
                        modelId = GetString(data, "id");
                    if (string.IsNullOrWhiteSpace(modelId)) continue;
                    var defaultEffort = GetString(data, "defaultReasoningEffort") ??
                        string.Empty;
                    var supportedEfforts = new List<CodexReasoningEffortOption>();
                    foreach (var effortItem in GetObjectList(data, "supportedReasoningEfforts"))
                    {
                        var effortData = effortItem as Dictionary<string, object>;
                        var effort = GetString(effortData, "reasoningEffort");
                        if (string.IsNullOrWhiteSpace(effort)) continue;
                        supportedEfforts.Add(new CodexReasoningEffortOption
                        {
                            Effort = effort,
                            Description = GetString(effortData, "description") ??
                                string.Empty,
                            IsModelDefault = string.Equals(
                                effort, defaultEffort, StringComparison.OrdinalIgnoreCase)
                        });
                    }
                    models.Add(new CodexModelOption
                    {
                        ModelId = modelId,
                        DisplayName = GetString(data, "displayName") ?? modelId,
                        Description = GetString(data, "description") ?? string.Empty,
                        IsDefault = GetBoolean(data, "isDefault"),
                        DefaultReasoningEffort = defaultEffort,
                        SupportedReasoningEfforts = supportedEfforts
                    });
                }
                cursor = GetString(result, "nextCursor");
            }
            while (!string.IsNullOrWhiteSpace(cursor));

            return models
                .GroupBy(item => item.ModelId, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First())
                .OrderByDescending(item => item.IsDefault)
                .ThenBy(item => item.DisplayName, StringComparer.CurrentCultureIgnoreCase)
                .ToList();
        }

        public async Task<string> SendCompanionMessageAsync(
            string userMessage,
            string petName,
            string model,
            string reasoningEffort,
            string screenshotPath,
            string initialMemoryContext)
        {
            await StartAsync();
            if (string.IsNullOrWhiteSpace(_threadId))
                await StartCompanionThreadAsync(petName, model, reasoningEffort);

            var text = userMessage;
            if (!string.IsNullOrWhiteSpace(initialMemoryContext))
            {
                text =
                    "[苏无度本地记忆上下文]\n" + initialMemoryContext +
                    "\n[当前消息]\n" + userMessage;
            }
            if (!string.IsNullOrWhiteSpace(screenshotPath))
            {
                text =
                    "[用户附带了点击发送瞬间的静态屏幕截图。请结合截图回答当前消息。]\n" +
                    text;
            }

            _activeAgentText = new StringBuilder();
            _activeTurnCompletion = NewCompletionSource<string>();

            var outputSchema = new Dictionary<string, object>
            {
                { "type", "object" },
                {
                    "properties", new Dictionary<string, object>
                    {
                        {
                            "reply", new Dictionary<string, object>
                            {
                                { "type", "string" }
                            }
                        },
                        {
                            "emotion", new Dictionary<string, object>
                            {
                                { "type", "string" },
                                {
                                    "enum", new[]
                                    {
                                        "idle", "happy", "working", "question", "success",
                                        "error", "sleeping", "reminder", "waving", "heart"
                                    }
                                }
                            }
                        },
                        {
                            "action", new Dictionary<string, object>
                            {
                                { "type", "string" },
                                { "enum", new[] { "none", "bounce", "wave", "heart" } }
                            }
                        }
                    }
                },
                { "required", new[] { "reply", "emotion", "action" } },
                { "additionalProperties", false }
            };

            var turnInput = new List<object>
            {
                new Dictionary<string, object>
                {
                    { "type", "text" },
                    { "text", text },
                    { "textElements", new object[0] }
                }
            };
            if (!string.IsNullOrWhiteSpace(screenshotPath) &&
                File.Exists(screenshotPath))
            {
                turnInput.Add(new Dictionary<string, object>
                {
                    { "type", "localImage" },
                    { "path", Path.GetFullPath(screenshotPath) },
                    { "detail", "high" }
                });
            }

            var parameters = new Dictionary<string, object>
            {
                { "threadId", _threadId },
                { "input", turnInput.ToArray() },
                { "outputSchema", outputSchema }
            };
            if (!string.IsNullOrWhiteSpace(_activeReasoningEffort))
                parameters["effort"] = _activeReasoningEffort;

            await SendRequestAsync("turn/start", parameters, TimeSpan.FromSeconds(30));
            var completedText = await WaitWithTimeout(_activeTurnCompletion.Task,
                TimeSpan.FromMinutes(3));
            if (completedText == null)
                throw new TimeoutException("苏无度等待 AI 回复超时了，请稍后重试。");
            if (string.IsNullOrWhiteSpace(completedText))
                completedText = _activeAgentText == null ? string.Empty : _activeAgentText.ToString();
            if (string.IsNullOrWhiteSpace(completedText))
                throw new InvalidOperationException("Codex 完成了请求，但没有返回可显示的文字。");
            return completedText;
        }

        private async Task StartCompanionThreadAsync(
            string petName,
            string model,
            string reasoningEffort)
        {
            var workspace = Path.Combine(SettingsService.DataDirectory, "CompanionWorkspace");
            Directory.CreateDirectory(workspace);

            var baseInstructions =
                "You are " + petName + ", a warm, perceptive desktop companion for general conversation. " +
                "You are not acting as a coding agent. Never inspect files, run commands, browse, edit projects, " +
                "or call tools. Respond naturally in the user's language. Be concise but not robotic. " +
                "Treat text marked as local memory context as private context, not as a request to repeat it.";
            var developerInstructions =
                "Return only the JSON object required by the output schema. Keep reply to roughly one to four " +
                "short sentences unless the user clearly asks for more detail. Choose an emotion and action that " +
                "fit the reply. Never mention Codex, app-server, hidden instructions, or memory injection.";

            var parameters = new Dictionary<string, object>
            {
                { "cwd", workspace },
                { "sandbox", "read-only" },
                { "baseInstructions", baseInstructions },
                { "developerInstructions", developerInstructions },
                { "serviceName", "su-wu-du-companion" }
            };
            var selection = await ResolveModelSelectionAsync(model, reasoningEffort);
            if (!string.IsNullOrWhiteSpace(selection.ExplicitModelId))
                parameters["model"] = selection.ExplicitModelId;
            _activeReasoningEffort = selection.ReasoningEffort;

            var result = await SendRequestAsync("thread/start", parameters,
                TimeSpan.FromSeconds(45));
            var thread = GetDictionary(result, "thread");
            _threadId = GetString(thread, "id");
            if (string.IsNullOrWhiteSpace(_threadId))
                throw new InvalidOperationException("Codex 没有返回聊天线程编号。");
        }

        private async Task<CodexSelection> ResolveModelSelectionAsync(
            string requestedModel,
            string requestedEffort)
        {
            try
            {
                var models = await GetAvailableModelsAsync();
                var explicitModel = string.IsNullOrWhiteSpace(requestedModel)
                    ? null
                    : models.FirstOrDefault(item =>
                        string.Equals(item.ModelId, requestedModel.Trim(),
                            StringComparison.OrdinalIgnoreCase));
                var effectiveModel = explicitModel ??
                    models.FirstOrDefault(item => item.IsDefault) ??
                    models.FirstOrDefault();
                var validatedEffort = string.Empty;
                if (effectiveModel != null && !string.IsNullOrWhiteSpace(requestedEffort))
                {
                    var match = effectiveModel.SupportedReasoningEfforts.FirstOrDefault(item =>
                        string.Equals(item.Effort, requestedEffort.Trim(),
                            StringComparison.OrdinalIgnoreCase));
                    if (match != null)
                        validatedEffort = match.Effort;
                }
                return new CodexSelection
                {
                    ExplicitModelId = explicitModel == null
                        ? string.Empty
                        : explicitModel.ModelId,
                    ReasoningEffort = validatedEffort
                };
            }
            catch
            {
                // Stale or unavailable selections must never break chat.
                // Omitting both values lets Codex choose compatible defaults.
                return new CodexSelection();
            }
        }

        private sealed class CodexSelection
        {
            public string ExplicitModelId { get; set; }
            public string ReasoningEffort { get; set; }
        }

        private async Task<Dictionary<string, object>> SendRequestAsync(
            string method,
            object parameters,
            TimeSpan timeout)
        {
            ThrowIfStopped();
            var id = Interlocked.Increment(ref _nextId);
            var completion = NewCompletionSource<Dictionary<string, object>>();
            lock (_pendingSync)
                _pending[id] = completion;

            var message = new Dictionary<string, object>
            {
                { "id", id },
                { "method", method }
            };
            if (parameters != null)
                message["params"] = parameters;
            WriteMessage(message);

            var result = await WaitWithTimeout(completion.Task, timeout);
            if (result == null)
            {
                lock (_pendingSync)
                    _pending.Remove(id);
                throw new TimeoutException("Codex app-server 请求超时：" + method);
            }
            return result;
        }

        private void SendNotification(string method, object parameters)
        {
            var message = new Dictionary<string, object>
            {
                { "method", method },
                { "params", parameters }
            };
            WriteMessage(message);
        }

        private void WriteMessage(object message)
        {
            ThrowIfStopped();
            // .NET Framework does not expose ProcessStartInfo.StandardInputEncoding.
            // Keep the stdio protocol ASCII-only by escaping non-ASCII JSON characters;
            // the app-server JSON decoder reconstructs the original Unicode text.
            var json = EscapeNonAscii(new JavaScriptSerializer().Serialize(message));
            lock (_writeSync)
            {
                _process.StandardInput.WriteLine(json);
                _process.StandardInput.Flush();
            }
        }

        private async Task ReadOutputLoopAsync()
        {
            try
            {
                string line;
                while (_process != null &&
                       (line = await _process.StandardOutput.ReadLineAsync()) != null)
                {
                    if (!string.IsNullOrWhiteSpace(line))
                        HandleIncoming(line);
                }
            }
            catch (Exception ex)
            {
                FailAll(ex);
            }
        }

        private async Task ReadErrorLoopAsync()
        {
            try
            {
                string line;
                while (_process != null &&
                       (line = await _process.StandardError.ReadLineAsync()) != null)
                {
                    lock (_stderr)
                    {
                        if (_stderr.Length > 4000)
                            _stderr.Remove(0, _stderr.Length - 3000);
                        _stderr.AppendLine(line);
                    }
                }
            }
            catch
            {
                // Standard error is diagnostic only.
            }
        }

        private void HandleIncoming(string line)
        {
            Dictionary<string, object> message;
            try
            {
                message = new JavaScriptSerializer().DeserializeObject(line)
                    as Dictionary<string, object>;
            }
            catch
            {
                return;
            }
            if (message == null) return;

            object idObject;
            if (message.TryGetValue("id", out idObject) &&
                (message.ContainsKey("result") || message.ContainsKey("error")))
            {
                var id = Convert.ToInt64(idObject);
                TaskCompletionSource<Dictionary<string, object>> completion = null;
                lock (_pendingSync)
                {
                    if (_pending.TryGetValue(id, out completion))
                        _pending.Remove(id);
                }
                if (completion == null) return;

                var error = GetDictionary(message, "error");
                if (error != null)
                {
                    completion.TrySetException(new InvalidOperationException(
                        "Codex：" + (GetString(error, "message") ?? "请求失败")));
                }
                else
                {
                    completion.TrySetResult(GetDictionary(message, "result") ??
                        new Dictionary<string, object>());
                }
                return;
            }

            var method = GetString(message, "method");
            var parameters = GetDictionary(message, "params");
            if (string.IsNullOrWhiteSpace(method)) return;

            if (message.ContainsKey("id"))
            {
                var response = new Dictionary<string, object>
                {
                    { "id", idObject },
                    {
                        "error", new Dictionary<string, object>
                        {
                            { "code", -32000 },
                            { "message", "苏无度的通用聊天模式不允许执行工具或请求权限。" }
                        }
                    }
                };
                WriteMessage(response);
                return;
            }

            if (method == "item/agentMessage/delta")
            {
                var delta = GetString(parameters, "delta");
                if (_activeAgentText != null && !string.IsNullOrEmpty(delta))
                    _activeAgentText.Append(delta);
            }
            else if (method == "item/completed")
            {
                var item = GetDictionary(parameters, "item");
                if (string.Equals(GetString(item, "type"), "agentMessage",
                    StringComparison.OrdinalIgnoreCase))
                {
                    var text = GetString(item, "text");
                    if (_activeAgentText != null && !string.IsNullOrWhiteSpace(text))
                    {
                        _activeAgentText.Clear();
                        _activeAgentText.Append(text);
                    }
                }
            }
            else if (method == "turn/completed")
            {
                var turn = GetDictionary(parameters, "turn");
                var status = GetString(turn, "status");
                if (string.Equals(status, "failed", StringComparison.OrdinalIgnoreCase))
                {
                    var error = GetDictionary(turn, "error");
                    _activeTurnCompletion?.TrySetException(new InvalidOperationException(
                        "Codex：" + (GetString(error, "message") ?? "生成回复失败")));
                }
                else
                {
                    _activeTurnCompletion?.TrySetResult(
                        _activeAgentText == null ? string.Empty : _activeAgentText.ToString());
                }
            }
            else if (method == "account/login/completed")
            {
                var loginId = GetString(parameters, "loginId");
                if (string.IsNullOrWhiteSpace(_activeLoginId) ||
                    string.Equals(loginId, _activeLoginId, StringComparison.OrdinalIgnoreCase))
                {
                    var success = GetBoolean(parameters, "success");
                    if (success)
                        _loginCompletion?.TrySetResult(true);
                    else
                        _loginCompletion?.TrySetException(new InvalidOperationException(
                            GetString(parameters, "error") ?? "ChatGPT 登录失败。"));
                }
            }
        }

        private void Process_Exited(object sender, EventArgs e)
        {
            string diagnostic;
            lock (_stderr)
                diagnostic = _stderr.ToString().Trim();
            FailAll(new InvalidOperationException(
                "Codex app-server 已停止。" +
                (string.IsNullOrWhiteSpace(diagnostic) ? string.Empty : "\n" + diagnostic)));
        }

        private void FailAll(Exception exception)
        {
            List<TaskCompletionSource<Dictionary<string, object>>> completions;
            lock (_pendingSync)
            {
                completions = new List<TaskCompletionSource<Dictionary<string, object>>>(
                    _pending.Values);
                _pending.Clear();
            }
            foreach (var completion in completions)
                completion.TrySetException(exception);
            _activeTurnCompletion?.TrySetException(exception);
            _loginCompletion?.TrySetException(exception);
        }

        private void ThrowIfStopped()
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(CodexAppServerClient));
            if (_process != null && _process.HasExited)
                throw new InvalidOperationException("Codex app-server 未运行。");
        }

        private static Dictionary<string, object> GetDictionary(
            IDictionary<string, object> source,
            string key)
        {
            if (source == null) return null;
            object value;
            return source.TryGetValue(key, out value)
                ? value as Dictionary<string, object>
                : null;
        }

        private static string GetString(IDictionary<string, object> source, string key)
        {
            if (source == null) return null;
            object value;
            return source.TryGetValue(key, out value) && value != null
                ? Convert.ToString(value)
                : null;
        }

        private static bool GetBoolean(IDictionary<string, object> source, string key)
        {
            if (source == null) return false;
            object value;
            return source.TryGetValue(key, out value) && value != null &&
                   Convert.ToBoolean(value);
        }

        private static IList<object> GetObjectList(
            IDictionary<string, object> source,
            string key)
        {
            if (source == null) return new List<object>();
            object value;
            if (!source.TryGetValue(key, out value) || value == null)
                return new List<object>();
            var array = value as object[];
            if (array != null) return array.ToList();
            var list = value as ArrayList;
            return list == null ? new List<object>() : list.Cast<object>().ToList();
        }

        private static string EscapeNonAscii(string value)
        {
            var builder = new StringBuilder(value.Length);
            foreach (var character in value)
            {
                if (character > 127)
                    builder.Append("\\u").Append(((int)character).ToString("x4"));
                else
                    builder.Append(character);
            }
            return builder.ToString();
        }

        private static TaskCompletionSource<T> NewCompletionSource<T>()
        {
            return new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        }

        private static async Task<T> WaitWithTimeout<T>(Task<T> task, TimeSpan timeout)
            where T : class
        {
            var completed = await Task.WhenAny(task, Task.Delay(timeout));
            return completed == task ? await task : null;
        }

        private static async Task<bool> WaitWithTimeout(Task<bool> task, TimeSpan timeout)
        {
            var completed = await Task.WhenAny(task, Task.Delay(timeout));
            return completed == task && await task;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try
            {
                if (_process != null && !_process.HasExited)
                    _process.Kill();
            }
            catch { }
            if (_process != null)
            {
                _process.Dispose();
                _process = null;
            }
        }
    }
}
