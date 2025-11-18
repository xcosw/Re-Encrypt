import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
                .padding(.top, 20)
            
            // App Info
            Text("Secure Password Manager")
                .font(.title2.bold())
            
            Text("Version \(appVersion())")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal)
            
            // Description
            Text("Secure Password Manager keeps your credentials safe using end-to-end AES-256 encryption. "
                 + "Built for performance, privacy, and a beautiful SwiftUI experience.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Links
            HStack(spacing: 30) {
                Link(destination: URL(string: "https://xcosw.com")!) {
                    Label("Website", systemImage: "globe")
                }
                Link(destination: URL(string: "mailto:support@xcosw.com")!) {
                    Label("Support", systemImage: "envelope")
                }
                Link(destination: URL(string: "https://github.com/xcosw")!) {
                    Label("GitHub", systemImage: "chevron.left.slash.chevron.right")
                }
            }
            .padding(.top, 8)
            .foregroundColor(.accentColor)
            
            Spacer()
            
            Text("© \(Calendar.current.component(.year, from: Date())) Secure Password Manager. All rights reserved.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
        }
        .frame(width: 420, height: 420)
        .padding()
    }

    private func appVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/*
 Text("Credits")
     .font(.headline)
     .padding(.top, 12)
 Text("Developed by KeyKo\nUI design by SecurePass Team")
     .font(.footnote)
     .multilineTextAlignment(.center)

 */
