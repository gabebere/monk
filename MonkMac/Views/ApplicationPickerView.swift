import AppKit
import SwiftUI

struct ApplicationPickerView: View {
    @ObservedObject var catalog: ApplicationCatalog
    @Binding var selectedApplications: [ApplicationDescriptor]
    @FocusState.Binding var focusedField: FocusCommandField?
    let onAdvance: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    var title = "Allowed apps"
    var placeholder = "Type an application"
    @State private var query = ""
    @State private var highlightedIndex = 0

    private var selectedIDs: Set<String> {
        Set(selectedApplications.map(\.id))
    }

    private var matches: [ApplicationDescriptor] {
        catalog.matches(for: query, excluding: selectedIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 9) {
                Image(systemName: "app.badge.checkmark")
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .applications)
                    .onSubmit(handleSubmit)
                    .onKeyPress(.downArrow) {
                        if matches.isEmpty {
                            onMoveDown()
                        } else {
                            moveHighlight(by: 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        if matches.isEmpty {
                            onMoveDown()
                        } else {
                            moveHighlight(by: 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if matches.isEmpty {
                            onMoveUp()
                        } else {
                            moveHighlight(by: -1)
                        }
                        return .handled
                    }
                    .onKeyPress(.leftArrow) {
                        if matches.isEmpty {
                            onMoveUp()
                        } else {
                            moveHighlight(by: -1)
                        }
                        return .handled
                    }
                    .onChange(of: query) {
                        highlightedIndex = 0
                    }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            if !matches.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, application in
                        Button {
                            add(application)
                        } label: {
                            HStack(spacing: 10) {
                                applicationIcon(application, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(application.displayName)
                                        .foregroundStyle(.primary)
                                    if application.isRemoteMobileApplication {
                                        Text("On iPhone or iPad")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "return")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            index == highlightedIndex ? Color.primary.opacity(0.11) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .onHover { isHovering in
                            if isHovering {
                                highlightedIndex = index
                            }
                        }
                    }
                }
                .padding(5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if !selectedApplications.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedApplications) { application in
                            SelectionChip(application: application) {
                                selectedApplications.removeAll { $0.id == application.id }
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleSubmit() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onAdvance()
            return
        }
        guard matches.indices.contains(highlightedIndex) else { return }
        add(matches[highlightedIndex])
    }

    private func add(_ application: ApplicationDescriptor) {
        selectedApplications.append(application)
        query = ""
        highlightedIndex = 0
    }

    private func moveHighlight(by offset: Int) {
        guard !matches.isEmpty else { return }
        highlightedIndex = (highlightedIndex + offset + matches.count) % matches.count
    }

    @ViewBuilder
    private func applicationIcon(_ application: ApplicationDescriptor, size: CGFloat) -> some View {
        if application.isRemoteMobileApplication {
            Image(systemName: "iphone")
                .font(.system(size: size * 0.68, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundleURL.path))
                .resizable()
                .frame(width: size, height: size)
        }
    }
}

struct SelectionChip: View {
    let title: String
    let systemImage: String?
    let applicationURL: URL?
    let onRemove: () -> Void

    init(title: String, systemImage: String, onRemove: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.applicationURL = nil
        self.onRemove = onRemove
    }

    init(application: ApplicationDescriptor, onRemove: @escaping () -> Void) {
        self.title = application.displayName
        self.systemImage = nil
        self.applicationURL = application.bundleURL
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 7) {
            leadingIcon
            Text(title)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary.opacity(0.92))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.primary.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let applicationURL {
            if applicationURL.path.hasPrefix("/Monk/RemoteApplications/") {
                Image(systemName: "iphone")
                    .font(.caption)
                    .frame(width: 17, height: 17)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 17, height: 17)
            }
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.caption)
        }
    }
}
