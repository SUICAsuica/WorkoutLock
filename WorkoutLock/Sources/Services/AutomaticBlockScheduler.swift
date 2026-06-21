#if canImport(DeviceActivity)
import DeviceActivity
#endif
import Foundation

enum AutomaticBlockScheduler {
    static let activityName = "workout-lock.daily-block"

    static func schedule(startHour: Int, startMinute: Int) {
        #if canImport(DeviceActivity)
        if #available(iOS 16.0, *) {
            let center = DeviceActivityCenter()
            let activity = DeviceActivityName(activityName)
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: startHour, minute: startMinute),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )
            center.stopMonitoring([activity])
            try? center.startMonitoring(activity, during: schedule)
        }
        #endif
    }

    static func cancel() {
        #if canImport(DeviceActivity)
        if #available(iOS 16.0, *) {
            DeviceActivityCenter().stopMonitoring([DeviceActivityName(activityName)])
        }
        #endif
    }
}
