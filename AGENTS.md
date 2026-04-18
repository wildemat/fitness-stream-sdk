# Agent Instructions — FitnessStream SDK

This file provides context for AI coding agents working with this repository. When a user asks for help with the SDK, first determine which role they are in, then follow the corresponding guidance.

## Determine the user's role

Ask the user (or infer from context) which of the two roles they are:

1. **App Developer** — building an iOS/watchOS app that embeds this SDK to stream workout metrics to an endpoint
2. **Endpoint Vendor** — building a server or service that receives workout data from apps using this SDK

The integration steps, relevant files, and troubleshooting differ significantly between these roles. Do not mix guidance across roles unless the user is explicitly doing both.

---

## Role: App Developer

### What they're doing

Integrating the FitnessStream SDK into their iOS/watchOS app so it can stream live workout metrics (HealthKit, location, custom data) to a remote endpoint.

### Key files for this role

| File | Purpose |
|------|---------|
| `Package.swift` | Defines `FitnessStreamCore` and `FitnessStreamUI` products |
| `Sources/FitnessStreamCore/FitnessStreamEngine.swift` | Main coordinator — registration, configuration, streaming lifecycle, tick, verify connection |
| `Sources/FitnessStreamCore/Schema/StreamConfiguration.swift` | Persisted state (endpoint, toggles, frequency). Single source of truth for what the user configures. |
| `Sources/FitnessStreamCore/Catalog/MetricCatalog.swift` | All available metric identifiers, friendly names, source groups |
| `Sources/FitnessStreamCore/Catalog/MetricDescriptor.swift` | `MetricDescriptor`, `MetricSource`, `ValueType`, `Aggregation` types |
| `Sources/FitnessStreamCore/Collection/MetricCollector.swift` | Dynamic HealthKit anchored queries |
| `Sources/FitnessStreamCore/Collection/CustomMetricStore.swift` | Thread-safe store for app-pushed custom values |
| `Sources/FitnessStreamCore/Collection/MetricSnapshot.swift` | Timestamped values payload, flat JSON encoding |
| `Sources/FitnessStreamCore/Transport/StreamEndpoint.swift` | Endpoint config model (URL, API key, frequency) |
| `Sources/FitnessStreamCore/Transport/HTTPPostTransport.swift` | POST transport implementation |
| `Sources/FitnessStreamUI/StreamConfigView.swift` | Drop-in SwiftUI settings panel |

### Integration walkthrough

Guide the user through these steps in order:

1. **Install the package** via SPM. They add `FitnessStreamCore` (required) and optionally `FitnessStreamUI` to their target.

2. **Create the engine** with an `HKHealthStore` instance. Optionally pass a custom `StreamConfiguration` if they need a specific UserDefaults suite.

3. **Register catalog metrics** by passing identifier strings to `engine.register(metrics:)`. The available identifiers are in `MetricCatalog.all`. Only registered metrics can be collected and streamed.

4. **Register custom metrics** with `engine.registerCustom(identifier:valueType:)` for any app-specific data they want to stream alongside HealthKit metrics. Custom identifiers must not collide with catalog identifiers.

5. **Request HealthKit authorization**. The SDK does not do this — the app must call `healthStore.requestAuthorization(toShare:read:)`. Use `engine.requiredHealthKitReadTypes` and `engine.requiredHealthKitShareTypes` to get the exact type sets.

6. **Configure an endpoint** — either programmatically with `engine.configureSimple(endpoint:)` or through the `StreamConfigView` UI which handles everything.

7. **Start streaming** with `engine.startStreaming(workoutType:startDate:)` when a workout begins.

8. **Call `engine.tick(elapsedSeconds:)`** on a 1-second timer. The engine collects from all sources, builds a snapshot, and streams at the configured frequency. The returned `MetricSnapshot` can be used to update the app's own UI.

9. **Push custom values** during the workout with `engine.setCustomValue(_:for:)`.

10. **Stop streaming** with `engine.stopStreaming()` when the workout ends.

### Common tasks

- **Changing friendly names**: `engine.configuration.friendlyNameOverrides["identifier"] = "Display Name"`
- **Building custom settings UI**: Read/write `engine.configuration` properties directly instead of using `StreamConfigView`
- **Custom persistence suite**: `StreamConfiguration(suiteName: "group.com.app", keyPrefix: "prefix")`
- **Custom transport**: `engine.setTransport(myTransport)` where `myTransport` conforms to `StreamTransport`
- **Watch integration**: Set `engine.collector.watchProvidedMetrics` for metrics coming from the watch, and use `engine.collector.setValue(_:for:)` to inject watch-provided values

### Pitfalls to warn about

- The SDK does not own the `HKWorkoutSession`. The app creates and manages it.
- `registerCustom()` must be called before streaming starts. Registration during streaming has no effect on the current session.
- Custom identifiers that collide with catalog identifiers (e.g., `"heart_rate"`) are rejected.
- `tick()` must be called by the app on its own timer. The SDK does not create its own timer.
- The `MetricSnapshot.encodeFlatJSON()` format is backward-compatible: all values are top-level keys, not nested under a `values` object.

