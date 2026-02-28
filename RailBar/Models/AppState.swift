import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.michalcerny.RailBar", category: "AppState")

@MainActor
final class AppState: ObservableObject {
    @Published var projects: [RailwayProject] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var rateLimitWarning: String?
    @Published var apiToken: String {
        didSet {
            KeychainHelper.save(token: apiToken)
        }
    }

    /// Index for rotating through active (building/deploying) services
    @Published var tickerIndex = 0

    private let apiService = RailwayAPIService()
    private var refreshTimer: Timer?
    private var tickerTimer: Timer?
    private var currentPollingInterval: TimeInterval = 30

    // MARK: - Computed: all services with their parent project name

    struct ServiceInfo {
        let projectName: String
        let serviceName: String
        let status: DeploymentStatus
    }

    var allServices: [ServiceInfo] {
        projects.flatMap { project in
            project.services.compactMap { service in
                guard let deployment = service.latestDeployment else { return nil }
                return ServiceInfo(
                    projectName: project.name,
                    serviceName: service.name,
                    status: deployment.status
                )
            }
        }
    }

    /// Services currently building/deploying/initializing
    var activeServices: [ServiceInfo] {
        allServices.filter { [.building, .deploying, .initializing].contains($0.status) }
    }

    // MARK: - Status counts

    var runningCount: Int {
        allServices.filter { $0.status == .success }.count
    }

    var errorCount: Int {
        allServices.filter { $0.status == .failed || $0.status == .crashed }.count
    }

    var buildingCount: Int {
        activeServices.count
    }

    // MARK: - Menu bar icon

    var statusIcon: String {
        if apiToken.isEmpty { return "train.side.front.car" }
        if isLoading && projects.isEmpty { return "arrow.trianglehead.2.counterclockwise" }
        if error != nil { return "exclamationmark.triangle" }
        if errorCount > 0 { return "xmark.circle.fill" }
        if buildingCount > 0 { return "arrow.trianglehead.2.counterclockwise" }
        return "train.side.front.car"
    }

    // MARK: - Menu bar text (shown next to icon)

    var statusText: String {
        if apiToken.isEmpty { return "" }
        if isLoading && projects.isEmpty { return "Loading..." }
        if error != nil { return "Error" }

        // When something is building, rotate through active services
        if !activeServices.isEmpty {
            let idx = tickerIndex % activeServices.count
            let svc = activeServices[idx]
            let verb = svc.status == .building ? "building" : svc.status == .deploying ? "deploying" : "starting"
            return "\(svc.projectName) › \(svc.serviceName) \(verb)"
        }

        // Otherwise show summary counts
        var parts: [String] = []
        if runningCount > 0 { parts.append("✓\(runningCount)") }
        if errorCount > 0 { parts.append("✕\(errorCount)") }
        let sleepCount = allServices.filter { $0.status == .sleeping }.count
        if sleepCount > 0 { parts.append("⏸\(sleepCount)") }

        return parts.isEmpty ? "No services" : parts.joined(separator: " ")
    }

    var isConfigured: Bool {
        !apiToken.isEmpty
    }

    init() {
        self.apiToken = KeychainHelper.loadToken() ?? ""
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        currentPollingInterval = 30
        Task { await fetchProjects() }
        restartRefreshTimer()
        // Ticker rotates every 3 seconds for building services
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if !self.activeServices.isEmpty {
                    self.tickerIndex += 1
                } else {
                    self.tickerIndex = 0
                }
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        tickerTimer?.invalidate()
        tickerTimer = nil
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

        // Adapt polling interval based on rate-limit budget
        await adaptPollingInterval()
    }

    private func adaptPollingInterval() async {
        let tracker = apiService.rateLimitTracker
        let suggested = await tracker.suggestedPollingInterval
        let remaining = await tracker.remaining
        let limit = await tracker.limit

        if let remaining, let limit {
            if remaining <= 0 {
                rateLimitWarning = "Rate limit reached – pausing until reset"
            } else if Double(remaining) / Double(max(limit, 1)) < 0.25 {
                rateLimitWarning = "Rate limit low (\(remaining)/\(limit) remaining)"
            } else {
                rateLimitWarning = nil
            }
        } else {
            rateLimitWarning = nil
        }

        if suggested != currentPollingInterval {
            logger.info("Adjusting poll interval: \(self.currentPollingInterval)s → \(suggested)s (budget: \(remaining ?? -1)/\(limit ?? -1))")
            currentPollingInterval = suggested
            restartRefreshTimer()
        }
    }

    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: currentPollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchProjects()
            }
        }
    }
}
