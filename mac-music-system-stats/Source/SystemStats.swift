import Foundation
import Combine
import Darwin

enum MonitorHistory {
    static let capacity = 60
    // Reserve the unrecorded part of the minute on the left. Two readings
    // must occupy two seconds, rather than stretching over the whole chart.
    static func horizontalFraction(index: Int, count: Int) -> Double {
        Double(capacity - count + index) / Double(capacity - 1)
    }
}

struct CPUReading: Equatable {
    let user: Double
    let system: Double
    let idle: Double
    var total: Double { user + system }
}

struct CPUCounters {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
    func reading(since previous: CPUCounters) -> CPUReading? {
        let userDelta = UInt64(user &- previous.user) + UInt64(nice &- previous.nice)
        let systemDelta = UInt64(system &- previous.system)
        let idleDelta = UInt64(idle &- previous.idle)
        let total = userDelta + systemDelta + idleDelta
        guard total > 0 else { return nil }
        return CPUReading(user: Double(userDelta) / Double(total) * 100,
                          system: Double(systemDelta) / Double(total) * 100,
                          idle: Double(idleDelta) / Double(total) * 100)
    }
    func utilization(since previous: CPUCounters) -> Double? { reading(since: previous)?.total }
}

enum MemoryPressure: Int32 {
    case unknown = 0, normal = 1, warning = 2, critical = 4
    init(kernelLevel: Int32) { self = Self(rawValue: kernelLevel) ?? .unknown }
    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .unknown: return "Unavailable"
        }
    }
}

struct MemoryReading {
    let used: UInt64
    let total: UInt64
    let swap: UInt64?
    let cached: UInt64
    let pressure: MemoryPressure
    var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
    static func usedBytes(free: UInt64, speculative: UInt64, fileBacked: UInt64, pageSize: UInt64, total: UInt64) -> UInt64 {
        // Mach's free_count already includes speculative pages. vm_stat excludes
        // that subset when reporting Pages free. Match Memory Used by subtracting
        // genuinely free pages and file-backed pages; do not subtract purgeable
        // anonymous pages again just because they also appear in Cached Files.
        let genuinelyFree = free > speculative ? free - speculative : 0
        let unused = min(total, (genuinelyFree + fileBacked) * pageSize)
        return total - unused
    }
}

enum SystemStatsReader {
    static func cpu() -> CPUCounters? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUCounters(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }
    static func memory() -> MemoryReading? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        let hasPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0
        return MemoryReading(used: MemoryReading.usedBytes(free: UInt64(info.free_count), speculative: UInt64(info.speculative_count), fileBacked: UInt64(info.external_page_count), pageSize: UInt64(pageSize), total: total), total: total, swap: hasSwap ? swap.xsu_used : nil, cached: min(total, (UInt64(info.external_page_count) + UInt64(info.purgeable_count)) * UInt64(pageSize)), pressure: hasPressure ? MemoryPressure(kernelLevel: pressure) : .unknown)
    }

}

final class SystemStatsModel: ObservableObject {
    @Published private(set) var cpu: CPUReading?
    var cpuPercent: Double? { cpu?.total }
    @Published private(set) var cpuHistory: [CPUReading] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var memory: MemoryReading?
    private(set) var isSampling = false
    private var timer: Timer?
    private var generation = 0
    private var reading = false
    private let queue = DispatchQueue(label: "local.music-island.system-stats", qos: .utility)
    // These counters are confined to the sampling queue.
    private var previousCPU: CPUCounters?
    func setSamplingEnabled(_ enabled: Bool) {
        guard enabled != isSampling else { return }
        generation += 1
        let generation = generation
        isSampling = enabled
        timer?.invalidate(); timer = nil; reading = false
        guard enabled else { return }
        cpu = nil; cpuHistory = []; memoryHistory = []
        queue.async { self.previousCPU = nil }
        sample(generation: generation)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample(generation: generation) }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    private func sample(generation: Int) {
        guard isSampling, self.generation == generation, !reading else { return }
        reading = true
        queue.async {
            let counters = SystemStatsReader.cpu()
            let cpu = counters.flatMap { current in self.previousCPU.flatMap { current.reading(since: $0) } }
            self.previousCPU = counters
            let memory = SystemStatsReader.memory()
            DispatchQueue.main.async {
                guard self.isSampling, self.generation == generation else { return }
                self.reading = false
                self.cpu = cpu
                if let cpu {
                    self.cpuHistory.append(cpu)
                    if self.cpuHistory.count > MonitorHistory.capacity { self.cpuHistory.removeFirst(self.cpuHistory.count - MonitorHistory.capacity) }
                }
                self.memory = memory
                if let memory {
                    self.memoryHistory.append(memory.fraction * 100)
                    if self.memoryHistory.count > MonitorHistory.capacity { self.memoryHistory.removeFirst(self.memoryHistory.count - MonitorHistory.capacity) }
                }
            }
        }
    }
    deinit { timer?.invalidate() }
}
