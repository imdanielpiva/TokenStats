import TokenStatsCore
import SwiftUI

/// Multi-select menu for filtering by model.
struct ModelFilterPicker: View {
    let availableModels: [String]
    @Binding var selectedModels: Set<String>

    private var buttonLabel: String {
        if self.selectedModels.isEmpty {
            return "All Models"
        } else if self.selectedModels.count == 1 {
            return UsageFormatter.modelDisplayName(self.selectedModels.first!)
        } else {
            return "\(self.selectedModels.count) Models"
        }
    }

    var body: some View {
        Menu {
            Button("All Models") {
                self.selectedModels = []
            }
            .disabled(self.selectedModels.isEmpty)

            Divider()

            ForEach(self.availableModels, id: \.self) { model in
                Toggle(isOn: self.binding(for: model)) {
                    Text(UsageFormatter.modelDisplayName(model))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(self.buttonLabel)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }

    private func binding(for model: String) -> Binding<Bool> {
        Binding(
            get: { self.selectedModels.contains(model) },
            set: { isSelected in
                if isSelected {
                    self.selectedModels.insert(model)
                } else {
                    self.selectedModels.remove(model)
                }
            })
    }
}

#Preview {
    @Previewable @State var selected: Set<String> = []
    ModelFilterPicker(
        availableModels: ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"],
        selectedModels: $selected)
        .padding()
}
