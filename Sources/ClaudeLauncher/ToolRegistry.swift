import Foundation

// MARK: - Which tools exist on this machine, and which the user wants
//
// Stored in tools.json alongside the other three config files. Like them it
// decodes field by field, so a file written by a newer version can't fail to
// load and silently reset the setup.
//
// Detection answers the "scan the computer or ask the user" half of the
// request: a built-in tool only appears once its binary is actually found, so
// the picker never offers something that can't run. The user's part is the
// enable/disable toggle and any custom tools they define.

struct ToolSettings: Codable {

    /// Built-ins the user has switched off. Stored as the exclusion rather than
    /// the inclusion so a tool added in a later version shows up by default
    /// instead of being invisible until someone opens Settings.
    var disabledToolIDs: [String] = []

    /// Tools the user defined themselves — the route for any CLI whose flags
    /// this app can't verify.
    var customTools: [AITool] = []

    /// Extra flags per tool id, appended verbatim to every launch.
    var extraArguments: [String: [String]] = [:]

    private enum CodingKeys: String, CodingKey {
        case disabledToolIDs, customTools, extraArguments
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disabledToolIDs = try c.decodeIfPresent([String].self, forKey: .disabledToolIDs) ?? []
        customTools = try c.decodeIfPresent([AITool].self, forKey: .customTools) ?? []
        extraArguments = try c.decodeIfPresent([String: [String]].self, forKey: .extraArguments) ?? [:]
    }

    static func load() -> ToolSettings {
        guard let data = try? Data(contentsOf: AppPaths.toolsFile),
              let decoded = try? JSONDecoder().decode(ToolSettings.self, from: data) else {
            return ToolSettings()
        }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: AppPaths.toolsFile)
    }
}

/// A tool paired with where its binary was found, if anywhere.
struct ResolvedTool: Identifiable, Hashable {
    let tool: AITool
    /// Absolute path to the executable, or nil when it isn't installed.
    let path: String?

    var id: String { tool.id }
    var isInstalled: Bool { path != nil }
}

enum ToolRegistry {

    /// Every known tool — built-ins plus the user's own — resolved against the
    /// filesystem. Custom tools override a built-in sharing their id, so a user
    /// who needs different flags than the ones shipped here can take over.
    static func resolveAll(settings: ToolSettings) -> [ResolvedTool] {
        var byID: [String: AITool] = [:]
        var order: [String] = []

        for tool in AITool.builtIns {
            byID[tool.id] = tool
            order.append(tool.id)
        }
        for var custom in settings.customTools {
            custom.isBuiltIn = false
            if byID[custom.id] == nil { order.append(custom.id) }
            byID[custom.id] = custom
        }

        return order.compactMap { id in
            guard var tool = byID[id] else { return nil }
            tool.extraArguments = settings.extraArguments[id] ?? tool.extraArguments
            return ResolvedTool(tool: tool, path: Launcher.findExecutable(for: tool))
        }
    }

    /// Tools offered in the launch panel: installed, and not switched off.
    static func selectable(settings: ToolSettings) -> [ResolvedTool] {
        let disabled = Set(settings.disabledToolIDs)
        return resolveAll(settings: settings)
            .filter { $0.isInstalled && !disabled.contains($0.id) }
    }
}
