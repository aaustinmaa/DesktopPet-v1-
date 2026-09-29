import SwiftUI

@MainActor struct TargetScheduleView: View {
    @ObservedObject var model: AppModel
    let initialDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "month"
    @State private var from = Date()
    @State private var through = Date()
    @State private var target = 0

    private var lower: Date {
        mode == "month" ? Calendar.current.dateInterval(of: .month, for: from)!.start : from
    }
    private var upper: Date? {
        if mode == "future" { return nil }
        if mode == "month" {
            return Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.dateInterval(of: .month, for: from)!.end)!
        }
        return through
    }
    private func key(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PetHeading(title: "批量设置番茄钟目标", subtitle: "提前安排每天的目标数量。")
            Picker("设置范围", selection: $mode) {
                Text("整个月").tag("month")
                Text("日期范围").tag("range")
                Text("所有未来日期").tag("future")
            }.pickerStyle(.segmented)
            DatePicker(mode == "month" ? "选择月份（该日期所在月）" : "开始日期", selection: $from, displayedComponents: .date)
            if mode == "range" { DatePicker("结束日期（含当天）", selection: $through, displayedComponents: .date) }
            HStack {
                Text("每天目标（个）")
                IntegerField(title: "0–999", value: $target, range: 0...999).frame(width: 90)
            }
            Text(upper.map { "将设置 \(key(lower)) 至 \(key($0)) 每天的目标。" } ?? "从 \(key(lower)) 起每天生效，无截止日期。")
                .font(.callout)
            Text("覆盖范围内已有目标，保留番茄钟和 Notes。之后仍可单独修改某一天；重复批量设置以最新设置为准。")
                .font(.caption).foregroundStyle(PetTheme.muted)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("应用") {
                    model.setTargets(from: key(lower), through: upper.map(key), target: target)
                    dismiss()
                }.buttonStyle(PetButtonStyle(primary: true))
                    .disabled(upper.map { key($0) < key(lower) } ?? false)
            }
        }.padding(26).frame(width: 480).petPage()
            .onAppear { from = initialDate; through = initialDate; target = model.data.journalDay(key(initialDate)).target }
    }
}
