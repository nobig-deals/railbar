import Foundation

struct RailwayAPIService {
    private let endpoint = URL(string: "https://backboard.railway.app/graphql/v2")!

    func fetchProjects(token: String) async throws -> [RailwayProject] {
        let query = """
        query {
            me {
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
        }
        """

        let data: ProjectsQueryData = try await performQuery(query: query, token: token)
        var projects: [RailwayProject] = []

        for edge in data.me.projects.edges {
            let node = edge.node

            // Find production environment (or first available)
            let environments = node.environments.edges.map {
                RailwayEnvironment(id: $0.node.id, name: $0.node.name)
            }
            let productionEnvId = environments.first(where: { $0.name.lowercased() == "production" })?.id
                ?? environments.first?.id

            // Fetch latest deployment for each service
            var services: [RailwayService] = []
            for serviceEdge in node.services.edges {
                let serviceNode = serviceEdge.node
                let deployment: RailwayDeployment? = if let envId = productionEnvId {
                    try? await fetchLatestDeployment(
                        serviceId: serviceNode.id,
                        environmentId: envId,
                        token: token
                    )
                } else {
                    nil
                }

                services.append(RailwayService(
                    id: serviceNode.id,
                    name: serviceNode.name,
                    icon: serviceNode.icon,
                    latestDeployment: deployment
                ))
            }

            projects.append(RailwayProject(
                id: node.id,
                name: node.name,
                services: services,
                environments: environments
            ))
        }

        return projects
    }

    private func fetchLatestDeployment(
        serviceId: String,
        environmentId: String,
        token: String
    ) async throws -> RailwayDeployment? {
        let query = """
        query($serviceId: String!, $environmentId: String!) {
            deployments(
                first: 1
                input: {
                    serviceId: $serviceId
                    environmentId: $environmentId
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
        }
        """

        let variables: [String: Any] = [
            "serviceId": serviceId,
            "environmentId": environmentId,
        ]

        let data: DeploymentsQueryData = try await performQuery(
            query: query,
            variables: variables,
            token: token
        )

        guard let node = data.deployments.edges.first?.node else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return RailwayDeployment(
            id: node.id,
            status: DeploymentStatus(rawValue: node.status) ?? .unknown,
            createdAt: dateFormatter.date(from: node.createdAt) ?? Date()
        )
    }

    private func performQuery<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil,
        token: String
    ) async throws -> T {
        var body: [String: Any] = ["query": query]
        if let variables {
            body["variables"] = variables
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RailwayAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw RailwayAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)

        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw RailwayAPIError.graphQL(errors.map(\.message))
        }

        guard let resultData = graphQLResponse.data else {
            throw RailwayAPIError.noData
        }

        return resultData
    }
}

enum RailwayAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case graphQL([String])
    case noData

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
        }
    }
}
