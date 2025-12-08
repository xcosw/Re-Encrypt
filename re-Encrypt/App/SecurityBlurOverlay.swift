//
//  SecurityBlurOverlay.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 3.12.2025.
//

import SwiftUI

struct SecurityBlurOverlay: View {
    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.85))
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: UUID())
    }
}


struct SecurityBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading) {
                Text("Screenshot Detected")
                    .font(.headline)
                Text("Sensitive information may have been captured.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 6)
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
