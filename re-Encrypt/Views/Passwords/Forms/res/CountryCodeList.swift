import Foundation

struct CountryCode: Identifiable, Hashable, Codable {
    let code: String   // e.g. "+1"
    let name: String   // e.g. "United States"
    let flag: String   // e.g. "🇺🇸"
    let uuid: UUID     // Unique identifier, not part of JSON
    
    var id: String { "\(code)|\(name)" }
    
    // MARK: - Initializer
    init(code: String, name: String, flag: String, uuid: UUID = UUID()) {
        self.code = code
        self.name = name
        self.flag = flag
        self.uuid = uuid
    }
    
    // MARK: - Codable support
    enum CodingKeys: String, CodingKey {
        case code, name, flag
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(String.self, forKey: .code)
        self.name = try container.decode(String.self, forKey: .name)
        self.flag = try container.decode(String.self, forKey: .flag)
        self.uuid = UUID()
    }
}

struct CountryData {
    static func loadCountryCodes() -> [CountryCode] {
        guard let url = Bundle.main.url(forResource: "CountryCodes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            let decoder = JSONDecoder()
            let countries = try decoder.decode([CountryCode].self, from: data)
            return countries
        } catch {
            return []
        }
    }
}
