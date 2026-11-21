import Foundation
import CryptoKit
import Darwin
// Standalone checksum regression probe, not a video-generation benchmark.
// Compile with swiftc -O, then run each mode in a fresh process against the same file.
guard CommandLine.arguments.count == 3, ["baseline", "bounded"].contains(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("Usage: checksum-memory-probe baseline|bounded file\n".utf8))
    exit(2)
}
let bounded = CommandLine.arguments[1] == "bounded"
let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[2]))
var hash = SHA256()
let started = ProcessInfo.processInfo.systemUptime
if bounded {
    while true {
        let count: Int = try autoreleasepool {
            guard let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty else { return 0 }
            hash.update(data: data)
            return data.count
        }
        if count == 0 { break }
    }
} else {
    while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
}
try file.close()
var info = task_vm_info_data_t()
var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
let status = withUnsafeMutablePointer(to: &info) { ptr in
    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
}
print("mode=\(bounded ? "bounded" : "baseline") elapsed=\(ProcessInfo.processInfo.systemUptime-started) peakBytes=\(info.ledger_phys_footprint_peak) kernelStatus=\(status) sha256=\(hash.finalize().map{String(format:"%02x",$0)}.joined())")
