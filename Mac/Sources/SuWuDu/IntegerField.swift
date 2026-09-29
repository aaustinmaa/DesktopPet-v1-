import SwiftUI

/// Keep incomplete input local so deleting the last digit never restores it.
struct IntegerField: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = Int.min...Int.max
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: Binding(get: { text }, set: { input in
            text = input
            let number = input.isEmpty || input == "-" ? 0 : Int(input)
            if let number {
                let updated = min(range.upperBound, max(range.lowerBound, number))
                if value != updated { value = updated }
            }
        }))
            .focused($focused)
            .onAppear { text = String(value) }
            .onChange(of: value) { _, number in
                if !focused { text = String(number) }
            }
            .onChange(of: focused) { _, active in
                if !active { text = String(value) }
            }
            .onSubmit { text = String(value) }
    }
}
