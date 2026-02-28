import Foundation
import OSLog

private let logger = Logger(subsystem: "com.michalcerny.RailBar", category: "API")

// MARK: - Rate Limit Tracker

actor RateLimitTracker {
    private(set) var limit: Int?
    private(set) var remaining: Int?
    private(set) var resetDate: Date?

    func update(from response: HTTPURLResponse) {
        if let val = response.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init) {
            limit = val
        }
        if let val = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
            remaining = val
        }
        if let val = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) {
            resetDate = Date(timeIntervalSince1970: val)
        }
    }

    /// Seconds to wait before the next request is safe, or 0 if OK to proceed.
    func secondsUntilReady() -> TimeInterval {
        guard let remaining, remaining <= 0, let resetDate else { return 0 }
        return max(resetDate.timeIntervalSinceNow + 1, 0)   // +1s buffer
    }

    /// Adaptive polling interval based on how much budget is left.
    var suggestedPollingInterval: TimeInterval {
        guard let limit, let remaining, limit > 0 else { return 30 }
        let ratio = Double(remaining) / Double(limit)
        if ratio < 0.1  { return 120 }   // <10% left  → 2 min
        if ratio < 0.25 { return 60  }   // <25% left  → 1 min
        return 30                          // plenty     → 30 s
    }
}

struct RailwayAPIService {
    private let endpoint = URL(string: "https://backboard.railway.com/graphql/v2")!
    private let maxRetries = 3
    private let deploymentBatchSize = 5
    let rateLimitTracker = RateLimitTracker()

    func fetchProjects(token: String) async throws -> [RailwayProject] {
        // Single query: get all projects with their services and environments
        let query = """
        query {
            projects {
                edges {
                    node {
                        id
                        name
                        services {
                            edges {
                                node {
                                    id
                                    name
                                    icon
                                }
                            }
                        }
                        environments {
                            edges {
                                node {
                                    id
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }
        """

        logger.info("Fetching all projects...")
        let data: ProjectsWithDetailsQueryData = try await performQuery(query: query, token: token)
        logger.info("Got \(data.projects.edges.count) projects")

        var projects: [RailwayProject] = []
        var allRequests: [DeploymentRequest] = []

        for (pIdx, edge) in data.projects.edges.enumerated() {
            let node = edge.node
            let environments = node.environments.edges.map {
                RailwayEnvironment(id: $0.node.id, name: $0.node.name)
            }
            let productionEnvId = environments.first(where: { $0.name.lowercased() == "production" })?.id
                ?? environments.first?.id

            var services: [RailwayService] = []
            for serviceEdge in node.services.edges {
                let sIdx = services.count
                let serviceNode = serviceEdge.node
                services.append(RailwayService(
                    id: serviceNode.id,
                    name: serviceNode.name,
                    icon: serviceNode.icon,
                    latestDeployment: nil
                ))
                if let envId = productionEnvId {
                    allRequests.append(DeploymentRequest(
                        projectIndex: pIdx,
                        serviceIndex: sIdx,
                        serviceId: serviceNode.id,
                        environmentId: envId
                    ))
                }
            }

            projects.append(RailwayProject(
                id: node.id,
                name: node.name,
                services: services,
                environments: environments
            ))
        }

        // Batch-fetch deployments using GraphQL aliases
        logger.info("Fetching deployments for \(allRequests.count) services in batches of \(self.deploymentBatchSize)")
        for chunk in allRequests.chunked(into: deploymentBatchSize) {
            let deployments = try await fetchDeploymentsBatched(requests: chunk, token: token)

            for (req, deployment) in zip(chunk, deployments) {
                if let deployment {
                    projects[req.projectIndex].services[req.serviceIndex] = RailwayService(
                        id: projects[req.projectIndex].services[req.serviceIndex].id,
                        name: projects[req.projectIndex].services[req.serviceIndex].name,
                        icon: projects[req.projectIndex].services[req.serviceIndex].icon,
                        latestDeployment: deployment
                    )
                }
            }
        }

        logger.info("Done. Loaded \(projects.count) projects")
        return projects
    }

