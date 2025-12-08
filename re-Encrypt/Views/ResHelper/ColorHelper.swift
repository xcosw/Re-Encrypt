//
//  ColorHelper.swift
//  re-Encrypt
//
//  Created by xcosw.dev on 3.12.2025.
//

import SwiftUI

let brandColors: [String: Color] = [
    // Core Tech Giants
    "Google": Color(red: 66/255, green: 133/255, blue: 244/255),
    "Gmail": Color(red: 234/255, green: 67/255, blue: 53/255),
    "Facebook": Color(red: 24/255, green: 119/255, blue: 242/255),
    "Apple": Color(red: 0/255, green: 0/255, blue: 0/255),
    "GitHub": Color(red: 36/255, green: 41/255, blue: 47/255),
    "Twitter": Color(red: 29/255, green: 161/255, blue: 242/255),
    "Instagram": Color(red: 131/255, green: 58/255, blue: 180/255),
    "LinkedIn": Color(red: 10/255, green: 102/255, blue: 194/255),
    "Slack": Color(red: 74/255, green: 21/255, blue: 75/255),
    "Reddit": Color(red: 255/255, green: 69/255, blue: 0/255),
    "Dropbox": Color(red: 0/255, green: 97/255, blue: 255/255),
    "Microsoft": Color(red: 242/255, green: 80/255, blue: 34/255),
    "Zoom": Color(red: 0/255, green: 112/255, blue: 255/255),
    "Amazon": Color(red: 255/255, green: 153/255, blue: 0/255),
    "Netflix": Color(red: 229/255, green: 9/255, blue: 20/255),
    "Spotify": Color(red: 30/255, green: 215/255, blue: 96/255),
    "Pinterest": Color(red: 189/255, green: 8/255, blue: 28/255),
    "Trello": Color(red: 0/255, green: 121/255, blue: 191/255),
    "Asana": Color(red: 246/255, green: 114/255, blue: 95/255),
    "Yahoo": Color(red: 67/255, green: 2/255, blue: 151/255),
    "ProtonMail": Color(red: 88/255, green: 75/255, blue: 141/255),
    "Discord": Color(red: 88/255, green: 101/255, blue: 242/255),
    "TikTok": Color(red: 0/255, green: 242/255, blue: 234/255),
    "WhatsApp": Color(red: 37/255, green: 211/255, blue: 102/255),
    "Snapchat": Color(red: 255/255, green: 252/255, blue: 0/255),
    "Figma": Color(red: 242/255, green: 78/255, blue: 30/255),
    "Notion": Color(red: 0/255, green: 0/255, blue: 0/255),
    "Bitbucket": Color(red: 38/255, green: 132/255, blue: 255/255),
    "Medium": Color(red: 0/255, green: 0/255, blue: 0/255),
    "StackOverflow": Color(red: 244/255, green: 128/255, blue: 36/255),
    "WordPress": Color(red: 33/255, green: 117/255, blue: 155/255),
    "Salesforce": Color(red: 0/255, green: 161/255, blue: 224/255),
    "PayPal": Color(red: 0/255, green: 48/255, blue: 135/255),
    "Venmo": Color(red: 10/255, green: 132/255, blue: 255/255),
    "Square": Color(red: 0/255, green: 0/255, blue: 0/255),
    "Stripe": Color(red: 99/255, green: 91/255, blue: 255/255),
    "Shopify": Color(red: 0/255, green: 128/255, blue: 96/255),
    "Evernote": Color(red: 30/255, green: 185/255, blue: 95/255),
    "OneDrive": Color(red: 0/255, green: 114/255, blue: 198/255),
    "Google Drive": Color(red: 60/255, green: 186/255, blue: 84/255),
    "Microsoft Teams": Color(red: 104/255, green: 33/255, blue: 122/255),
    "YouTube": Color(red: 255/255, green: 0/255, blue: 0/255),
    "Twitch": Color(red: 145/255, green: 70/255, blue: 255/255),
    "SoundCloud": Color(red: 255/255, green: 85/255, blue: 0/255),
    "Telegram": Color(red: 0/255, green: 136/255, blue: 204/255),
    "Signal": Color(red: 66/255, green: 133/255, blue: 244/255),

    // Security / VPN / Privacy
    "ProtonVPN": Color(red: 0/255, green: 128/255, blue: 255/255),
    "NordVPN": Color(red: 0/255, green: 82/255, blue: 204/255),
    "ExpressVPN": Color(red: 207/255, green: 15/255, blue: 28/255),
    "DuckDuckGo": Color(red: 255/255, green: 109/255, blue: 33/255),
    "1Password": Color(red: 0/255, green: 122/255, blue: 255/255),
    "LastPass": Color(red: 204/255, green: 0/255, blue: 0/255),
    "Bitwarden": Color(red: 0/255, green: 82/255, blue: 204/255),
    "Keeper": Color(red: 255/255, green: 187/255, blue: 0/255),
    "ProtonCalendar": Color(red: 100/255, green: 70/255, blue: 160/255),
    "ProtonContacts": Color(red: 92/255, green: 70/255, blue: 150/255),
    "Proton Wiki": Color(red: 82/255, green: 65/255, blue: 135/255),

    // Creative / Design
    "Canva": Color(red: 0/255, green: 171/255, blue: 165/255),
    "Behance": Color(red: 19/255, green: 20/255, blue: 24/255),
    "Dribbble": Color(red: 234/255, green: 76/255, blue: 137/255),
    "OpenAI": Color(red: 26/255, green: 26/255, blue: 26/255),
    "ChatGPT": Color(red: 0/255, green: 180/255, blue: 150/255),
    "Adobe": Color(red: 255/255, green: 0/255, blue: 0/255),

    // Productivity / Scheduling
    "Calendly": Color(red: 0/255, green: 145/255, blue: 234/255),
    "ZoomInfo": Color(red: 214/255, green: 0/255, blue: 28/255),
    "Fiverr": Color(red: 0/255, green: 184/255, blue: 122/255),
    "Upwork": Color(red: 91/255, green: 189/255, blue: 114/255),
    "Coursera": Color(red: 0/255, green: 73/255, blue: 164/255),
    "Udemy": Color(red: 255/255, green: 0/255, blue: 85/255),
    "Khan Academy": Color(red: 22/255, green: 121/255, blue: 107/255),
    "Duolingo": Color(red: 120/255, green: 200/255, blue: 80/255),

    // Streaming / Entertainment
    "Disney+": Color(red: 0/255, green: 66/255, blue: 150/255),
    "HBO Max": Color(red: 95/255, green: 0/255, blue: 157/255),
    "Hulu": Color(red: 28/255, green: 231/255, blue: 131/255),
    "Vimeo": Color(red: 26/255, green: 183/255, blue: 234/255),
    "Soundtrap": Color(red: 103/255, green: 58/255, blue: 183/255),
    "TripAdvisor": Color(red: 0/255, green: 175/255, blue: 137/255),
    "Airbnb": Color(red: 255/255, green: 90/255, blue: 95/255),
    "Booking.com": Color(red: 0/255, green: 53/255, blue: 128/255),
    "Expedia": Color(red: 255/255, green: 216/255, blue: 0/255),

    // Education / AI Tools
    "Udacity": Color(red: 1/255, green: 180/255, blue: 228/255),
    "DataCamp": Color(red: 0/255, green: 207/255, blue: 158/255),
    "DeepL": Color(red: 0/255, green: 70/255, blue: 130/255),
    "Grammarly": Color(red: 0/255, green: 179/255, blue: 152/255),
    "Reverso": Color(red: 0/255, green: 114/255, blue: 206/255),
    "Wordtune": Color(red: 156/255, green: 39/255, blue: 176/255),
    "Copy.ai": Color(red: 94/255, green: 117/255, blue: 255/255),
    "Jasper": Color(red: 130/255, green: 60/255, blue: 255/255),

    // Focus / Wellbeing
    "Calm": Color(red: 43/255, green: 118/255, blue: 210/255),
    "Headspace": Color(red: 255/255, green: 112/255, blue: 40/255),
    "Focus@Will": Color(red: 237/255, green: 85/255, blue: 59/255),
    "MyNoise": Color(red: 105/255, green: 105/255, blue: 105/255)
]
