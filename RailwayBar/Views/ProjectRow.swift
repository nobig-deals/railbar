import SwiftUI

struct ProjectRow: View {
    let project: RailwayProject
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    projectStatusBadge
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(project.services) { service in
                        ServiceRow(service: service)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
    }

    private var projectStatusBadge: some View {
        let statuses = project.services.compactMap { $0.latestDeployment?.status }

        let worst: DeploymentStatus = if statuses.contains(where: { $0 == .crashed || $0 == .failed }) {
            .crashed
        } else if statuses.contains(where: { $0 == .building || $0 == .deploying || $0 == .initializing }) {
            .building
        } else if statuses.allSatisfy({ $0 == .success }) && !statuses.isEmpty {
            .success
        } else {
            .unknown
        }

        return Circle()
            .fill(statusColor(worst))
            .frame(width: 8, height: 8)
    }

    private func statusColor(_ status: DeploymentStatus) -> Color {
        switch status {
        case .success: .green
        case .building, .deploying, .initializing: .orange
        case .failed, .crashed: .red
        case .sleeping: .purple
        default: .gray
        }
    }
}

struct ServiceRow: View {
    let service: RailwayService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: service.latestDeployment?.status.iconName ?? "questionmark.circle")
                .font(.caption)
                .foregroundStyle(serviceColor)

            Text(service.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            if let deployment = service.latestDeployment {
                Text(deployment.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(serviceColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(serviceColor.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var serviceColor: Color {
        guard let status = service.latestDeployment?.status else { return .gray }
        switch status {
        case .success: return .green
        case .building, .deploying, .initializing: return .orange
        case .failed, .crashed: return .red
        case .sleeping: return .purple
        default: return .gray
        }
    }
}
