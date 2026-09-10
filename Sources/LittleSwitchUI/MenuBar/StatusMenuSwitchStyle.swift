import SwiftUI

/// NSSwitch desaturates when its application is inactive, including inside an
/// open NSMenu. Keep the connection indicator tied to its value instead.
struct StatusMenuSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var layoutDirection
    @GestureState private var dragTranslation: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        let offset = StatusMenuSwitchTrack.thumbOffset(
            isOn: configuration.isOn,
            translation: dragTranslation,
            layoutDirection: layoutDirection
        )
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint)
                    .opacity(configuration.isOn ? 1 : 0)
                Circle().fill(.white)
                    .frame(width: StatusMenuSwitchTrack.thumb, height: StatusMenuSwitchTrack.thumb)
                    .padding(StatusMenuSwitchTrack.inset)
                    .offset(x: offset)
            }
            .frame(width: StatusMenuSwitchTrack.width, height: StatusMenuSwitchTrack.height)
            .overlay {
                Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 1)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            DragGesture(minimumDistance: 3)
                .updating($dragTranslation) { value, translation, _ in
                    if isEnabled { translation = value.translation.width }
                }
                .onEnded { value in
                    guard isEnabled else { return }
                    let destination = StatusMenuSwitchTrack.draggedValue(
                        isOn: configuration.isOn,
                        translation: value.translation.width,
                        layoutDirection: layoutDirection
                    )
                    guard destination != configuration.isOn else { return }
                    configuration.isOn = destination
                }
        )
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: configuration.isOn)
    }

}
