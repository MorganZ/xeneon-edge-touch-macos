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
let reportID: UInt8 = 0x0D
let maxContacts = 10
let rawMaxX: Double = 16383
let rawMaxY: Double = 9599

// MARK: - Options

setbuf(stdout, nil)
let restoreCursor = !CommandLine.arguments.contains("--no-restore")
let verbose = CommandLine.arguments.contains("-v")
func log(_ s: String) { if verbose { print(s) } }

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

func handle(contacts: [CGPoint]) {
    switch (mode, contacts.first) {
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

// MARK: - Report parsing
// Report 0x0D: [id][10 × {tip:1 pad:3 cid:4, x:u16, y:u16}][scanTime:u16][count:u8]

func parse(_ r: UnsafeBufferPointer<UInt8>) {
    log("digitizer report id=\(r.count > 0 ? r[0] : 0) len=\(r.count)")
    guard r.count >= 54, r[0] == reportID else { return }
    let count = min(Int(r[53]), maxContacts)
    var pts: [CGPoint] = []
    for i in 0..<count {
        let o = 1 + i * 5
        guard r[o] & 1 == 1 else { continue }
        let x = Double(UInt16(r[o + 1]) | UInt16(r[o + 2]) << 8)
        let y = Double(UInt16(r[o + 3]) | UInt16(r[o + 4]) << 8)
        pts.append(toScreen(x, y))
    }
    log("contacts=\(count) tips=\(pts.count) mode=\(mode) \(pts.first.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "")")
    handle(contacts: pts)
}

// MARK: - HID setup

var reportBuffer = [UInt8](repeating: 0, count: 64)
var mouseBuffer = [UInt8](repeating: 0, count: 16)
// Mouse interface, report 7: [07][buttons][X u16][Y u16][wheel]. The Edge sends
// single-touch here even after the Device Mode switch, so this is the main input path.
let mouseTrace: IOHIDReportCallback = { _, _, _, _, _, report, length in
    guard length >= 6, report[0] == 0x07 else { return }
    var pts: [CGPoint] = []
    if report[1] & 1 == 1 {
        let x = Double(UInt16(report[2]) | UInt16(report[3]) << 8)
        let y = Double(UInt16(report[4]) | UInt16(report[5]) << 8)
        pts.append(toScreen(x, y))
    }
    log("mouse: tip=\(pts.count) mode=\(mode) \(pts.first.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "")")
    handle(contacts: pts)
}

let reportCallback: IOHIDReportCallback = { _, _, _, _, _, report, length in
    parse(UnsafeBufferPointer(start: report, count: length))
}

let deviceMatched: IOHIDDeviceCallback = { _, _, _, device in
    let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
    log("device matched: page=\(page) usage=\(usage)")
    if page == kHIDPage_GenericDesktop {   // mouse interface (seized, so macOS no longer sees it)
        mouseBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, mouseTrace, nil)
        }
        return
    }
    guard page == kHIDPage_Digitizer, usage == kHIDUsage_Dig_TouchScreen else { return }
    // Switch the controller from mouse emulation to multi-touch reporting (Device Mode = 2).
    var feat = [UInt8](repeating: 0, count: 8)
    var n: CFIndex = feat.count
    feat[0] = 0x0A
    var r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x0A, &feat, &n)
    log("get max contacts (0x0A) -> 0x\(String(UInt32(bitPattern: r), radix: 16)) \(Array(feat.prefix(n)))")
    n = feat.count; feat = [UInt8](repeating: 0, count: 8); feat[0] = 0x21
    r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x21, &feat, &n)
    log("get device mode (0x21) -> 0x\(String(UInt32(bitPattern: r), radix: 16)) \(Array(feat.prefix(n)))")
    var modeReport: [UInt8] = [0x21, 0x02, 0x00]
    r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x21, &modeReport, modeReport.count)
    log("set device mode -> 0x\(String(UInt32(bitPattern: r), radix: 16))")
    n = feat.count; feat = [UInt8](repeating: 0, count: 8); feat[0] = 0x21
    r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x21, &feat, &n)
    log("device mode after set -> \(Array(feat.prefix(n)))")
    reportBuffer.withUnsafeMutableBufferPointer { buf in
        IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, reportCallback, nil)
    }
    print("Xeneon Edge digitizer attached")
}

let deviceRemoved: IOHIDDeviceCallback = { _, _, _, _ in
    if mode != .idle { finish() }
    print("Xeneon Edge digitizer detached")
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

let rc = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
guard rc == kIOReturnSuccess else {
    print("IOHIDManagerOpen failed (0x\(String(rc, radix: 16))). Grant Input Monitoring to this binary/terminal.")
    exit(1)
}
print("touchd running (restore cursor: \(restoreCursor)). Ctrl-C to quit.")
CFRunLoopRun()
