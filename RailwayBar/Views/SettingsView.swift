import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenInput = ""
    @State private var showToken = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if showToken {
                        TextField("Railway API Token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Railway API Token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Button("Save Token") {
                    appState.apiToken = tokenInput
                    appState.startPolling()
                }
                .disabled(tokenInput.isEmpty)

                Text("Get your token from [Railway Account Settings](https://railway.app/account/tokens)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Railway API")
            }

            Section {
                LabeledContent("Projects", value: "\(appState.projects.count)")
                let serviceCount = appState.projects.reduce(0) { $0 + $1.services.count }
                LabeledContent("Services", value: "\(serviceCount)")
                if let error = appState.error {
                    LabeledContent("Status") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                } else {
                    LabeledContent("Status", value: appState.isConfigured ? "Connected" : "Not configured")
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
        .onAppear {
            tokenInput = appState.apiToken
        }
    }
}
