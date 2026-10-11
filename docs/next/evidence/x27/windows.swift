import Foundation
import CoreGraphics

let owner = Int(CommandLine.arguments[1])!
let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
let windows = rows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == owner }.map { row in
    ["number": row[kCGWindowNumber as String] ?? 0,
     "title": row[kCGWindowName as String] ?? "",
     "bounds": row[kCGWindowBounds as String] ?? [:],
     "layer": row[kCGWindowLayer as String] ?? 0,
     "onScreen": row[kCGWindowIsOnscreen as String] ?? false] as [String: Any]
}
let data = try JSONSerialization.data(withJSONObject: windows, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
