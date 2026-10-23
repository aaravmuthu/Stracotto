import Foundation
import Observation

/// AlDente's Schedule: timed actions with repeats, catch-up after sleep, and a task history.
@MainActor @Observable
final class Scheduler {
    enum Action: Codable, Hashable {
        case setLimit(Int), startCalibration, topUp, pauseCharging, dischargeTo(Int), lowPowerOn, lowPowerOff

        var title: String {
            switch self {
            case .setLimit(let v): "Set Charge Limit to \(v)%"
            case .startCalibration: "Start Calibration Mode"
            case .topUp: "Top Up"
            case .pauseCharging: "Pause Charging"
            case .dischargeTo(let v): "Discharge to \(v)%"
            case .lowPowerOn: "Enable Low Power Mode"
            case .lowPowerOff: "Disable Low Power Mode"
            }
        }
        var icon: String {
            switch self {
            case .setLimit: "slider.horizontal.below.rectangle"
            case .startCalibration: "arrow.triangle.2.circlepath"
            case .topUp: "plus.circle"
            case .pauseCharging: "pause.circle"
            case .dischargeTo: "minus.circle"
            case .lowPowerOn, .lowPowerOff: "leaf"
            }
        }
    }

    enum Repeat: String, Codable, CaseIterable, Identifiable {
        case never = "Don't Repeat", daily = "Daily", weekdays = "Weekdays", weekly = "Weekly",
             biweekly = "Biweekly", monthly = "Monthly", yearly = "Yearly"
        var id: Self { self }
    }

    struct Task: Codable, Identifiable, Hashable {
        var id = UUID()
        var action: Action
        var date: Date
        var repeats: Repeat
        var enabled = true
    }

    struct HistoryEntry: Codable, Identifiable, Hashable {
        var id = UUID()
        let date: Date
        let title: String
        let note: String?
    }

    /// Ready-made tasks, like AlDente's templates.
    static let templates: [(name: String, task: Task)] = [
        ("Monthly Calibration", Task(action: .startCalibration, date: nextDate(hour: 10), repeats: .monthly)),
        ("Full Charge Before Work", Task(action: .topUp, date: nextDate(hour: 6), repeats: .weekdays)),
        ("Back to 80% at Night", Task(action: .setLimit(80), date: nextDate(hour: 22), repeats: .daily)),
    ]

    var tasks: [Task] = [] { didSet { save() } }
    private(set) var history: [HistoryEntry] = []
    var catchUpMissed = true { didSet { UserDefaults.standard.set(catchUpMissed, forKey: "schedule.catchUp") } }

    private let charge: ChargeController
    private var timer: Timer?

    init(charge: ChargeController) {
        self.charge = charge
        let d = UserDefaults.standard
        tasks = (d.data(forKey: "schedule.tasks")).flatMap { try? JSONDecoder().decode([Task].self, from: $0) } ?? []
        history = (d.data(forKey: "schedule.history")).flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
        catchUpMissed = d.object(forKey: "schedule.catchUp") as? Bool ?? true
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func add(_ task: Task) { tasks.append(task); tasks.sort { $0.date < $1.date } }
    func remove(_ task: Task) { tasks.removeAll { $0.id == task.id } }

    private func tick() {
        let now = Date()
        for i in tasks.indices where tasks[i].enabled && tasks[i].date <= now {
            // A task more than 10 minutes late was missed during sleep or while quit.
            let missed = now.timeIntervalSince(tasks[i].date) > 600
            if !missed || catchUpMissed { perform(tasks[i].action) }
            if let next = Self.advance(tasks[i].date, by: tasks[i].repeats, after: now) {
                tasks[i].date = next
            } else {
                tasks[i].enabled = false
            }
        }
    }

    private func perform(_ action: Action) {
        var note: String?
        switch action {
        case .setLimit(let v): charge.limit = charge.snapped(v)
        case .topUp: charge.isToppingUp = true
        default:
            if charge.backendStatus != .ready { note = "Skipped: charge control isn't active" }
        }
        history.insert(HistoryEntry(date: Date(), title: action.title, note: note), at: 0)
        history = Array(history.prefix(200))
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: "schedule.history")
    }

    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(tasks), forKey: "schedule.tasks") }

    static func nextDate(hour: Int) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return today > Date() ? today : cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    static func advance(_ date: Date, by repeats: Repeat, after now: Date) -> Date? {
        let cal = Calendar.current
        var next = date
        repeat {
            switch repeats {
            case .never: return nil
            case .daily: next = cal.date(byAdding: .day, value: 1, to: next)!
            case .weekdays:
                repeat { next = cal.date(byAdding: .day, value: 1, to: next)! } while cal.isDateInWeekend(next)
            case .weekly: next = cal.date(byAdding: .weekOfYear, value: 1, to: next)!
            case .biweekly: next = cal.date(byAdding: .weekOfYear, value: 2, to: next)!
            case .monthly: next = cal.date(byAdding: .month, value: 1, to: next)!
            case .yearly: next = cal.date(byAdding: .year, value: 1, to: next)!
            }
        } while next <= now
        return next
    }
}
