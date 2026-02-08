import Foundation

// MARK: - Domain Models

struct RailwayProject: Identifiable {
    let id: String
    let name: String
    let services: [RailwayService]
    let environments: [RailwayEnvironment]
}

struct RailwayService: Identifiable {
    let id: String
    let name: String
    let icon: String?
    let latestDeployment: RailwayDeployment?
}

struct RailwayDeployment: Identifiable {
    let id: String
    let status: DeploymentStatus
    let createdAt: Date
}

struct RailwayEnvironment: Identifiable {
    let id: String
    let name: String
}

// MARK: - Deployment Status

enum DeploymentStatus: String, CaseIterable {
    case building = "BUILDING"
    case deploying = "DEPLOYING"
    case initializing = "INITIALIZING"
    case success = "SUCCESS"
    case failed = "FAILED"
    case crashed = "CRASHED"
    case removed = "REMOVED"
    case sleeping = "SLEEPING"
    case unknown

    var displayName: String {
        switch self {
        case .building: "Building"
        case .deploying: "Deploying"
        case .initializing: "Initializing"
        case .success: "Running"
        case .failed: "Failed"
        case .crashed: "Crashed"
        case .removed: "Removed"
        case .sleeping: "Sleeping"
        case .unknown: "Unknown"
        }
    }

    var iconName: String {
        switch self {
        case .building, .deploying, .initializing: "arrow.trianglehead.2.counterclockwise"
        case .success: "checkmark.circle.fill"
        case .failed, .crashed: "xmark.circle.fill"
        case .removed: "minus.circle"
        case .sleeping: "moon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .building, .deploying, .initializing: "orange"
        case .success: "green"
        case .failed, .crashed: "red"
        case .removed: "gray"
        case .sleeping: "purple"
        case .unknown: "gray"
        }
    }
}

// MARK: - GraphQL Response Types

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}

struct ProjectsQueryData: Decodable {
    let me: MeData

    struct MeData: Decodable {
        let projects: ProjectConnection

        struct ProjectConnection: Decodable {
            let edges: [ProjectEdge]

            struct ProjectEdge: Decodable {
                let node: ProjectNode

                struct ProjectNode: Decodable {
                    let id: String
                    let name: String
                    let services: ServiceConnection
                    let environments: EnvironmentConnection

                    struct ServiceConnection: Decodable {
                        let edges: [ServiceEdge]

                        struct ServiceEdge: Decodable {
                            let node: ServiceNode

                            struct ServiceNode: Decodable {
                                let id: String
                                let name: String
                                let icon: String?
                            }
                        }
                    }

                    struct EnvironmentConnection: Decodable {
                        let edges: [EnvironmentEdge]

                        struct EnvironmentEdge: Decodable {
                            let node: EnvironmentNode

                            struct EnvironmentNode: Decodable {
                                let id: String
                                let name: String
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DeploymentsQueryData: Decodable {
    let deployments: DeploymentConnection

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
}
