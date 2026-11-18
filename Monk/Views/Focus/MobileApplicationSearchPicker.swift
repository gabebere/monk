import FamilyControls
import ManagedSettings
import SwiftUI

struct MobileApplicationSearchPicker: View {
    @ObservedObject var service: CrossDeviceFocusService
    @Binding var selection: FamilyActivitySelection
    @Binding private var macSelection: [CrossDeviceApplication]
    let openSystemPicker: () -> Void
    private let includesMacApplications: Bool

    @State private var query = ""
    @FocusState private var searchIsFocused: Bool

    init(
        service: CrossDeviceFocusService,
        selection: Binding<FamilyActivitySelection>,
        macSelection: Binding<[CrossDeviceApplication]>? = nil,
        openSystemPicker: @escaping () -> Void
    ) {
        self.service = service
        _selection = selection
        _macSelection = macSelection ?? .constant([])
        self.openSystemPicker = openSystemPicker
        includesMacApplications = macSelection != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            localApplicationPicker

            if canSearchCatalog {
                if includesMacApplications && service.searchableApplications.isEmpty {
                    Text("Choose apps for this device above. Add Mac apps below to allow them on your Mac too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                searchField

                if !trimmedQuery.isEmpty {
                    searchResults
                }
            }

            if !selection.applicationTokens.isEmpty || !macSelection.isEmpty {
                selectedApplications
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search available app names", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($searchIsFocused)
                .onSubmit(selectFirstResult)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear app search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(searchIsFocused ? Color.primary.opacity(0.32) : .clear, lineWidth: 1)
        }
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            if filteredApplications.isEmpty && filteredMacApplications.isEmpty {
                Text("No apps match “\(trimmedQuery)”.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(Array(filteredApplications.prefix(6).enumerated()), id: \.element.id) { index, application in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 52)
                    }
                    applicationResult(application)
                }

                ForEach(Array(visibleMacApplications.enumerated()), id: \.element.id) { index, application in
                    if !filteredApplications.isEmpty || index > 0 {
                        Divider()
                            .padding(.leading, 52)
                    }
                    macApplicationResult(application)
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func applicationResult(_ application: MobileInstalledApplication) -> some View {
        let isSelected = selection.applicationTokens.contains(application.token)

        return Button {
            toggle(application.token)
        } label: {
            HStack(spacing: 12) {
                Label(application.token)
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)

                Text(service.displayName(for: application))
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Remove app" : "Allow app")
    }

    private func macApplicationResult(_ application: CrossDeviceApplication) -> some View {
        let isSelected = macSelection.contains(application)

        return Button {
            if isSelected {
                macSelection.removeAll { $0.id == application.id }
            } else {
                macSelection.append(application)
            }
            query = ""
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .lineLimit(1)
                    Text("On Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isSelected ? "Remove" : "Allow") \(application.displayName) on Mac")
    }

    private var selectedApplications: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedTokens, id: \.self) { token in
                    Button {
                        selection.applicationTokens.remove(token)
                    } label: {
                        HStack(spacing: 7) {
                            selectedApplicationLabel(token)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(.thinMaterial, in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove selected app")
                }

                ForEach(macSelection) { application in
                    Button {
                        macSelection.removeAll { $0.id == application.id }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "desktopcomputer")
                            Text(application.displayName)
                                .lineLimit(1)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(.thinMaterial, in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(application.displayName) on Mac")
                }
            }
        }
    }

    private var localApplicationPicker: some View {
        Button(action: openSystemPicker) {
            HStack(spacing: 12) {
                Image(systemName: "app.badge.checkmark")

                VStack(alignment: .leading, spacing: 2) {
                    Text(applicationCountLabel)
                    Text("Choose apps on this device with Apple’s private list")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSearchCatalog: Bool {
        !service.searchableApplications.isEmpty ||
            (includesMacApplications && !service.macApplications.isEmpty)
    }

    private var filteredApplications: [MobileInstalledApplication] {
        guard !trimmedQuery.isEmpty else { return [] }
        return service.searchableApplications.filter {
            service.displayName(for: $0).localizedCaseInsensitiveContains(trimmedQuery) ||
                ($0.bundleIdentifier?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    private var filteredMacApplications: [CrossDeviceApplication] {
        guard includesMacApplications, !trimmedQuery.isEmpty else { return [] }
        let localBundleIdentifiers = Set(
            service.searchableApplications.compactMap { $0.bundleIdentifier?.lowercased() }
        )
        return service.macApplications.filter { application in
            let matchesQuery = application.displayName.localizedCaseInsensitiveContains(trimmedQuery) ||
                (application.sourceBundleIdentifier?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
            let isAlreadyLocal = application.sourceBundleIdentifier.map {
                localBundleIdentifiers.contains($0.lowercased())
            } ?? false
            return matchesQuery && !isAlreadyLocal
        }
    }

    private var visibleMacApplications: [CrossDeviceApplication] {
        let remainingCount = max(0, 6 - min(filteredApplications.count, 6))
        return Array(filteredMacApplications.prefix(remainingCount))
    }

    private var selectedTokens: [ManagedSettings.ApplicationToken] {
        let selected = selection.applicationTokens
        let catalogTokens = service.searchableApplications
            .map(\.token)
            .filter(selected.contains)
        let knownTokens = Set(catalogTokens)
        return catalogTokens + selected.filter { !knownTokens.contains($0) }
    }

    private var applicationCountLabel: String {
        let count = selection.applicationTokens.count
        return count == 0 ? "Choose apps" : "\(count) app\(count == 1 ? "" : "s") allowed"
    }

    @ViewBuilder
    private func selectedApplicationLabel(_ token: ManagedSettings.ApplicationToken) -> some View {
        if let application = service.searchableApplications.first(where: { $0.token == token }) {
            Label(application.token)
                .labelStyle(.iconOnly)
                .frame(width: 20, height: 20)
            Text(service.displayName(for: application))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        } else {
            Label(token)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }

    private func toggle(_ token: ManagedSettings.ApplicationToken) {
        if selection.applicationTokens.contains(token) {
            selection.applicationTokens.remove(token)
        } else {
            selection.applicationTokens.insert(token)
        }
        query = ""
    }

    private func selectFirstResult() {
        if let application = filteredApplications.first {
            selection.applicationTokens.insert(application.token)
        } else if let application = filteredMacApplications.first,
                  !macSelection.contains(application) {
            macSelection.append(application)
        } else {
            return
        }
        query = ""
    }
}
