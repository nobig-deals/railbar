import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.isConfigured {
                unconfiguredView
            } else if appState.projects.isEmpty && appState.isLoading {
                loadingView
            } else if let error = appState.error, appState.projects.isEmpty {
                errorView(error)
            } else {
                projectListView
            }

            if let warning = appState.rateLimitWarning {
                rateLimitBanner(warning)
            }

            Divider()
                .padding(.vertical, 4)

            footerButtons
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            if appState.isConfigured {
                appState.startPolling()
            }
        }
        .onDisappear {
            appState.stopPolling()
        }
    }

    // MARK: - States

    private var unconfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("API Token Required")
                .font(.headline)
            Text("Open Settings to add your Railway API token.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading projects...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await appState.fetchProjects() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Project List

    private var projectListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appState.projects) { project in
                ProjectRow(project: project)
            }
        }
    }

    // MARK: - Rate Limit Banner

    private func rateLimitBanner(_ message: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            if appState.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                Task { await appState.fetchProjects() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(appState.isLoading)

            Spacer()

            SettingsLink {
                Text("Settings")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.caption)
    }
}
