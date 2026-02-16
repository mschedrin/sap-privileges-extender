import Cocoa

let homeDir = NSHomeDirectory()
let scriptFile = homeDir + "/.local/bin/dismiss-notifications.scpt"
let logFile = homeDir + "/Library/Logs/privileges-extender-dismiss.log"

// Load AppleScript from external file so we can update it without recompiling
var source: String
do {
    source = try String(contentsOfFile: scriptFile, encoding: .utf8)
} catch {
    let errMsg = "ERROR: Could not load script from \(scriptFile): \(error)"
    try? errMsg.write(toFile: logFile, atomically: true, encoding: .utf8)
    print(errMsg)
    exit(1)
}

var error: NSDictionary?
let script = NSAppleScript(source: source)!
let result = script.executeAndReturnError(&error)

var output = ""
if let error = error {
    output = "ERROR: \(error)"
} else {
    output = result.stringValue ?? "no output"
}

try? output.write(toFile: logFile, atomically: true, encoding: .utf8)
print(output)
