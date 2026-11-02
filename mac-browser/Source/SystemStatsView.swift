import SwiftUI

struct MonitorTrace: Shape {
    let upper: [Double]
    var lower: [Double]? = nil
    var fillArea = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard upper.count > 1 else { return path }
        func point(_ index: Int, _ value: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * MonitorHistory.horizontalFraction(index: index, count: upper.count),
                    y: rect.maxY - rect.height * min(1, max(0, value / 100)))
        }
        for (index, value) in upper.enumerated() {
            if index == 0 { path.move(to: point(index, value)) }
            else { path.addLine(to: point(index, value)) }
        }
        if fillArea {
            for index in upper.indices.reversed() {
                path.addLine(to: point(index, lower?[index] ?? 0))
            }
            path.closeSubpath()
        }
        return path
    }
}

struct SystemStatsView: View {
    @ObservedObject var stats: SystemStatsModel
    private let systemColor = Color(red: 1, green: 0.23, blue: 0.23)
    private let userColor = Color(red: 0.16, green: 0.82, blue: 1)
    private var memoryColor: Color {
        switch stats.memory?.pressure ?? .unknown {
        case .normal: return Color(red: 0.22, green: 0.83, blue: 0.36)
        case .warning: return Color(red: 1, green: 0.65, blue: 0.08)
        case .critical: return Color(red: 1, green: 0.23, blue: 0.23)
        case .unknown: return .gray
        }
    }
    private let rule = Color.white.opacity(0.35)
    private func gb(_ bytes: UInt64) -> String { String(format: "%.2f GB", Double(bytes) / 1_073_741_824) }
    private func swap(_ bytes: UInt64) -> String {
        bytes < 1_073_741_824 ? String(format: "%.1f MB", Double(bytes) / 1_048_576) : gb(bytes)
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.2f%%", $0) } ?? "—" }
    private func row(_ title: String, _ value: String, color: Color = .white.opacity(0.8), compact: Bool = false, separator: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(title).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 1)
                Text(value).foregroundStyle(color).monospacedDigit()
            }.font(.system(size: compact ? 9 : 10, weight: .medium)).frame(height: compact ? 15.5 : 18)
            if separator { Rectangle().fill(rule).frame(height: 0.5) }
        }.accessibilityElement(children: .combine)
    }
    private func graphHeader(_ title: String) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            Rectangle().fill(rule).frame(height: 0.5)
        }
    }
    private func panel<Legend: View, Graph: View>(@ViewBuilder legend: () -> Legend, @ViewBuilder graph: () -> Graph) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0, content: legend).frame(maxHeight: .infinity, alignment: .top)
                .padding(8).frame(width: 151)
            Rectangle().fill(rule).frame(width: 0.5)
            VStack(spacing: 5, content: graph).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(height: 84)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.55), lineWidth: 0.8))
    }
    var body: some View {
        VStack(spacing: 9) {
            panel {
                row("System:", percent(stats.cpu?.system), color: systemColor)
                row("User:", percent(stats.cpu?.user), color: userColor)
                row("Idle:", percent(stats.cpu?.idle), separator: false)
            } graph: {
                graphHeader("CPU LOAD").help("Last minute of CPU use, on a fixed 0–100% scale. Newest reading is on the right. Separate sampling times can differ from Activity Monitor.")
                let system = stats.cpuHistory.map(\.system)
                let total = stats.cpuHistory.map(\.total)
                ZStack {
                    MonitorTrace(upper: total, lower: system, fillArea: true).fill(userColor.opacity(0.2))
                    MonitorTrace(upper: system, fillArea: true).fill(systemColor.opacity(0.3))
                    MonitorTrace(upper: total).stroke(userColor, lineWidth: 1)
                    MonitorTrace(upper: system).stroke(systemColor, lineWidth: 1)
                }.frame(maxHeight: .infinity).clipped().accessibilityHidden(true)
            }
            panel {
                row("Memory Used:", stats.memory.map { gb($0.used) } ?? "—", color: memoryColor, compact: true)
                row("Physical Memory:", stats.memory.map { gb($0.total) } ?? "—", compact: true)
                row("Cached Files:", stats.memory.map { gb($0.cached) } ?? "—", compact: true)
                row("Swap Used:", stats.memory?.swap.map { swap($0) } ?? "—", compact: true, separator: false)
            } graph: {
                graphHeader("MEMORY USED").help("RAM usage history, colored by macOS memory pressure: \(stats.memory?.pressure.label ?? "Unavailable"). The height shows usage; the color shows pressure.")
                ZStack {
                    MonitorTrace(upper: stats.memoryHistory, fillArea: true).fill(memoryColor.opacity(0.25))
                    MonitorTrace(upper: stats.memoryHistory).stroke(memoryColor, lineWidth: 1)
                }.frame(maxHeight: .infinity).clipped().accessibilityHidden(true)
            }
        }
    }
}
