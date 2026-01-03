import SwiftUI

struct WeekdayPicker: View {
    @Binding var selectedWeekdays: Set<Int>

    private let symbols: [(label: String, weekday: Int)] = [
        ("S", 1), ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(symbols, id: \.weekday) { symbol in
                let isSelected = selectedWeekdays.contains(symbol.weekday)
                Text(symbol.label)
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .background(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.10))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.6 : 0.2), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .onTapGesture {
                        toggle(symbol.weekday)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func toggle(_ weekday: Int) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }
}
