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

    /// Merge a resolved schema into the user's existing toggle list.
    ///
    /// Rules:
    /// - Identifiers in `resolved` but not in `currentToggles` → added with `true`
    /// - Identifiers in `currentToggles` that came from a previous remote schema
    ///   but are no longer in `resolved` or `defaultIdentifiers` → removed
    /// - Existing toggle values are **never** changed
    ///
    /// Returns the updated toggles and whether anything changed.
    public static func mergeIntoToggles(
        resolvedSchema: ResolvedSchema,
        currentToggles: [String: Bool],
        defaultIdentifiers: Set<String>,
        previousRemoteIdentifiers: Set<String>
    ) -> (toggles: [String: Bool], newRemoteIds: Set<String>, didChange: Bool) {
        var toggles = currentToggles
        var didChange = false

        let resolvedIds = resolvedSchema.resolvedIdentifiers

        // Add new identifiers from the resolved schema (default on)
        for id in resolvedIds {
            if toggles[id] == nil {
                toggles[id] = true
                didChange = true
            }
        }

        // Remove identifiers that were previously added by a remote schema
        // but are no longer in the resolved schema or the app defaults
        for id in previousRemoteIdentifiers {
            if !resolvedIds.contains(id) && !defaultIdentifiers.contains(id) {
                if toggles.removeValue(forKey: id) != nil {
                    didChange = true
                }
            }
        }

        let newRemoteIds = resolvedIds.subtracting(defaultIdentifiers)
        return (toggles, newRemoteIds, didChange)
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
