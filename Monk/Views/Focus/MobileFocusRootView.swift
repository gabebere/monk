import SwiftUI

struct MobileFocusRootView: View {
    @StateObject private var service = CrossDeviceFocusService.shared
    @State private var showingDeviceSetup = false

    var body: some View {
        ZStack {
            MobileFocusBackground()

            if let state = service.activeState {
                if service.hasRefreshedApplicationCatalog,
                   let application = service.unresolvedApplications(for: state).first {
                    MobileCrossDeviceApplicationSetupView(
                        service: service,
                        application: application
                    )
                    .transition(.opacity)
                } else if !state.allowedDomains.isEmpty && !service.hasConfiguredBrowserApps {
                    MobileBrowserSetupView(service: service, state: state)
                        .transition(.opacity)
                } else {
                    MobileActiveFocusView(state: state)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            } else if !service.isScreenTimeAuthorized || !service.hasConfiguredAllowedApps {
                MobileDeviceSetupView(service: service, isPresented: nil)
                    .transition(.opacity)
            } else {
                MobileFocusComposerView(service: service)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: service.activeState?.sessionID)
        .animation(.easeInOut(duration: 0.24), value: service.hasConfiguredAllowedApps)
        .task {
            service.start()
            await service.refreshReadiness()
        }
        .overlay(alignment: .topTrailing) {
            if service.activeState == nil,
               service.isScreenTimeAuthorized,
               service.hasConfiguredAllowedApps {
                Button {
                    showingDeviceSetup = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .foregroundStyle(.primary.opacity(0.72))
                .accessibilityLabel("Device setup")
                .padding()
            }
        }
        .sheet(isPresented: $showingDeviceSetup) {
            MobileDeviceSetupView(service: service, isPresented: $showingDeviceSetup)
                .presentationDetents([.large])
        }
    }
}

struct MobileFocusBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.indigo.opacity(0.20), Color.cyan.opacity(0.12), .clear]
                    : [Color.indigo.opacity(0.10), Color.cyan.opacity(0.12), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    MobileFocusRootView()
}
