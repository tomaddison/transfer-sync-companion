import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    let onBack: () -> Void

    var body: some View {
        @Bindable var store = settingsStore

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.companionMutedText)
                }
                .buttonStyle(.ghostIcon)

                Text("Settings")
                    .font(Font.companion(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            VStack(spacing: 10) {
                settingsCard(
                    title: "Auto-stack versions",
                    description: "Automatically stack files with similar names as new versions",
                    isOn: $store.autoStackEnabled
                )

                settingsCard(
                    title: "Notifications",
                    description: "Show macOS notifications for upload events",
                    isOn: $store.notificationsEnabled
                )

                settingsCard(
                    title: "Launch at login",
                    description: "Start TransferSync when you log in to your Mac",
                    isOn: $store.launchAtLogin
                )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private func settingsCard(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Font.companion(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                Text(description)
                    .font(Font.companion(size: 11))
                    .foregroundStyle(Color.companionMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.companionCard)
        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.cardCornerRadius))
    }
}
