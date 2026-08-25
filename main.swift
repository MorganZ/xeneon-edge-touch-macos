// touchd command-line entry point.
import Foundation

setbuf(stdout, nil)
restoreCursor = !CommandLine.arguments.contains("--no-restore")
verbose = CommandLine.arguments.contains("-v")

let rc = startDriver()
guard rc == kIOReturnSuccess else {
    print("IOHIDManagerOpen failed (0x\(String(UInt32(bitPattern: rc), radix: 16))). Grant Input Monitoring to this binary/terminal.")
    exit(1)
}
print("touchd running (restore cursor: \(restoreCursor)). Ctrl-C to quit.")
CFRunLoopRun()
