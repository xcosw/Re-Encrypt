import SwiftUI

struct MasterPasswordPrompt: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    var onSubmit: (Data) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter Master Password")
                        .font(.title3.weight(.semibold))
                    Text("To change secure storage settings, please confirm using your master password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.bottom, 16)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Divider()

            // --- Input Field ---
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Master Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 280)
                    .padding(.top, 10)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            // --- Footer Buttons ---
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    password.removeAll(keepingCapacity: false)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    submit()
                } label: {
                    Label("Confirm", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .shadow(radius: 12, y: 4)
        )
        .frame(width: 420)
        .padding()
    }

    private func submit() {
        let data = Data(password.utf8)
        password.removeAll(keepingCapacity: false)
        onSubmit(data)
        dismiss()
    }
}
