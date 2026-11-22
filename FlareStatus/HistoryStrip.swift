import FlareStatusKit
import SwiftUI

/// The row of daily uptime bars, oldest on the left and today on the right.
struct HistoryStrip: View {
    let days: [DayUptime]
    var gapRatio: CGFloat = 0.3

    var body: some View {
        Canvas { context, size in
            guard !days.isEmpty else { return }
            let count = CGFloat(days.count)
            let slot = size.width / count
            let gap = min(slot * gapRatio, 6)
            let width = max(1, slot - gap)
            let radius = min(width / 2, 4)
            for (index, day) in days.enumerated() {
                let rect = CGRect(x: CGFloat(index) * slot + gap / 2, y: 0, width: width, height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius),
                    with: .color(Theme.color(forUptime: day.percent)))
            }
        }
        .accessibilityLabel("Uptime for the last \(days.count) days")
    }
}

#Preview {
    let monitor = SampleData.snapshot(.outage).monitors[0]
    return HistoryStrip(days: monitor.dailyUptime(days: 90, now: Int(Date().timeIntervalSince1970)))
        .frame(width: 1200, height: 60)
        .padding(60)
        .background(Theme.background)
}
