import Foundation

@main enum SystemStatsTests {
    static func main() {
        assert(MemoryPressure(kernelLevel: 1) == .normal)
        assert(MemoryPressure(kernelLevel: 2) == .warning)
        assert(MemoryPressure(kernelLevel: 4) == .critical)
        assert(MemoryPressure(kernelLevel: 0) == .unknown)
        assert(MemoryPressure(kernelLevel: -1) == .unknown)
        let almostFullButNormal = MemoryReading(used: 99, total: 100, swap: 0, cached: 0, pressure: .normal)
        assert(almostFullButNormal.fraction == 0.99 && almostFullButNormal.pressure == .normal)
        let zero = CPUCounters(user: 0, system: 0, idle: 0, nice: 0)
        assert(zero.utilization(since: zero) == nil)
        assert(CPUCounters(user: 0, system: 0, idle: 100, nice: 0).utilization(since: zero) == 0)
        assert(CPUCounters(user: 25, system: 25, idle: 0, nice: 50).utilization(since: zero) == 100)
        let split = CPUCounters(user: 20, system: 10, idle: 65, nice: 5).reading(since: zero)!
        assert(split.user == 25 && split.system == 10 && split.idle == 65)
        assert(abs(split.user + split.system + split.idle - 100) < 0.00001)
        let before = CPUCounters(user: 100, system: 100, idle: 700, nice: 100)
        let after = CPUCounters(user: 200, system: 300, idle: 1000, nice: 200)
        assert(abs(after.utilization(since: before)! - 400.0 / 700 * 100) < 0.00001)
        let wrapBefore = CPUCounters(user: UInt32.max - 4, system: 0, idle: 100, nice: 0)
        let wrapAfter = CPUCounters(user: 5, system: 0, idle: 110, nice: 0)
        assert(wrapAfter.utilization(since: wrapBefore) == 50)
        // Free includes speculative: count the speculative subset only once.
        assert(MemoryReading.usedBytes(free: 10, speculative: 2, fileBacked: 20, pageSize: 4096, total: 1_000_000) == 1_000_000 - 28 * 4096)
        assert(MemoryReading.usedBytes(free: 0, speculative: 0, fileBacked: 0, pageSize: 4096, total: 1_000_000) == 1_000_000)
        assert(MemoryReading.usedBytes(free: 100, speculative: 0, fileBacked: 100, pageSize: 4096, total: 500) == 0)
        assert(MemoryReading.usedBytes(free: 2, speculative: 5, fileBacked: 20, pageSize: 4096, total: 1_000_000) == 1_000_000 - 20 * 4096)
        // A short history stays at the right of a fixed minute, rather than
        // expanding into a misleading full-width, nearly flat line.
        assert(MonitorHistory.horizontalFraction(index: 0, count: 60) == 0)
        assert(MonitorHistory.horizontalFraction(index: 59, count: 60) == 1)
        assert(MonitorHistory.horizontalFraction(index: 1, count: 2) == 1)
        assert(abs(MonitorHistory.horizontalFraction(index: 0, count: 2) - 58.0 / 59) < 0.00001)
        let monitor = SystemStatsModel()
        assert(!monitor.isSampling && monitor.cpuHistory.isEmpty)
        monitor.setSamplingEnabled(true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
        assert(monitor.isSampling)
        assert(monitor.cpuPercent.map { (0...100).contains($0) } == true)
        assert(monitor.memory.map { $0.total == ProcessInfo.processInfo.physicalMemory && $0.used <= $0.total } == true)
        print(String(format: "Live CPU %.1f%%; RAM %.2f / %.0f GiB; swap %.2f GiB", monitor.cpuPercent!, Double(monitor.memory!.used) / 1_073_741_824, Double(monitor.memory!.total) / 1_073_741_824, Double(monitor.memory!.swap ?? 0) / 1_073_741_824))
        // Repeated hover-related refreshes must not clear an active history.
        let activeHistory = monitor.cpuHistory
        monitor.setSamplingEnabled(true)
        assert(monitor.cpuHistory == activeHistory)
        monitor.setSamplingEnabled(false)
        let samples = monitor.cpuHistory
        let memorySamples = monitor.memoryHistory
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
        assert(!monitor.isSampling && monitor.cpuHistory == samples && monitor.memoryHistory == memorySamples)
        monitor.setSamplingEnabled(true)
        assert(monitor.cpuHistory.isEmpty && monitor.memoryHistory.isEmpty && monitor.cpuPercent == nil)
        monitor.setSamplingEnabled(false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        assert(!monitor.isSampling && monitor.cpuHistory.isEmpty && monitor.cpuPercent == nil)
        print("System stats checks passed: OS pressure levels independent of usage, CPU deltas/wrap, memory accounting, real counters, fixed history scale, repeated enable preserves history, and disabled sampling stops.")
    }
}
