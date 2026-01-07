import CodexBarCore
import SwiftUI

/// Segmented control for selecting time period aggregation.
struct TimePeriodPicker: View {
    @Binding var selection: CostUsageTimePeriod

    var body: some View {
        Picker("Period", selection: self.$selection) {
            ForEach(CostUsageTimePeriod.allCases, id: \.self) { period in
                Text(period.displayName)
                    .tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }
}

#Preview {
    @Previewable @State var selection: CostUsageTimePeriod = .month
    TimePeriodPicker(selection: $selection)
        .padding()
}
