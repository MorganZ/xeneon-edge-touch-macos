// touchd — minimal user-space touch driver for the Corsair Xeneon Edge on macOS.
//
// Seizes the Edge's HID interfaces (so macOS stops treating it as a mouse on the
// main display), reads its raw touch reports, and injects CGEvents mapped onto
// the Xeneon display wherever it sits in the arrangement.
//
// Gestures: press / drag / release (the firmware reports a single contact).
// After each gesture the cursor is restored to where it was (--no-restore to disable).
//
// Needs: Input Monitoring (HID seize) + Accessibility (event posting).

import Foundation
import IOKit.hid
import CoreGraphics

// MARK: - Device constants (Xeneon Edge touch controller, wch.cn)

let vendorID = 0x27c0
let productID = 0x0859
let corsairDisplayVendor: UInt32 = 0x0E58
let rawMaxX: Double = 16383
let rawMaxY: Double = 9599

// MARK: - Options

var restoreCursor = true
var verbose = false
func log(_ s: String) { if verbose { print(s) } }

/// Called on the main thread when the Edge attaches/detaches.
var onAttachChange: ((Bool) -> Void)?

// MARK: - Target display

func targetDisplayBounds() -> CGRect {
    var count: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    CGGetOnlineDisplayList(16, &ids, &count)
    let list = Array(ids.prefix(Int(count)))
    if let d = list.first(where: { CGDisplayVendorNumber($0) == corsairDisplayVendor }) {
        return CGDisplayBounds(d)
    }
    if let d = list.first(where: { $0 != CGMainDisplayID() }) { return CGDisplayBounds(d) }
    return CGDisplayBounds(CGMainDisplayID())
}

func toScreen(_ x: Double, _ y: Double) -> CGPoint {
    let b = targetDisplayBounds()
    return CGPoint(x: b.origin.x + x / rawMaxX * b.width,
                   y: b.origin.y + y / rawMaxY * b.height)
}

// MARK: - Event injection

func post(_ type: CGEventType, at p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func postScroll(dx: Double, dy: Double) {
    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
        .post(tap: .cghidEventTap)
}

func cursorPosition() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

// MARK: - Gesture state machine (single finger — the Edge firmware only reports one touch)
//   touch -> mouseMoved (hover, so overlay scroll bars appear) + mouseDown
//   move  -> mouseDragged
//   lift  -> mouseUp, then the cursor is restored

enum Mode { case idle, press }
var mode = Mode.idle
var savedCursor = CGPoint.zero
var lastPoint = CGPoint.zero

func handle(_ p: CGPoint?) {
    switch (mode, p) {
    case (.idle, nil):
        break
    case (.idle, let p?):
        savedCursor = cursorPosition()
        lastPoint = p
        mode = .press
        post(.mouseMoved, at: p)
        post(.leftMouseDown, at: p)
    case (.press, let p?):
        lastPoint = p
        post(.leftMouseDragged, at: p)
    case (.press, nil):
        post(.leftMouseUp, at: lastPoint)
        finish()
    }
}

func finish() {
    mode = .idle
    if restoreCursor { CGWarpMouseCursorPosition(savedCursor) }
}

// MARK: - HID input
//
// The Edge exposes a multitouch digitizer interface, but its firmware never reports
// on it (multitouch is presumably enabled by iCUE through the vendor interface).
// All touch data arrives on the *mouse* interface as report 7:
//   [07][buttons][X u16 0…16383][Y u16 0…9599][wheel]
// bit 0 of `buttons` is the finger-down state.

var reportBuffer = [UInt8](repeating: 0, count: 16)

let reportCallback: IOHIDReportCallback = { _, _, _, _, _, report, length in
    guard length >= 6, report[0] == 0x07 else { return }
    var p: CGPoint? = nil
    if report[1] & 1 == 1 {
        let x = Double(UInt16(report[2]) | UInt16(report[3]) << 8)
        let y = Double(UInt16(report[4]) | UInt16(report[5]) << 8)
        p = toScreen(x, y)
    }
    log("touch: \(p.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "up") mode=\(mode)")
    handle(p)
}

// The manager seizes every interface of the device (mouse, digitizer, vendor), which is
// what stops macOS from using it; we only need to read the mouse one.
let deviceMatched: IOHIDDeviceCallback = { _, _, _, device in
    let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    guard page == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_Mouse else { return }
    reportBuffer.withUnsafeMutableBufferPointer { buf in
        IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, reportCallback, nil)
    }
    print("Xeneon Edge attached")
    onAttachChange?(true)
}

let deviceRemoved: IOHIDDeviceCallback = { _, _, _, device in
    let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    guard page == kHIDPage_GenericDesktop else { return }
    if mode != .idle { finish() }
    print("Xeneon Edge detached")
    onAttachChange?(false)
}

var manager: IOHIDManager?

/// Opens the Edge exclusively. Returns kIOReturnNotPermitted when Input Monitoring is missing.
@discardableResult
func startDriver() -> IOReturn {
    let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
    IOHIDManagerRegisterDeviceMatchingCallback(m, deviceMatched, nil)
    IOHIDManagerRegisterDeviceRemovalCallback(m, deviceRemoved, nil)
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    let rc = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    if rc == kIOReturnSuccess { manager = m } else { IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) }
    return rc
}

func stopDriver() {
    guard let m = manager else { return }
    if mode != .idle { finish() }
    IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
    manager = nil
}
