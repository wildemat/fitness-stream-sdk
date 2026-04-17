import XCTest
@testable import FitnessStreamCore

final class SchemaResolverTests: XCTestCase {

    func testResolveAllRegistered() {
        let registry = MetricRegistry()
        registry.register(identifiers: ["heart_rate", "active_energy_kcal"])

        let schema = SchemaDefinition(
            name: "test",
            metrics: [
                MetricRequest(identifier: "heart_rate"),
                MetricRequest(identifier: "active_energy_kcal"),
            ]
        )

        let result = SchemaResolver.resolve(schema: schema, registry: registry)
        XCTAssertEqual(result.resolved.count, 2)
        XCTAssertTrue(result.dropped.isEmpty)
        XCTAssertTrue(result.isFullyResolved)
    }

    func testResolveDropsUnregistered() {
        let registry = MetricRegistry()
        registry.register(identifiers: ["heart_rate"])

        let schema = SchemaDefinition(
            name: "test",
            metrics: [
                MetricRequest(identifier: "heart_rate"),
                MetricRequest(identifier: "cadence", required: false),
            ]
        )

        let result = SchemaResolver.resolve(schema: schema, registry: registry)
        XCTAssertEqual(result.resolved.count, 1)
        XCTAssertEqual(result.dropped.count, 1)
        XCTAssertEqual(result.dropped.first?.identifier, "cadence")
        XCTAssertTrue(result.isFullyResolved)
    }

    func testResolveRejectsRequiredMissing() {
        let registry = MetricRegistry()
        registry.register(identifiers: ["heart_rate"])

        let schema = SchemaDefinition(
            name: "test",
            metrics: [
                MetricRequest(identifier: "heart_rate"),
                MetricRequest(identifier: "cadence", required: true),
            ]
        )

        let result = SchemaResolver.resolve(schema: schema, registry: registry)
        XCTAssertFalse(result.isFullyResolved)
    }

    func testResolveIncludesCustomMetrics() {
        let registry = MetricRegistry()
        registry.register(identifiers: ["heart_rate"])
        registry.registerCustom(identifier: "current_exercise", valueType: .string)

        let schema = SchemaDefinition(
            name: "test",
            metrics: [
                MetricRequest(identifier: "heart_rate"),
                MetricRequest(identifier: "current_exercise"),
            ]
        )

        let result = SchemaResolver.resolve(schema: schema, registry: registry)
        XCTAssertEqual(result.resolved.count, 2)
        XCTAssertTrue(result.resolved.contains(where: {
            $0.identifier == "current_exercise" && $0.source == "custom"
        }))
    }

    func testCustomMetricCannotShadowCatalog() {
        let registry = MetricRegistry()
        let success = registry.registerCustom(identifier: "heart_rate", valueType: .double)
        XCTAssertFalse(success)
    }

    func testResolveAll() {
        let registry = MetricRegistry()
        registry.register(identifiers: ["heart_rate", "active_energy_kcal", "pace_min_per_km"])
        registry.registerCustom(identifier: "mood_score", valueType: .int)

        let result = SchemaResolver.resolveAll(registry: registry)
        XCTAssertEqual(result.resolved.count, 4)
        XCTAssertTrue(result.dropped.isEmpty)
    }
}