---

## Role: Endpoint Vendor

### What they're doing

Building a server that receives live workout metrics from apps using this SDK. They need to handle incoming POST payloads and optionally serve a schema to control which metrics get sent.

### Key files for this role

| File | Purpose |
|------|---------|
| `Tools/schema-tool.js` | CLI for generating and validating schema files |
| `Tools/catalog.json` | Machine-readable metric catalog (all identifiers, types, units) |
| `Tools/package.json` | npm package manifest for the schema tool |
| `Sources/FitnessStreamCore/Schema/SchemaDefinition.swift` | The `SchemaDefinition` Codable model — defines the JSON shape of `GET /schema` |
| `Sources/FitnessStreamCore/Schema/SchemaResolver.swift` | Resolution logic — how the SDK decides which metrics to include |

### Integration walkthrough

Guide the user through these steps:

1. **Minimum viable endpoint**: Their server needs to accept `POST` requests with `Content-Type: application/json`. The body is a flat JSON object with `workout_type`, `elapsed_seconds`, `timestamp`, and whatever metrics the user toggled on. Return `200` on success. Also handle `{"ping": true}` health check POSTs with a `200`.

2. **Headers**: The SDK sends `X-API-Key` if the user configured one. They should validate it if they require authentication.

3. **Optional schema endpoint**: If they want to control which metrics they receive, serve `GET {base_url}/schema` returning a `SchemaDefinition` JSON. The SDK appends `/schema` to whatever URL the user entered. The schema is fetched when the user taps "Verify Connection" in the app's settings.

4. **Generate a schema**: Use the schema tool to create a starting template:
   - `node Tools/schema-tool.js list` to see all available metrics
   - `node Tools/schema-tool.js generate --preset running -o schema.json` for a preset
   - Add `--custom '{"field":"type"}'` to include app-specific custom metrics

5. **Validate the schema**: Run `node Tools/schema-tool.js validate schema.json` before deploying. This catches typos, type mismatches, and warns about custom metrics that need app-side registration.

6. **Coordinate custom metrics**: If they request identifiers not in `Tools/catalog.json`, those are custom metrics that the app developer must register with `engine.registerCustom()`. The vendor must verify with the app developer that these identifiers are available and match the expected types.

### Schema negotiation behavior

Explain these rules when the vendor asks about what happens after they deploy a schema:

- The SDK fetches `GET /schema` automatically after a successful health check
- Metrics in the schema that the app registered are added to the user's toggle list
- Metrics the app didn't register are silently dropped — no error
- `"required": true` metrics that can't be resolved cause the entire schema to be rejected
- The user can still toggle individual metrics off even if the schema requests them
- If `GET /schema` fails (404, timeout, etc.), the SDK streams the app's default registered metrics — no schema is required
- The payload format is always flat JSON: `{ "heart_rate": 148.0, "workout_type": "Running", ... }` — no nesting

### Common tasks

- **Testing locally**: They can run the schema tool against their schema file before deploying. The `validate` command checks everything the SDK would check at runtime.
- **Adding custom metrics later**: Just update the schema JSON, no SDK changes needed. But the app must also register the new custom identifiers.
- **Multiple app support**: Different apps may register different metrics. A single schema works across apps — unresolvable metrics are silently dropped. Use `"required": false` unless a metric is truly mandatory.

### Pitfalls to warn about

- The schema URL is `{user_entered_url}/schema`, not a separate configurable URL. The vendor's schema must be served at that path.
- `value_type` on custom metrics in the schema is informational — the SDK doesn't enforce it. But it helps the app developer verify the contract.
- The payload is flat JSON with snake_case keys. There is no `values` wrapper object.
- Meta fields (`workout_type`, `elapsed_seconds`, `timestamp`) are always included regardless of the schema.
- The SDK sends data at a user-configurable frequency (1-30 seconds). Vendors should not assume a fixed interval.

---

## General repo context

- The SDK is a Swift Package with two library products: `FitnessStreamCore` (no UI dependencies) and `FitnessStreamUI` (SwiftUI, depends on Core).
- `Tools/` contains Node.js tooling for endpoint vendors. It is not part of the Swift package.
- The metric catalog is defined in two places that must stay in sync: `Sources/FitnessStreamCore/Catalog/MetricCatalog.swift` (Swift source of truth) and `Tools/catalog.json` (JS tooling reference). When adding new metrics, update both.
- All public types are in `FitnessStreamCore`. The UI product only adds `StreamConfigView`.
- The SDK targets iOS 16+ and watchOS 9+. Some HealthKit types (cycling cadence/power/speed) require iOS 17+ and are gated with `#available` checks in `MetricCollector.swift`.
