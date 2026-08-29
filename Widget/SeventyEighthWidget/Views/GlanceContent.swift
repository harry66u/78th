import SwiftUI
import ScheduleEngine

/// What every glance surface needs, reduced to strings and a colour once, so the
/// four widget sizes cannot drift apart.
struct GlanceContent {

    enum Mode {
        /// Counting down the end of the current class.
        case inClass
        /// Counting down to the start of the next class.
        case upNext
        /// Nothing running: end of day, or no school.
        case idle
    }

    var mode: Mode
    /// "AP Physics C", "Lunch", "Sunday".
    var title: String
    /// "402", or nil.
    var room: String?
    /// "Period 2", or nil.
    var slotLabel: String?
    /// What the countdown counts to. Nil when nothing is running.
    var target: Date?
    /// Where the countdown started, for the ring on the circular accessory.
    var intervalStart: Date?
    var color: Color
    /// Short status word above the countdown: "left", "until", "".
    var caption: String

    init(snapshot: ScheduleSnapshot) {
        switch snapshot.status {
        case .inPeriod(let current, _):
            mode = .inClass
            title = current.title
            room = current.room
            slotLabel = current.slotLabel
            target = current.end
            intervalStart = current.start
            color = Theme.courseColor(for: current)
            caption = "left"

        case .beforeSchool(let next), .passing(_, let next):
            mode = .upNext
            title = next.title
            room = next.room
            slotLabel = next.slotLabel
            target = next.start
            intervalStart = snapshot.now
            color = Theme.courseColor(for: next)
            caption = "until"

        case .dayComplete(let nextDay):
            mode = .idle
            if let nextDay {
                title = nextDay.title
                room = nextDay.room
                slotLabel = "Tomorrow"
            } else {
                title = "Done"
                room = nil
                slotLabel = nil
            }
            target = nil
            intervalStart = nil
            color = .secondary
            caption = ""

        case .noSchool(let reason):
            mode = .idle
            // "On a no school day show the day name and nothing else."
            title = reason
            room = nil
            slotLabel = nil
            target = nil
            intervalStart = nil
            color = .secondary
            caption = ""
        }
    }

    /// The remaining seconds at a given entry date.
    func secondsRemaining(at date: Date) -> Int? {
        guard let target else { return nil }
        return max(0, Int(target.timeIntervalSince(date).rounded(.up)))
    }

    /// 0 to 1 through the current interval, for the circular ring.
    func progress(at date: Date) -> Double {
        guard let target, let intervalStart, target > intervalStart else { return 0 }
        let total = target.timeIntervalSince(intervalStart)
        let elapsed = date.timeIntervalSince(intervalStart)
        return min(max(elapsed / total, 0), 1)
    }
}
