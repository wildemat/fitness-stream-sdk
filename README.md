# FitnessStream SDK

A schema-driven streaming SDK for iOS and watchOS that collects live workout metrics from HealthKit, CoreLocation, and custom app-defined sources, then streams them to any HTTP endpoint.

## Features

- **Dynamic metric collection** — registers only the HealthKit queries needed based on a resolved schema
- **Schema negotiation** — endpoint defines what metrics it wants, SDK reports what it can provide
- **Custom metrics** — host app pushes arbitrary key-value data alongside HK metrics
- **Pluggable transport** — ships with HTTP POST, extensible via `StreamTransport` protocol
- **Zero third-party dependencies** — only Apple frameworks (HealthKit, CoreLocation, Foundation)

## Requirements

- iOS 16.0+ / watchOS 9.0+
- Swift 5.9+
- Xcode 15.0+

---

## For App Developers

### Installation

Add the package to your project via Xcode:

1. File → Add Package Dependencies...
2. Enter: `https://github.com/wildemat/fitness-stream-sdk`
3. Select version rule (recommended: **Up to Next Major** from `0.2.0`)
4. Add `FitnessStreamCore` to your target (and `FitnessStreamUI` if you want the config panel)

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wildemat/fitness-stream-sdk", from: "0.2.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "FitnessStreamCore", package: "fitness-stream-sdk"),
            .product(name: "FitnessStreamUI", package: "fitness-stream-sdk"),
        ]
    ),
]
```

### Products

| Product | What it includes | When to use |
|---------|-----------------|-------------|
| `FitnessStreamCore` | Engine, metric collection, schema negotiation, transport | Always required |
| `FitnessStreamUI` | `StreamConfigView` (SwiftUI settings panel) | Optional. Use if you want the drop-in config UI. Skip if you build your own settings screen. |

### Quick Start

```swift
import FitnessStreamCore
import HealthKit

// 1. Create the engine
let engine = FitnessStreamEngine(healthStore: HKHealthStore())

// 2. Register what metrics your app can provide
engine.register(metrics: [
    "heart_rate",
    "active_energy_kcal",
    "distance_meters",
    "pace_min_per_km",
    "heart_rate_zone",
    "latitude", "longitude", "elevation_meters",
])

// 3. Register custom metrics (app-defined, any shape)
engine.registerCustom(identifier: "current_exercise", valueType: .string)
engine.registerCustom(identifier: "segment_reps", valueType: .int)

// 4. Configure an endpoint
let endpoint = StreamEndpoint(
    url: URL(string: "https://your-server.com/metrics")!,
    apiKey: "sk-...",
    frequency: 5.0
)
engine.configureSimple(endpoint: endpoint)

// 5. Start streaming when a workout begins
engine.startStreaming(workoutType: "Running", startDate: Date())

// 6. Call tick() on your 1-second timer — engine handles throttle
let snapshot = engine.tick(elapsedSeconds: elapsed)

// 7. Push custom values anytime during the workout
engine.setCustomValue(.string("Squats"), for: "current_exercise")

// 8. Stop when done
engine.stopStreaming()
```

### HealthKit Authorization

The SDK does not request HealthKit authorization itself — your app must do this. The engine provides helpers to get the exact types needed based on what you registered:

```swift
let readTypes = engine.requiredHealthKitReadTypes   // Set<HKObjectType>
let shareTypes = engine.requiredHealthKitShareTypes  // Set<HKSampleType>

healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
    // proceed with workout
}
```

You must also add the HealthKit entitlement and usage descriptions to your `Info.plist`:

```
NSHealthShareUsageDescription — why you read health data
NSHealthUpdateUsageDescription — why you write workout sessions
```

### Workout Lifecycle

The SDK does **not** own the `HKWorkoutSession`. Your app creates and manages the session. The SDK attaches its metric collectors when you call `startStreaming()` and detaches them on `stopStreaming()`.

```swift
// Your app starts the HK session
let session = try HKWorkoutSession(healthStore: store, configuration: config)
session.startActivity(with: Date())

// Then tell the SDK to start collecting and streaming
engine.startStreaming(workoutType: "Running", startDate: Date())

// On your 1-second timer, call tick() — the engine collects from HK,
// builds a snapshot, and streams it at the configured frequency
let snapshot = engine.tick(elapsedSeconds: elapsed)

// Pause/resume streaming with the workout
engine.pauseStreaming()
engine.resumeStreaming()

