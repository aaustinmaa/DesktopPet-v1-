import SwiftUI

struct IntegerInput {
    var text = ""
    var number: Int { Int(text) ?? 0 }
    mutating func accept(_ input: String, range: ClosedRange<Int>) -> Int? {
        if input.isEmpty || (input == "-" && range.lowerBound < 0) {
            text = input
            return 0
        }
        guard let parsed = Int(input) else { return nil }
        let value = min(range.upperBound, max(range.lowerBound, parsed))
        text = parsed == value ? input : String(value)
        return value
    }
    mutating func synchronize(_ value: Int, editing: Bool) {
        if !editing || number != value { text = String(value) }
    }
}

/// Incomplete input is local; invalid/overflowing input is rejected, never saved as an old value.
struct IntegerField: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = Int.min...Int.max
    @State private var input = IntegerInput()
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: Binding(get: { input.text }, set: { text in
            if let updated = input.accept(text, range: range), updated != value { value = updated }
        }))
            .focused($focused)
            .onAppear { input.synchronize(value, editing: false) }
            .onChange(of: value) { _, number in input.synchronize(number, editing: focused) }
            .onChange(of: focused) { _, active in
                if !active { input.synchronize(value, editing: false) }
            }
            .onSubmit { input.synchronize(value, editing: false) }
    }
}
