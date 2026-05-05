import SwiftUI

struct HeaderView: View {
    @Binding var isEditMode: Bool
    let onAdd: () -> Void

    @State private var store = HeaderStore()
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        HStack(alignment: .center) {
            titleSection
            Spacer()
            HStack(spacing: 8) {
                headerButton(icon: "plus", action: onAdd)
                    .disabled(isEditMode)
                    .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)
                    .animation(DesignTokens.toggleSpring, value: isEditMode)
                // 편집 모드 토글: 아이콘은 동일하게 유지하고 active tint 만 바꿔
                // 형태 점프 없이 상태가 명확하게 보이도록 한다.
                headerButton(
                    icon: "arrow.up.arrow.down",
                    isActive: isEditMode,
                    iconSize: 11
                ) {
                    isEditMode.toggle()
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 12, trailing: 20))
    }

    // MARK: Title

    @ViewBuilder
    private var titleSection: some View {
        if store.state.isEditingTitle {
            TextField("", text: draftTitleBinding)
                .textFieldStyle(.plain)
                .font(DesignTokens.titleFont)
                .foregroundStyle(DesignTokens.titleColor)
                .tracking(-0.3)
                .focused($titleFieldFocused)
                .focusEffectDisabled()
                .frame(maxWidth: 180)
                .onSubmit { store.send(.commitTitle) }
                .onChange(of: titleFieldFocused) { _, focused in
                    if !focused { store.send(.commitTitle) }
                }
                // TextField 가 처음 렌더된 시점에 포커스 → 별도의 asyncAfter 불필요.
                .onAppear { titleFieldFocused = true }
        } else {
            HStack(spacing: 6) {
                Text(store.state.widgetTitle.isEmpty ? "Today" : store.state.widgetTitle)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.titleColor)
                    .tracking(-0.3)
                    .onTapGesture(count: 2) { store.send(.beginEditingTitle) }

                Button(action: { store.send(.beginEditingTitle) }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DesignTokens.textMeta)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .opacity(store.state.isTitleEditButtonHovered ? 1.0 : 0.75)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    store.send(.titleEditButtonHovered(hovering))
                }
                .help("제목 편집")
                .disabled(isEditMode)
                .opacity(isEditMode ? DesignTokens.disabledOpacity : 1.0)
                .animation(DesignTokens.toggleSpring, value: isEditMode)
            }
        }
    }

    private var draftTitleBinding: Binding<String> {
        Binding(
            get: { store.state.draftTitle },
            set: { store.send(.updateDraftTitle($0)) }
        )
    }

    // MARK: Buttons

    private func headerButton(
        icon: String,
        isActive: Bool = false,
        iconSize: CGFloat = 12,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = store.state.hoveredHeaderButton == icon

        return Button(action: action) {
            ZStack {
                // Base: dark glass disc — 다크모드에선 white 의 미세한 fill 만으로
                // floating 한 느낌. light 모드는 기존 톤 유지.
                Circle()
                    .fill(DT.headerButtonFill(active: isActive, hovered: isHovered))

                // Stroke: active 시에만 살짝 더 또렷
                Circle()
                    .strokeBorder(
                        DT.headerButtonStroke(active: isActive, hovered: isHovered),
                        lineWidth: 0.5
                    )

                // 아주 옅은 상단 inner highlight — 라이트에선 살짝, 다크에선 더 옅게
                LinearGradient(
                    colors: [DT.headerButtonHighlight(active: isActive), .clear],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.6)
                )
                .clipShape(Circle())

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(isActive ? DT.blue : DT.buttonIcon)
            }
            .frame(width: DesignTokens.headerButton, height: DesignTokens.headerButton)
            .scaleEffect(isHovered && !isActive ? 1.06 : 1.0)
            .animation(DesignTokens.toggleSpring, value: isActive)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            store.send(.headerButtonHovered(icon: icon, hovering: hovering))
        }
    }
}
