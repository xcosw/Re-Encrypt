import SwiftUI

@available(macOS 15.0, *)
struct SecurityStatusPopoverButton: View {
    @State private var showPopover = false
    
    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                Text("Security Status")
            }
            .padding(6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            SecurityStatusView()
                .frame(width: 400, height: 600)
        }
    }
}

@available(macOS 15.0, *)
struct SecurityStatusView: View {
    @State private var status: SecurityStatus?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let status = status {
                // Header
                HStack {
                    Image(systemName: securityIcon(for: status.securityLevel))
                        .font(.system(size: 40))
                        .foregroundColor(securityColor(for: status.securityLevel))
                    
                    VStack(alignment: .leading) {
                        Text("Security Status")
                            .font(.title2.bold())
                        Text(status.statusDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Authentication
                GroupBox(label: Label("Authentication", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(
                            label: "Session Status",
                            value: status.hasKey ? (status.sessionExpired ? "Expired" : "Active") : "Locked",
                            color: status.hasKey && !status.sessionExpired ? .green : .red
                        )
                        StatusRow(
                            label: "Failed Attempts",
                            value: "\(status.failedAttempts)/3 (Total: \(status.totalFailedAttempts)/10)",
                            color: status.failedAttempts == 0 ? .green : (status.failedAttempts >= 2 ? .red : .orange)
                        )
                        if status.backoffTimeRemaining > 0 {
                            StatusRow(
                                label: "Backoff Period",
                                value: "\(Int(status.backoffTimeRemaining))s remaining",
                                color: .orange
                            )
                        }
                        StatusRow(
                            label: "Rate Limit",
                            value: "\(status.remainingRateLimit)/3 attempts available",
                            color: status.remainingRateLimit > 1 ? .green : .orange
                        )
                    }
                }
                
                // Protection
                GroupBox(label: Label("Protection", systemImage: "shield.checkered")) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(
                            label: "Recovery Codes",
                            value: status.hasRecoveryCodes ? "\(status.remainingRecoveryCodes)/10 available" : "Not set up",
                            color: status.hasRecoveryCodes ? .green : .orange
                        )
                        StatusRow(
                            label: "Integrity Check",
                            value: status.integrityVerified ? "Verified" : "Failed",
                            color: status.integrityVerified ? .green : .red
                        )
                        if let lastCheck = status.lastIntegrityCheck {
                            Text("Last check: \(lastCheck.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        StatusRow(
                            label: "Memory Protection",
                            value: status.memoryProtected ? "Enabled" : "Disabled",
                            color: status.memoryProtected ? .green : .gray
                        )
                        StatusRow(
                            label: "Anti-Debug",
                            value: status.antiDebugActive ? "Enabled" : "Disabled",
                            color: status.antiDebugActive ? .green : .gray
                        )
                    }
                }
                
                // Dead Man's Switch
                if status.deadManSwitchActive, let days = status.daysUntilAutoWipe {
                    GroupBox(label: Label("Dead Man's Switch", systemImage: "timer")) {
                        StatusRow(
                            label: "Auto-wipe in",
                            value: "\(days) days",
                            color: days > 30 ? .green : (days > 7 ? .orange : .red)
                        )
                    }
                }
                
                // Session Info
                GroupBox(label: Label("Session Info", systemImage: "clock")) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(
                            label: "Last Activity",
                            value: status.lastActivity.formatted(date: .abbreviated, time: .shortened),
                            color: .blue
                        )
                        StatusRow(
                            label: "Key Version",
                            value: "v\(status.keyVersion)",
                            color: .blue
                        )
                    }
                }
                
                Spacer()
                
                // Actions
                HStack {
                    Button(action: refreshStatus) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    if status.hasRecoveryCodes && status.remainingRecoveryCodes < 5 {
                        Button(action: regenerateRecoveryCodes) {
                            Label("Regenerate Codes", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button(action: exportAuditLog) {
                        Label("Export Logs", systemImage: "square.and.arrow.up")
                    }
                }
            } else {
                ProgressView("Loading security status...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear { refreshStatus() }
    }
    
    private func refreshStatus() {
        Task {
            status = await CryptoHelper.getSecurityStatus()
        }
    }
    
    private func regenerateRecoveryCodes() {
        // Your implementation
    }
    
    private func exportAuditLog() {
        Task {
            let logs = await AuditLogger.shared.exportLogs()
            print(logs)
        }
    }
    
    private func securityIcon(for level: SecurityStatus.SecurityLevel) -> String {
        switch level {
        case .optimal: return "checkmark.shield.fill"
        case .moderate: return "shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .critical: return "xmark.shield.fill"
        }
    }
    
    private func securityColor(for level: SecurityStatus.SecurityLevel) -> Color {
        switch level {
        case .optimal: return .green
        case .moderate: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold().foregroundColor(color)
        }
        .font(.body)
    }
}
