// From Barik (https://github.com/mocki-toki/barik), Barik/Widgets/Spaces/SpacesModels.swift:
// the protocols the AeroSpace provider and models conform to.
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

import AppKit

protocol SpaceModel: Identifiable, Equatable, Codable {
    associatedtype WindowType: WindowModel
    var isFocused: Bool { get set }
    var windows: [WindowType] { get set }
}

protocol WindowModel: Identifiable, Equatable, Codable {
    var id: Int { get }
    var title: String { get }
    var appName: String? { get }
    var isFocused: Bool { get }
    var appIcon: NSImage? { get set }
}

protocol SpacesProvider {
    associatedtype SpaceType: SpaceModel
    func getSpacesWithWindows() -> [SpaceType]?
}

protocol SwitchableSpacesProvider: SpacesProvider {
    func focusSpace(spaceId: String, needWindowFocus: Bool)
    func focusWindow(windowId: String)
}