// Stop when the workout ends
engine.stopStreaming()
```

The `tick()` method returns a `MetricSnapshot` on every call. You can read its values to update your own UI — you don't have to query HealthKit separately for display purposes.

### Custom Metrics

Custom metrics let you attach any app-specific data to the streamed payload. The SDK doesn't collect these — your app pushes values, and the SDK includes them in snapshots alongside HealthKit data.

**Register at startup** (before streaming begins):

```swift
engine.registerCustom(identifier: "current_exercise", valueType: .string)
engine.registerCustom(identifier: "reps", valueType: .int)
engine.registerCustom(identifier: "weight_lb", valueType: .double)
engine.registerCustom(identifier: "is_rest_period", valueType: .bool)

// Nested objects are also supported
engine.registerCustom(identifier: "segment_info", valueType: .object)
```

**Push values anytime during a workout:**

```swift
engine.setCustomValue(.string("Bench Press"), for: "current_exercise")
engine.setCustomValue(.int(12), for: "reps")
engine.setCustomValue(.double(135.0), for: "weight_lb")
engine.setCustomValue(.bool(false), for: "is_rest_period")

// Nested object
engine.setCustomValue(.object([
    "exercise_name": .string("Bench Press"),
    "reps": .int(12),
    "load_lb": .double(135.0),
]), for: "segment_info")

// Clear when no longer relevant
engine.clearCustomValue(for: "current_exercise")
```

Rules:
- Custom identifiers cannot collide with catalog identifiers (e.g., you can't register `"heart_rate"` as custom)
- Pushing a value for an unregistered identifier is a no-op with a warning log
- Custom values persist across pause/resume. Call `clearCustomValue` explicitly when needed.

### Friendly Name Overrides

The SDK provides default display names for all catalog metrics (e.g., `"heart_rate"` shows as "Heart Rate" in the config UI). You can override these for your app:

```swift
engine.configuration.friendlyNameOverrides["active_energy_kcal"] = "Calories"
engine.configuration.friendlyNameOverrides["distance_meters"] = "Run Distance"
engine.configuration.friendlyNameOverrides["current_exercise"] = "Exercise"
```

Overrides apply to the `StreamConfigView` toggle list. If no override is set, the SDK uses its built-in friendly names. If there's no built-in name either (custom metrics), it falls back to title-casing the identifier.

### StreamConfigView (Drop-in Settings UI)

`FitnessStreamUI` provides a complete SwiftUI settings panel that handles endpoint management, connection verification, schema negotiation, and per-metric toggle selection:

```swift
import FitnessStreamUI

// Present as a sheet
.sheet(isPresented: $showSettings) {
    StreamConfigView(engine: engine)
}

// Or as a navigation destination
NavigationLink("Stream Settings") {
    StreamConfigView(engine: engine)
}

// Or wrapped in UIHostingController for UIKit apps
let hostingVC = UIHostingController(rootView: StreamConfigView(engine: engine))
present(hostingVC, animated: true)
```

**What the config view provides:**

| Section | Controls |
|---------|----------|
| Streaming | Enable/disable toggle |
| Connection | Endpoint URL, API key, write frequency slider, **Save Endpoint** button |
| Verification | **Verify Connection** button with status messages |
| Data Points | Per-metric toggles with friendly names, grouped by source |

**How it works:**

1. User enters an endpoint URL and taps **Save Endpoint**. The metric list appears showing the app's default registered metrics, all toggled on.
2. User taps **Verify Connection**. The SDK pings the endpoint, then auto-fetches `GET {endpoint}/schema`.
3. If the endpoint serves a schema, new metrics are added to the list (toggled on by default). Metrics the endpoint doesn't request are removed. **Existing toggle choices are never overridden.**
4. If the endpoint has no schema, the message "No custom data requested" appears and the default list stays.
5. The user toggles individual metrics on/off. Only toggled-on metrics are included in the streamed payload.
6. All state (endpoint, toggles, frequency) is persisted to `UserDefaults` automatically.
7. Changing the endpoint URL and saving it resets the toggle list to defaults until the next verification.

**If you're not using StreamConfigView**, you can still read/write all state through `engine.configuration`:

```swift
let config = engine.configuration

config.savedEndpointURL = "https://example.com/metrics"
config.savedAPIKey = "sk-..."
config.frequency = 5.0
config.streamEnabled = true

// Read the user's toggle selections
let enabledMetrics = config.enabledIdentifiers  // Set<String>