    /// Fetch multiple deployments in a single GraphQL request using aliases
    private func fetchDeploymentsBatched(
        requests: [DeploymentRequest],
        token: String
    ) async throws -> [RailwayDeployment?] {
        guard !requests.isEmpty else { return [] }

        // Build a single query with aliases: d0, d1, d2, ...
        var queryFields: [String] = []
        for (i, req) in requests.enumerated() {
            queryFields.append("""
                d\(i): deployments(
                    first: 1
                    input: {
                        serviceId: "\(req.serviceId)"
                        environmentId: "\(req.environmentId)"
                    }
                ) {
                    edges {
                        node {
                            id
                            status
                            createdAt
                        }
                    }
                }
            """)
        }

        let query = "query {\n\(queryFields.joined(separator: "\n"))\n}"

        logger.debug("Batched deployment query for \(requests.count) services")

        let data: [String: DeploymentConnection] = try await performQuery(query: query, token: token)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var results: [RailwayDeployment?] = []
        for i in 0..<requests.count {
            if let connection = data["d\(i)"],
               let node = connection.edges.first?.node {
                results.append(RailwayDeployment(
                    id: node.id,
                    status: DeploymentStatus(rawValue: node.status) ?? .unknown,
                    createdAt: dateFormatter.date(from: node.createdAt) ?? Date()
                ))
            } else {
                results.append(nil)
            }
        }

        return results
    }

    // MARK: - Network layer with retry

    private func performQuery<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil,
        token: String
    ) async throws -> T {
        var body: [String: Any] = ["query": query]
        if let variables {
            body["variables"] = variables
        }

        let requestBody = try JSONSerialization.data(withJSONObject: body)

        // Proactive wait: if we've exhausted our budget, sleep until the window resets
        let waitTime = await rateLimitTracker.secondsUntilReady()
        if waitTime > 0 {
            logger.info("Rate limit budget exhausted – waiting \(waitTime, privacy: .public)s until reset")
            try await Task.sleep(for: .seconds(waitTime))
        }

        for attempt in 0..<maxRetries {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = requestBody

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RailwayAPIError.invalidResponse
            }

            // Always read rate-limit headers so we can adapt proactively
            await rateLimitTracker.update(from: httpResponse)

            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? Double(attempt + 1) * 2
                logger.warning("Rate limited (429). Retry after \(retryAfter)s (attempt \(attempt + 1)/\(self.maxRetries))")
                try await Task.sleep(for: .seconds(retryAfter))
                continue
            }

            guard httpResponse.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
                logger.error("HTTP \(httpResponse.statusCode): \(bodyStr)")
                throw RailwayAPIError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)

            if let errors = graphQLResponse.errors, !errors.isEmpty {
                logger.error("GraphQL errors: \(errors.map(\.message).joined(separator: ", "))")
                throw RailwayAPIError.graphQL(errors.map(\.message))
            }

            guard let resultData = graphQLResponse.data else {
                throw RailwayAPIError.noData
            }

            return resultData
        }

        logger.error("Max retries exhausted")
        throw RailwayAPIError.rateLimited
    }
}

// MARK: - Errors

enum RailwayAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case graphQL([String])
    case noData
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Railway API"
        case .httpError(let code):
            "Railway API returned HTTP \(code)"
        case .graphQL(let messages):
            "Railway API error: \(messages.joined(separator: ", "))"
        case .noData:
            "No data returned from Railway API"
        case .rateLimited:
            "Railway API rate limit exceeded. Try again shortly."
        }
    }
}

// MARK: - Request types

private struct DeploymentRequest {
    let projectIndex: Int
    let serviceIndex: Int
    let serviceId: String
    let environmentId: String
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Batched deployment response

struct DeploymentConnection: Decodable {
    let edges: [DeploymentEdge]

    struct DeploymentEdge: Decodable {
        let node: DeploymentNode

        struct DeploymentNode: Decodable {
            let id: String
            let status: String
            let createdAt: String
        }
    }
}
