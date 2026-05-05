import Testing
import Foundation
@testable import arachnode

@Suite("CategoryKey")
@MainActor
struct CategoryKeyTests {
    @Test("from empty list → uncategorized")
    func fromEmpty() {
        #expect(CategoryKey.from(categoryIDs: []) == .uncategorized)
    }

    @Test("from single id → single")
    func fromSingle() {
        let id = UUID()
        #expect(CategoryKey.from(categoryIDs: [id]) == .single(id))
    }

    @Test("from multiple ids → combination")
    func fromMultiple() {
        let a = UUID(), b = UUID()
        let key = CategoryKey.from(categoryIDs: [a, b])
        #expect(key == .combination([a, b]))
    }

    @Test("combination is set-equal regardless of order")
    func combinationOrder() {
        let a = UUID(), b = UUID()
        #expect(CategoryKey.from(categoryIDs: [a, b]) == CategoryKey.from(categoryIDs: [b, a]))
    }

    @Test("categoryIDs returns the underlying set")
    func categoryIDsAccessor() {
        let a = UUID(), b = UUID()
        #expect(CategoryKey.uncategorized.categoryIDs.isEmpty)
        #expect(CategoryKey.single(a).categoryIDs == [a])
        #expect(CategoryKey.combination([a, b]).categoryIDs == [a, b])
    }

    @Test("hashable: equal keys land in the same dict bucket")
    func hashable() {
        let a = UUID(), b = UUID()
        var map: [CategoryKey: Int] = [:]
        map[.combination([a, b])] = 1
        // Same set, different array order — must hit the same key.
        map[.combination([b, a])] = 2
        #expect(map.count == 1)
        #expect(map[.combination([a, b])] == 2)
    }
}