// Check what's toggled
let hrEnabled = config.metricToggles["heart_rate"] ?? false
```

### StreamConfiguration Persistence

`StreamConfiguration` persists all state to `UserDefaults`. By default it uses the standard suite with the key prefix `com.fitnessstream.sdk`. If you need a custom suite (e.g., for app groups or multiple SDK instances):

```swift
let config = StreamConfiguration(suiteName: "group.com.myapp", keyPrefix: "myapp.stream")
let engine = FitnessStreamEngine(healthStore: store, configuration: config)
```

Persisted state includes: endpoint URL, API key, frequency, stream enabled toggle, all metric toggle values, and remote schema identifiers.

---

## For Endpoint Vendors

This section is for developers building servers or services that **receive** workout data from apps using this SDK. Your server needs to handle incoming metric payloads and can optionally serve a schema to control which metrics get sent.

### What your server receives

The SDK sends `POST` requests to your endpoint URL with a flat JSON body:

```json
{
  "workout_type": "Running",
  "elapsed_seconds": 845,
  "timestamp": "2026-04-15T12:30:45Z",
  "heart_rate": 148.0,
  "active_energy_kcal": 285.0,
  "distance_meters": 4200.0,
  "pace_min_per_km": 5.72,
  "heart_rate_zone": 4,
  "latitude": 37.7749,
  "longitude": -122.4194,
  "elevation_meters": 48.0
}
```

Three fields are always present: `workout_type`, `elapsed_seconds`, `timestamp`. Everything else depends on what the app registered and what the user toggled on.

**Headers:**

| Header | Value |
|--------|-------|
| `Content-Type` | `application/json` |
| `X-API-Key` | The API key the user entered (if any) |

### Minimum server requirements

Your endpoint needs to handle two requests:

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/` (your base URL) | Receive metric payloads. Return `200` on success. |
| `POST` | `/` (your base URL) | Handle health check pings (`{"ping": true}`). Return `200`. |

That's it for basic integration. The SDK streams to whatever URL the user enters.

### Optional: Serve a schema to request specific metrics

If you want to control **which** metrics the app sends you, serve a `GET /schema` endpoint. The SDK auto-fetches this when the user taps "Verify Connection" in the settings UI.

**Your server serves `GET {base_url}/schema`:**

```json
{
  "schema_version": "1.0",
  "name": "my-overlay",
  "description": "Metrics for a running stream overlay",
  "metrics": [
    { "identifier": "heart_rate", "required": true },
    { "identifier": "active_energy_kcal", "required": false },
    { "identifier": "distance_meters", "required": false },
    { "identifier": "pace_min_per_km", "required": false }
  ],
  "meta_fields": ["workout_type", "elapsed_seconds", "timestamp"]
}
```

**Schema fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `schema_version` | Yes | Schema format version (use `"1.0"`) |
| `name` | Yes | Human-readable name for the schema |
| `description` | No | What this schema is for |
| `metrics` | Yes | Array of metric requests |
| `metrics[].identifier` | Yes | The metric identifier (see catalog below) |
| `metrics[].required` | No | If `true`, the SDK rejects the schema when this metric is unavailable. Default `false`. |
| `metrics[].value_type` | No | Type hint: `"double"`, `"int"`, `"string"`, `"bool"`, `"object"`. Informational for custom metrics. |
| `meta_fields` | No | Informational. These are always included regardless. |

**What happens when the SDK fetches your schema:**

1. The SDK resolves your requested metrics against what the app registered
2. Metrics the app can provide are added to the user's toggle list (default: on)
3. Metrics the app can't provide are silently dropped
4. The user can still toggle individual metrics on/off
5. Only toggled-on metrics appear in the `POST` payload

If `GET /schema` returns a non-200 status or isn't available, the SDK falls back to streaming whatever the app registered. No schema endpoint is required.

### Requesting custom metrics

Custom metrics are app-defined values that don't come from HealthKit or CoreLocation. These are things like exercise names, rep counts, weight amounts, or any domain-specific data the app pushes during a workout.

**You can request custom metrics in your schema just like catalog metrics:**

```json
{
  "schema_version": "1.0",
  "name": "hybrid-workout-overlay",
  "metrics": [
    { "identifier": "heart_rate", "required": true },
    { "identifier": "active_energy_kcal" },
    { "identifier": "current_exercise", "value_type": "string" },
    { "identifier": "weight", "value_type": "double" },
    { "identifier": "sets", "value_type": "int" },
    { "identifier": "reps", "value_type": "int" },
    { "identifier": "current_set", "value_type": "int" }
  ]
}
```

