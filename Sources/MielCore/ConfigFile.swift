import Foundation

public struct ConfigPaths: Hashable, Sendable {
    public var config: URL

    public init(config: URL) {
        self.config = config
    }

    /// ~/.config/mielwm/config.json. `MIELWM_CONFIG_DIR` moves it (tests run beside the real config).
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ConfigPaths {
        let dir = ProcessInfo.processInfo.environment["MIELWM_CONFIG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".config/mielwm", isDirectory: true)
        return ConfigPaths(config: dir.appendingPathComponent("config.json"))
    }

    /// When config.json last changed, to notice edits; nil while there is no file.
    public var configModified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: config.path))?[.modificationDate] as? Date
    }
}

public struct LoadedSettings: Hashable, Sendable {
    public var settings: Settings
    public var errors: [String] // one line each, for the menu bar and the log
}

/// Reads config.json. A missing file is fine; a file that is not JSON is
/// skipped whole with an error; a bad key costs only that key.
public func loadSettings(_ paths: ConfigPaths) -> LoadedSettings {
    parseSettings(config: try? Data(contentsOf: paths.config), configName: paths.config.lastPathComponent)
}

func parseSettings(config: Data?, configName: String = "config.json") -> LoadedSettings {
    var result = LoadedSettings(settings: Settings(), errors: [])
    func apply(_ data: Data?, name: String) {
        guard let data, !data.isEmpty else { return }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) } catch {
            result.errors.append("\(name): not valid JSON, using defaults (\(jsonErrorDetail(error)))")
            return
        }
        guard let dict = object as? [String: Any] else {
            result.errors.append("\(name): expected an object at the top")
            return
        }
        let entries = flatten(dict), names = Set(entries.map(\.0))
        for (key, raw) in entries {
            if key == "menubar:workspaces", names.contains("menubar:style") { continue } // the newer key decides
            if key.hasPrefix("keys:") {
                let chord = String(key.dropFirst(5))
                guard let command = raw as? String else { result.errors.append("\(name): binding '\(chord)' needs an action string"); continue }
                guard let parsed = KeyChord(chord) else { result.errors.append("\(name): cannot read the keys '\(chord)'"); continue }
                // The same chord may be spelled differently in the defaults.
                for existing in result.settings.bindings.keys where KeyChord(existing) == parsed {
                    result.settings.bindings[existing] = nil
                }
                if command.isEmpty || command == "none" { continue }
                guard Action(command: command) != nil else { result.errors.append("\(name): unknown action '\(command)' for '\(chord)'"); continue }
                result.settings.bindings[parsed.description] = command
                continue
            }
            guard let value = settingValue(raw) else { result.errors.append("\(name): '\(key)' has an unsupported value"); continue }
            let error = key.hasPrefix("rules:") ? result.settings.setRule(key, value) : result.settings.set(value, forKey: key)
            if let error { result.errors.append("\(name): \(error)") }
        }
    }
    apply(config, name: configName)
    return result
}

/// {"distortion": {"strength": 0.2}} and {"distortion:strength": 0.2} mean the same.
private func flatten(_ dict: [String: Any], prefix: String = "") -> [(String, Any)] {
    dict.sorted { $0.key < $1.key }.flatMap { key, value -> [(String, Any)] in
        let full = prefix.isEmpty ? key : prefix + ":" + key
        if let nested = value as? [String: Any] { return flatten(nested, prefix: full) }
        return [(full, value)]
    }
}

private func settingValue(_ raw: Any) -> SettingValue? {
    if let n = raw as? NSNumber {
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? .flag(n.boolValue) : .number(n.doubleValue)
    }
    return (raw as? String).map(SettingValue.text)
}

private func jsonErrorDetail(_ error: Error) -> String {
    (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
}

// MARK: - Editing config.json (the Settings window)

public struct ConfigWriteError: Error, CustomStringConvertible {
    public var description: String
}

/// Sets setting keys and `keys:<chord>` bindings in config.json (nil
/// removes one), keeping everything else, flat or nested. Never overwrites
/// a config.json that is not valid JSON.
public func updateConfig(_ changes: [String: SettingValue?], paths: ConfigPaths) throws {
    guard !changes.isEmpty else { return }
    var config = try readObject(paths.config)
    for (key, value) in changes {
        removeKey(key, from: &config)
        if let value { config[canonicalKey(key)] = value.json }
    }
    try writeObject(config, to: paths.config)
}

private func readObject(_ url: URL) throws -> [String: Any] {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
    let object: Any
    do { object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) } catch {
        throw ConfigWriteError(description: "\(url.lastPathComponent) is not valid JSON (\(jsonErrorDetail(error))). Fix it first.")
    }
    guard let dict = object as? [String: Any] else {
        throw ConfigWriteError(description: "\(url.lastPathComponent) does not hold an object at the top. Fix it first.")
    }
    return dict
}

private func writeObject(_ dict: [String: Any], to url: URL) throws {
    var data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    data.append(0x0A)
    let target = url.resolvingSymlinksInPath() // a dotfiles symlink stays a symlink
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target, options: .atomic)
}

/// Removes `key` wherever it sits (flat or nested); a binding also under
/// any other spelling of its chord. Nested objects left empty go too.
private func removeKey(_ key: String, from dict: inout [String: Any], prefix: String = "") {
    let chord = key.hasPrefix("keys:") ? KeyChord(String(key.dropFirst(5))) : nil
    for (k, value) in dict {
        let full = prefix.isEmpty ? k : prefix + ":" + k
        if var nested = value as? [String: Any] {
            removeKey(key, from: &nested, prefix: full)
            dict[k] = nested.isEmpty ? nil : nested
        } else if full == key || (chord != nil && full.hasPrefix("keys:") && KeyChord(String(full.dropFirst(5))) == chord) {
            dict[k] = nil
        }
    }
}

private func canonicalKey(_ key: String) -> String {
    guard key.hasPrefix("keys:"), let chord = KeyChord(String(key.dropFirst(5))) else { return key }
    return "keys:" + chord.description
}
/// Pretty JSON, written atomically, directories made as needed.
func writeJSON(_ value: some Encodable, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(value).write(to: url, options: .atomic)
}
