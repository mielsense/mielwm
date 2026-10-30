import ApplicationServices
import CoreGraphics
import os

/// Private but stable since 10.x: the CGWindowID behind an AX window element.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

let axTimeout: Float = 0.25

/// AX round trips made so far, for `MIELWM_TIMINGS` (Controller).
public let axCalls = OSAllocatedUnfairLock(initialState: 0)

extension AXUIElement {
    var windowNumber: UInt32? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        axCalls.withLock { $0 += 1 }
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    /// Several attributes in one round trip; failed ones come back nil.
    func values(_ attributes: [String]) -> [CFTypeRef?] {
        var result: CFArray?
        axCalls.withLock { $0 += 1 }
        guard AXUIElementCopyMultipleAttributeValues(self, attributes as CFArray, AXCopyMultipleAttributeOptions(), &result) == .success,
              let array = result as [AnyObject]?, array.count == attributes.count
        else { return attributes.map { _ in nil } }
        return array.map { item in
            if CFGetTypeID(item) == AXValueGetTypeID(), AXValueGetType(item as! AXValue) == .axError { return nil }
            return item
        }
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        axCalls.withLock { $0 += 1 }
        return AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        axCalls.withLock { $0 += 1 }
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }
}

func axValue(_ point: CGPoint) -> AXValue {
    var p = point
    return AXValueCreate(.cgPoint, &p)!
}

func axValue(_ size: CGSize) -> AXValue {
    var s = size
    return AXValueCreate(.cgSize, &s)!
}

func cgPoint(_ value: CFTypeRef?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
}

func cgSize(_ value: CFTypeRef?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
}