Custom metrics will only resolve if the app developer has registered them with `engine.registerCustom()`. **You must coordinate with the app developer** to confirm which custom identifiers are available and what types they use. The SDK cannot auto-collect custom metrics — the app pushes them.

Include `value_type` on custom metrics so the app developer can verify the contract matches what they register.

### Schema tool (generate and validate schemas)

The SDK ships a CLI tool (`Tools/schema-tool.js`) to help you build and validate schema files. Requires Node.js 18+.

**List all available catalog metrics:**

```bash
node Tools/schema-tool.js list
```

**Generate a schema from a preset:**

```bash
# Presets: running, cycling, gym, swimming, all
node Tools/schema-tool.js generate --preset running -o schema.json
```

**Generate a schema with custom metrics:**

```bash
# Inline JSON
node Tools/schema-tool.js generate --preset gym \
  --custom '{"current_exercise":"string","weight":"double","sets":"int","reps":"int","current_set":"int"}' \
  --name hybrid-overlay \
  -o schema.json

# Or from a file
node Tools/schema-tool.js generate --preset gym \
  --custom custom-metrics.json \
  -o schema.json
```

**Validate a schema file:**

```bash
node Tools/schema-tool.js validate schema.json
```

The validator checks for:
- Missing required fields (`schema_version`, `name`, `metrics`)
- Invalid `value_type` values
- Duplicate identifiers
- Custom metrics without type declarations (warning)
- Identifiers that aren't in the SDK catalog (reported as custom, with a reminder to verify with the app developer)

### Available metric identifiers

These are the identifiers you can request in your schema. All are sourced automatically by the SDK from Apple HealthKit, CoreLocation, or derived computation.

**HealthKit (17 types):**

| Identifier | Unit | Type | Aggregation |
|------------|------|------|-------------|
| `heart_rate` | count/min | double | latest |
| `active_energy_kcal` | kcal | double | cumulative |
| `distance_meters` | m | double | cumulative |
| `distance_cycling_meters` | m | double | cumulative |
| `step_count` | count | int | cumulative |
| `cadence` | count/min | double | latest |
| `cycling_power` | W | double | latest |
| `cycling_speed` | m/s | double | latest |
| `running_power` | W | double | latest |
| `running_speed` | m/s | double | latest |
| `running_stride_length` | m | double | latest |
| `running_vertical_oscillation` | cm | double | latest |
| `running_ground_contact_time` | ms | double | latest |
| `swimming_stroke_count` | count | int | cumulative |
| `distance_swimming` | m | double | cumulative |
| `vo2_max` | mL/kg/min | double | latest |
| `respiratory_rate` | count/min | double | latest |

**Computed:**

| Identifier | Type | Description |
|------------|------|-------------|
| `pace_min_per_km` | double | Derived from elapsed time and distance |
| `heart_rate_zone` | int | 1–5, derived from heart rate |

**Location:**

| Identifier | Type |
|------------|------|
| `latitude` | double |
| `longitude` | double |
| `elevation_meters` | double |

**Custom:** Any identifier the app developer registers. Coordinate with them directly.

---

## Architecture

```
Host App                        SDK                              Endpoint
─────────                       ───                              ────────
                         ┌─────────────────────┐
register(metrics:) ────> │   MetricRegistry    │
registerCustom()   ────> │  (HK + custom)      │
                         └────────┬────────────┘
                                  │
configure(endpoint:)              ▼
  │                      ┌─────────────────────┐       GET /schema
  └────────────────────> │   SchemaResolver    │ ◄──────────────────  Endpoint
                         │  registry ∩ wanted  │ ──────────────────> POST /schema/ack
                         └────────┬────────────┘
                                  │ resolved schema
                                  ▼
startStreaming() ──────> ┌─────────────────────┐
                         │ FitnessStreamEngine │
                         │                     │
                         │  MetricCollector ◄──── HealthKit (anchored queries)
                         │  LocationCollector ◄── CoreLocation
                         │  ComputedEngine ◄───── pace, HR zone (derived)
setCustomValue() ──────> │  CustomMetricStore  │
                         │         │           │
                         │         ▼           │
tick() ────────────────> │  MetricSnapshot     │
                         │  (values dict)      │
                         │         │           │
                         │         ▼           │
                         │  HTTPPostTransport ─────── POST /metrics ──> Endpoint
                         └─────────────────────┘
```

## License

MIT. See [LICENSE](LICENSE).
