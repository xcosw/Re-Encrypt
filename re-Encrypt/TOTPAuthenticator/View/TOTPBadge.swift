import SwiftUI

// MARK: - TOTP Badge (Shows "2FA" indicator)

/// Small badge to show that an entry has 2FA enabled
/// Usage: TOTPBadge().environmentObject(theme)
struct TOTPBadge: View {
    @EnvironmentObject private var theme: ThemeManager
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "number.square.fill")
                .font(.caption2)
            Text("2FA")
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(theme.badgeBackground.gradient)
        .cornerRadius(6)
    }
}




// MARK: - Alternative Badge Styles

/// Minimal dot indicator
struct TOTPDotBadge: View {
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
    }
}

/// Icon-only badge
struct TOTPIconBadge: View {
    @EnvironmentObject private var theme: ThemeManager
    
    var body: some View {
        Image(systemName: "number.circle.fill")
            .font(.caption)
            .foregroundColor(.green)
    }
}



// MARK: - TOTP Badge Components


/// Shield badge with checkmark
/// Security-focused design
/// Usage: TOTPShieldBadge()
struct TOTPShieldBadge: View {
    var body: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.caption)
            .foregroundColor(.green)
    }
}

/// Compact text-only badge
/// Minimal design, just "2FA" text
/// Usage: TOTPTextBadge().environmentObject(theme)
struct TOTPTextBadge: View {
    @EnvironmentObject private var theme: ThemeManager
    
    var body: some View {
        Text("2FA")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.green))
    }
}

// MARK: - Usage Examples in Different Contexts

@available(macOS 15.0, *)
struct BadgeUsageExamples: View {
    @EnvironmentObject private var theme: ThemeManager
    let entry: PasswordEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // EXAMPLE 1: In password list row header
            HStack {
                Text(entry.serviceName ?? "Service")
                    .font(.headline)
                
                if entry.hasTwoFactor {
                    TOTPBadge()
                        .environmentObject(theme)
                }
            }
            
            // EXAMPLE 2: As overlay on icon
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 44, height: 44)
                
                if entry.hasTwoFactor {
                    TOTPDotBadge()
                        .offset(x: 4, y: -4)
                }
            }
            
            // EXAMPLE 3: In metadata section
            HStack(spacing: 8) {
                if let category = entry.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.gray.opacity(0.2)))
                }
                
                if entry.hasTwoFactor {
                    TOTPTextBadge()
                        .environmentObject(theme)
                }
            }
            
            // EXAMPLE 4: With custom styling
            if entry.hasTwoFactor {
                HStack(spacing: 4) {
                    TOTPShieldBadge()
                    Text("Protected")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // EXAMPLE 5: In search results
            HStack {
                Text(entry.serviceName ?? "")
                Spacer()
                if entry.hasTwoFactor {
                    TOTPIconBadge()
                        .environmentObject(theme)
                }
            }
        }
    }
}

// MARK: - Badge in List Rows

/// Example row with badge
@available(macOS 15.0, *)
struct PasswordRowWithBadge: View {
    let entry: PasswordEntry
    @EnvironmentObject private var theme: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(theme.adaptiveTileBackground)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(entry.serviceName?.prefix(1).uppercased() ?? "?")
                        .font(.headline)
                )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.serviceName ?? "Unknown")
                        .font(.subheadline.weight(.medium))
                    
                    // Badge here!
                    if entry.hasTwoFactor {
                        TOTPBadge()
                            .environmentObject(theme)
                    }
                }
                
                if let username = entry.username {
                    Text(username)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
/*
#if DEBUG
struct TOTPBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // All badge styles
            HStack(spacing: 12) {
                TOTPBadge()
                TOTPDotBadge()
                TOTPIconBadge()
                TOTPShieldBadge()
                TOTPTextBadge()
            }
            
            // In context
            HStack {
                Text("Gmail")
                    .font(.headline)
                TOTPBadge()
            }
            
            HStack {
                Text("GitHub")
                    .font(.headline)
                TOTPIconBadge()
            }
        }
        .padding()
        .environmentObject(ThemeManager())
    }
}


#endif
 */
