import SwiftUI

/// Settings window, opened on ⌘, via the standard `Settings` scene.
struct SettingsWindow: View {
    @Bindable var controller: DictationController

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            SettingsPanelView(controller: controller)
        }
        .frame(width: 580, height: 520)
    }
}
