import Foundation
import GladeKit

/// The cleans done on one day, headed "Today", "Yesterday" or the date.
struct CleanDay: Identifiable {
  var day: Date
  var receipts: [Receipt]

  var id: Date { day }

  var title: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
    return sameYear
      ? day.formatted(.dateTime.weekday(.wide).month(.wide).day())
      : day.formatted(.dateTime.month(.wide).day().year())
  }

  /// Groups receipts by day, keeping them newest first.
  static func group(_ receipts: [Receipt]) -> [CleanDay] {
    let calendar = Calendar.current
    var days: [CleanDay] = []
    for receipt in receipts.sorted(by: { $0.date > $1.date }) {
      let day = calendar.startOfDay(for: receipt.date)
      if days.last?.day == day {
        days[days.count - 1].receipts.append(receipt)
      } else {
        days.append(CleanDay(day: day, receipts: [receipt]))
      }
    }
    return days
  }
}
