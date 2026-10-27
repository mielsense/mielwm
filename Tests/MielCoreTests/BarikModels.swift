// Barik's own config and AeroSpace models, copied from https://github.com/mocki-toki/barik
// (Barik/Config/ConfigModels.swift, ConfigManager.swift and Widgets/Spaces/Aerospace/AerospaceModels.swift)
// so the tests read mielwm's output the way Barik does. Changes: `experimental` is left out of RootToml
// (it needs Barik's SwiftUI constants and no fixture sets it), and the window model has no app icon.
//
// Copyright (c) 2024 Simon Butenko
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
// LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
// THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation

struct RootToml: Decodable {
    var theme: String?
    var yabai: YabaiConfig?
    var aerospace: AerospaceConfig?
    var widgets: WidgetsSection

    init() {
        self.theme = nil
        self.yabai = nil
        self.aerospace = nil
        self.widgets = WidgetsSection(displayed: [], others: [:])
    }
}

typealias ConfigData = [String: TOMLValue]

struct WidgetsSection: Decodable {
    let displayed: [TomlWidgetItem]
    let others: [String: ConfigData]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(
        displayed: [TomlWidgetItem],
        others: [String: ConfigData]
    ) {
        self.displayed = displayed
        self.others = others
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        let displayedKey = DynamicKey(stringValue: "displayed")!
        let displayedArray = try container.decode(
            [TomlWidgetItem].self, forKey: displayedKey)
        self.displayed = displayedArray

        var tempDict = [String: ConfigData]()

        for key in container.allKeys {
            guard key.stringValue != "displayed" else { continue }

            let nested = try container.nestedContainer(
                keyedBy: DynamicKey.self, forKey: key)

            var widgetDict = ConfigData()
            for nestedKey in nested.allKeys {
                let value = try nested.decode(TOMLValue.self, forKey: nestedKey)
                widgetDict[nestedKey.stringValue] = value
            }
            tempDict[key.stringValue] = widgetDict
        }

        self.others = tempDict
    }

    func config(for widgetId: String) -> ConfigData? {
        let keys = widgetId.split(separator: ".").map { String($0) }

        var current: Any? = others

        for key in keys {
            guard let dict = current as? [String: Any] else {
                return nil
            }
            current = dict[key]
        }

        return (current as? TOMLValue)?.dictionaryValue as? ConfigData
    }
}

struct TomlWidgetItem: Decodable {
    let id: String
    let inlineParams: ConfigData

    init(id: String, inlineParams: ConfigData) {
        self.id = id
        self.inlineParams = inlineParams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let strValue = try? container.decode(String.self) {
            self.id = strValue
            self.inlineParams = [:]
            return
        }

        let dictValue = try container.decode([String: ConfigData].self)

        guard dictValue.count == 1,
            let (widgetId, params) = dictValue.first
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Uncorrect inline-table in [widgets.displayed]"
                )
            )
        }

        self.id = widgetId
        self.inlineParams = params
    }
}

enum TOMLValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([TOMLValue])
    case dictionary(ConfigData)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let arr = try? container.decode([TOMLValue].self) {
            self = .array(arr)
            return
        }
        if let dict = try? container.decode(ConfigData.self) {
            self = .dictionary(dict)
            return
        }

        self = .null
    }
}

extension TOMLValue {
    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case let .int(i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }

    var arrayValue: [TOMLValue]? {
        if case let .array(arr) = self { return arr }
        return nil
    }

    var dictionaryValue: ConfigData? {
        if case let .dictionary(dict) = self { return dict }
        return nil
    }
}

struct YabaiConfig: Decodable {
    let path: String

    init() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/yabai") {
            self.path = "/opt/homebrew/bin/yabai"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/yabai") {
            self.path = "/usr/local/bin/yabai"
        } else {
            self.path = "/opt/homebrew/bin/yabai"
        }
    }
}

struct AerospaceConfig: Decodable {
    let path: String

    init() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace") {
            self.path = "/opt/homebrew/bin/aerospace"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/aerospace") {
            self.path = "/usr/local/bin/aerospace"
        } else {
            self.path = "/opt/homebrew/bin/aerospace"
        }
    }
}

struct AeroWindow: Decodable {
    let id: Int
    let title: String
    let appName: String?
    var isFocused: Bool = false
    let workspace: String?

    enum CodingKeys: String, CodingKey {
        case id = "window-id"
        case title = "window-title"
        case appName = "app-name"
        case workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        workspace = try container.decodeIfPresent(
            String.self, forKey: .workspace)
        isFocused = false
    }
}

struct AeroSpace: Decodable {
    let workspace: String
    var id: String { workspace }
    var isFocused: Bool = false
    var windows: [AeroWindow] = []

    enum CodingKeys: String, CodingKey {
        case workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try container.decode(String.self, forKey: .workspace)
    }

    init(workspace: String, isFocused: Bool = false, windows: [AeroWindow] = [])
    {
        self.workspace = workspace
        self.isFocused = isFocused
        self.windows = windows
    }
}

/// The config Barik writes the first time it runs.
let barikDefaultConfig = """
# If you installed yabai or aerospace without using Homebrew,
# manually set the path to the binary. For example:
#
# yabai.path = "/run/current-system/sw/bin/yabai"
# aerospace.path = ...

theme = "system" # system, light, dark

[widgets]
displayed = [ # widgets on menu bar
    "default.spaces",
    "spacer",
    "default.network",
    "default.battery",
    "divider",
    # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
    "default.time"
]

[widgets.default.spaces]
space.show-key = true        # show space number (or character, if you use AeroSpace)
window.show-title = true
window.title.max-length = 50

[widgets.default.battery]
show-percentage = true
warning-level = 30
critical-level = 10

[widgets.default.time]
format = "E d, J:mm"
calendar.format = "J:mm"

calendar.show-events = true
# calendar.allow-list = ["Home", "Personal"] # show only these calendars
# calendar.deny-list = ["Work", "Boss"] # show all calendars except these

[popup.default.time]
view-variant = "box"

[background]
enabled = true
"""
