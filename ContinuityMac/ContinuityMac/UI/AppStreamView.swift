import SwiftUI

/// Full app picker for App Streaming.
/// Shows all installed apps on the phone, searchable.
struct AppStreamView: View {
    @EnvironmentObject var mirroring: MirroringSessionManager
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredApps: [AndroidApp] {
        if searchText.isEmpty { return mirroring.installedApps }
        return mirroring.installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.packageName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("App Streaming")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading apps from phone...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mirroring.installedApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "iphone.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No apps found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // App list
                List(filteredApps) { app in
                    Button {
                        mirroring.streamApp(package: app.packageName)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            // App icon placeholder (colored by first letter)
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorForApp(app.packageName))
                                    .frame(width: 36, height: 36)
                                Text(String(app.displayName.prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(app.packageName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            // Active session banner
            if mirroring.isAppStreamActive {
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("App streaming active")
                        .font(.caption)
                    Spacer()
                    Button("Stop") {
                        mirroring.terminateMirroringSession()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
            }
        }
        .frame(width: 380, height: 520)
        .onAppear {
            if mirroring.installedApps.isEmpty {
                mirroring.fetchInstalledApps()
                // Give it time to load then hide spinner
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    isLoading = false
                }
            } else {
                isLoading = false
            }
        }
        .onChange(of: mirroring.installedApps.count) { count in
            if count > 0 { isLoading = false }
        }
    }

    // Deterministic color from package name
    private func colorForApp(_ pkg: String) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        let index = abs(pkg.hashValue) % colors.count
        return colors[index]
    }
}
