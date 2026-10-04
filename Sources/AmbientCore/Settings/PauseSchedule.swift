import Foundation

public enum PauseSchedule {
    /// "Pause until tomorrow": resumes at `hour` o'clock the next morning.
    /// Pausing in the small hours (before `hour`) resumes the same morning.
    public static func untilTomorrow(from now: Date, calendar: Calendar = .current, hour: Int = 6) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let todayAtHour = calendar.date(byAdding: .hour, value: hour, to: startOfToday) ?? startOfToday
        if now < todayAtHour { return todayAtHour }
        return calendar.date(byAdding: .day, value: 1, to: todayAtHour) ?? todayAtHour.addingTimeInterval(24 * 60 * 60)
    }
}
