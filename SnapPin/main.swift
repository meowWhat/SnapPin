import Cocoa

// Keep a strong reference to the delegate to prevent premature deallocation
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
