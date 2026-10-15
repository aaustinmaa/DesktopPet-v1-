import Foundation
import CoreFoundation

struct ClaudeModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let resolvedModel: String?
    let efforts: [String]

    var pickerLabel: String {
        let title = id.isEmpty ? "自动选择" : name
        guard let resolvedModel, !title.localizedCaseInsensitiveContains(resolvedModel) else { return title }
        return "\(title)（\(resolvedModel)）"
    }

    static let effortLevels = ["low", "medium", "high", "xhigh", "max"]

    static func parseCatalog(_ result: ClaudeCommandResult, requestID: String) throws -> [Self] {
        let invalid = AppError.message("无法读取 Claude 模型列表，请刷新后重试。")
        guard result.exitCode == 0, result.stdout.count <= 1_000_000 else { throw invalid }
        var catalog: [[String: Any]]?
        for line in result.stdout.split(separator: 0x0A) where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = message["type"] as? String else { throw invalid }
            guard type == "control_response" else { continue }
            guard let response = message["response"] as? [String: Any],
                  let responseID = response["request_id"] as? String else { throw invalid }
            guard responseID == requestID else { continue }
            guard catalog == nil, response["subtype"] as? String == "success",
                  let payload = response["response"] as? [String: Any],
                  let entries = payload["models"] as? [[String: Any]], !entries.isEmpty, entries.count <= 100 else {
                throw invalid
            }
            catalog = entries
        }
        guard let catalog else { throw invalid }
        var ids = Set<String>(), models: [Self] = []
        for entry in catalog {
            guard let value = entry["value"] as? String, validIdentifier(value),
                  let displayName = entry["displayName"] as? String,
                  !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  displayName.count <= 200, !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw invalid
            }
            let resolved: String?
            if let raw = entry["resolvedModel"] {
                guard let name = raw as? String, validIdentifier(name) else { throw invalid }
                resolved = name
            } else { resolved = nil }
            let id = value == "default" ? "" : value
            guard ids.insert(id).inserted else { throw invalid }
            let supportsEffort = try optionalBoolean(entry["supportsEffort"], invalid: invalid)
            let disabled = try optionalBoolean(entry["disabled"], invalid: invalid)
            let requiresCredits = try optionalBoolean(entry["requiresUsageCredits"], invalid: invalid)
            let supported: [String]
            if let raw = entry["supportedEffortLevels"] {
                guard let levels = raw as? [String], levels.count <= 20,
                      levels.allSatisfy({ $0.count <= 32 }) else { throw invalid }
                supported = levels
            } else { supported = [] }

            // Fable and older [1m] variants can require paid usage credits; print mode does not
            // ask for consent. The SDK catalog does not reliably expose subscription entitlement.
            // Keep these out until it can: https://code.claude.com/docs/en/model-config
            let identities = [value, resolved ?? ""].map { $0.lowercased() }
            guard !disabled, !requiresCredits,
                  !identities.contains(where: { $0.contains("fable") || $0.contains("[1m]") }),
                  value.lowercased() != "best" || resolved != nil else { continue }

            models.append(Self(id: id, name: id.isEmpty ? "默认" : displayName, resolvedModel: resolved,
                efforts: supportsEffort ? effortLevels.filter(supported.contains) : []))
        }
        guard !models.isEmpty else { throw invalid }
        return models
    }

    private static func validIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/\[\]-]{0,199}$"#, options: .regularExpression) != nil
    }

    private static func optionalBoolean(_ value: Any?, invalid: Error) throws -> Bool {
        guard let value else { return false }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid }
        return number.boolValue
    }
}
