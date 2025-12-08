import SwiftUI
import Foundation

enum CategoryIcons {
    // Central icon map
    private static let map: [String: String] = [
        "All": "widget.small.badge.plus",
        "WiFi": "wifi",
        "Web": "globe",
        "App": "app.fill",
        "Other": "ellipsis.circle",

        "Game": "gamecontroller.fill",
        "Games": "gamecontroller.fill",
        "Social": "person.2.fill",
        "Bank": "banknote",
        "Banking": "banknote",
        "Shopping": "bag.fill",
        "Developer": "chevron.left.forwardslash.chevron.right",
        "Develop": "chevron.left.forwardslash.chevron.right",
        "Work": "briefcase.fill",
        "Email": "envelope.fill",
        "Cloud": "icloud.fill",
        "Streaming": "play.rectangle.fill",
        "Crypto": "bitcoinsign.circle.fill",
        "Travel": "airplane",
        "Education": "book.fill",
        "Health": "heart.fill",
        "Finance": "dollarsign.circle.fill",
        "VPN": "lock.shield.fill",
        "Utilities": "wrench.and.screwdriver",
        "Photos": "photo.fill.on.rectangle.fill",
        "Notes": "note.text",
        "Music": "music.note",
        "Video": "film.fill",
        "News": "newspaper.fill",
        "Food": "fork.knife",
        "Delivery": "bicycle",
        "Transport": "tram.fill",
        "Maps": "map.fill",
        "Forum": "bubble.left.and.bubble.right.fill",
        "Security": "lock.fill",
        "ID": "person.badge.key.fill",
        "Store": "cart.fill"
    ]

    static let recommended: [String] = [
        "Wi-Fi", "Web", "App", "Social", "Game", "Bank", "Shopping", "Developer",
        "Email", "Work", "Cloud", "Streaming", "Crypto", "Travel",
        "Education", "Health", "Finance", "VPN", "Utilities", "Security", "Other"
    ]

    static var allKnown: Set<String> { Set(map.keys) }

    static func icon(for category: String) -> String {
        map[category] ?? "tag"
    }
}


/*extension CategoryIcons {
    static let defaultFolderIcons: [String: String] = [
        "Banking": "banknote.fill",
        "Email": "envelope.fill",
        "Social Media": "person.2.fill",
        "SocialMedia": "person.2.fill",
        "Wi-Fi": "wifi",
        "WiFi": "wifi",
        "Work": "briefcase.fill",
        "Shopping": "cart.fill",
        "Streaming": "play.tv.fill",
        "Gaming": "gamecontroller.fill",
        "Government": "building.columns.fill",
        "Health": "cross.case.fill",
        "Education": "graduationcap.fill",
        "Travel": "airplane",
        "Cryptocurrency": "bitcoinsign.circle.fill"
    ]
    
    static func icon(for category: String) -> String {
        let normalized = category.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        
        // Check default folder icons first
        if let icon = defaultFolderIcons[category] ?? defaultFolderIcons[normalized] {
            return icon
        }
        
        // Fallback to existing category icons
        return existingIcons[normalized] ?? "folder.fill"
    }
    
    private static let existingIcons: [String: String] = [
        "Banking": "banknote.fill",
        "Email": "envelope.fill",
        "SocialMedia": "person.2.fill",
        "Work": "briefcase.fill",
        "Shopping": "cart.fill",
        "Entertainment": "popcorn.fill",
        "Finance": "dollarsign.circle.fill",
        "Travel": "airplane",
        "Health": "heart.fill",
        "Education": "book.fill",
        "Gaming": "gamecontroller.fill",
        "Utilities": "wrench.fill",
        "Cloud": "cloud.fill",
        "Development": "chevron.left.forwardslash.chevron.right",
        "Security": "lock.shield.fill",
        "Communication": "message.fill",
        "Productivity": "checklist",
        "Other": "folder.fill"
    ]
}*/
