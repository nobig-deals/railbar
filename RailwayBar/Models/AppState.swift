import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var projects: [RailwayProject] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var apiToken: String {
        didSet {
            KeychainHelper.save(token: apiToken)
        }
    }

    private let apiService = RailwayAPIService()
    private var refreshTimer: Timer?

    /// Icon shown in the menu bar, reflects overall status
    var statusIcon: String {
        if apiToken.isEmpty { return "train.side.front.car" }
        if isLoading && projects.isEmpty { return "arrow.trianglehead.2.counterclockwise" }
        if error != nil { return "exclamationmark.triangle" }

        let allDeployments = projects.flatMap { $0.services.compactMap { $0.latestDeployment } }
        if allDeployments.contains(where: { $0.status == .crashed || $0.status == .failed }) {
            return "xmark.circle.fill"
        }
        if allDeployments.contains(where: { $0.status == .building || $0.status == .deploying || $0.status == .initializing }) {
            return "arrow.trianglehead.2.counterclockwise"
        }
        return "train.side.front.car"
    }

    var isConfigured: Bool {
        !apiToken.isEmpty
    }

    init() {
        self.apiToken = KeychainHelper.loadToken() ?? ""
    }

    func startPolling() {
        stopPolling()
        Task { await fetchProjects() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchProjects()
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func fetchProjects() async {
        guard isConfigured else { return }

        isLoading = true
        error = nil

        do {
            let fetched = try await apiService.fetchProjects(token: apiToken)
            self.projects = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
