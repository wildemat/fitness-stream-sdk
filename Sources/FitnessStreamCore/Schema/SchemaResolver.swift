import Foundation

/// Resolves an endpoint schema against the metric registry.
/// `(catalog ∪ custom registry) ∩ requested → resolved + dropped`
public enum SchemaResolver {

    /// Resolve a schema definition against the registry.
    /// Returns a `ResolvedSchema` with resolved and dropped metrics.
    public static func resolve(
        schema: SchemaDefinition,
        registry: MetricRegistry
    ) -> ResolvedSchema {
        var resolved: [ResolvedMetric] = []
        var dropped: [DroppedMetric] = []

        for request in schema.metrics {
            if let descriptor = registry.descriptor(for: request.identifier) {
                let sourceName: String
                switch descriptor.source {
                case .healthKit: sourceName = "healthkit"
                case .computed:  sourceName = "computed"
                case .location:  sourceName = "location"
                case .custom:    sourceName = "custom"
                }
                resolved.append(ResolvedMetric(
                    identifier: request.identifier,
                    source: sourceName
                ))
            } else {
                dropped.append(DroppedMetric(
                    identifier: request.identifier,
                    reason: "not_registered",
                    wasRequired: request.required ?? false
                ))
            }
        }

        return ResolvedSchema(
            schemaVersion: schema.schemaVersion,
            name: schema.name,
            resolved: resolved,
            dropped: dropped
        )
    }

    /// Create a "stream all" fallback schema from the full registry.
    public static func resolveAll(registry: MetricRegistry) -> ResolvedSchema {
        let resolved = registry.allDescriptors.map { descriptor -> ResolvedMetric in
            let sourceName: String
            switch descriptor.source {
            case .healthKit: sourceName = "healthkit"
            case .computed:  sourceName = "computed"
            case .location:  sourceName = "location"
            case .custom:    sourceName = "custom"
            }
            return ResolvedMetric(identifier: descriptor.identifier, source: sourceName)
        }
        return ResolvedSchema(
            schemaVersion: "1.0",
            name: "all",
            resolved: resolved,
            dropped: []
        )
    }
}
