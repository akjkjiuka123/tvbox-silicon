import Foundation

// TVBox sources answer a category page with a `filters` object: the extra second-level choices
// ("类型", "地区", "年份", "排序") that the category supports, keyed by the category's `type_id`.
// Choosing one sends the whole selection back as the `extend` parameter. Yingxia read neither, so a
// source opened as one flat list where TVBox would show the filter strip; this file adds both.

/// One second-level filter of a category, such as 类型 with its values.
public struct CatalogFilter: Identifiable, Hashable, Sendable {
    public struct Option: Identifiable, Hashable, Sendable {
        public let name: String
        public let value: String
        public var id: String { value }
        public init(name: String, value: String) { self.name = name; self.value = value }
    }
    /// The key the choice is sent under inside `extend`.
    public let key: String
    public let name: String
    public let options: [Option]
    public var id: String { key }
    public init(key: String, name: String, options: [Option]) {
        self.key = key; self.name = name; self.options = options
    }
}

/// Every category's filters, from one home answer.
public struct CatalogFilters: Equatable, Sendable {
    public private(set) var byCategory: [String: [CatalogFilter]] = [:]
    public init() {}
    public init(value: JSONValue?) {
        guard let object = value?.object else { return }
        for (category, entry) in object {
            let filters = (entry.array ?? []).compactMap { item -> CatalogFilter? in
                guard let fields = item.object, let key = fields["key"]?.string, !key.isEmpty else { return nil }
                let name = fields["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? key
                let options = (fields["value"]?.array ?? []).compactMap { option -> CatalogFilter.Option? in
                    guard let values = option.object, let value = values["v"]?.string else { return nil }
                    let shown = values["n"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? value
                    return CatalogFilter.Option(name: shown, value: value)
                }
                guard !options.isEmpty else { return nil }
                return CatalogFilter(key: key, name: name, options: options)
            }
            if !filters.isEmpty { byCategory[category] = filters }
        }
    }

    public var isEmpty: Bool { byCategory.isEmpty }
    public func filters(for category: String) -> [CatalogFilter] { byCategory[category] ?? [] }

    /// The `extend` value a source expects for a set of choices, e.g. `{"area":"大陆","year":"2024"}`.
    /// Empty values are dropped: a source reads an absent key as "全部".
    public static func extend(_ values: [String: String]) -> String? {
        let chosen = values.filter { !$0.value.isEmpty }
        guard !chosen.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(chosen.mapValues { JSONValue.string($0) }) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
