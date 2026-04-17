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

## Installation

### Swift Package Manager

Add the package to your project via Xcode:

1. File → Add Package Dependencies...
2. Enter: `https://github.com/wildemat/fitness-stream-sdk`
3. Select version rule (recommended: **Up to Next Major** from `0.1.0`)
4. Add `FitnessStreamCore` to your target

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wildemat/fitness-stream-sdk", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "FitnessStreamCore", package: "fitness-stream-sdk"),
        ]
    ),
]
```

## Quick Start

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

## Available Metrics

### HealthKit (17 types)

`heart_rate`, `active_energy_kcal`, `distance_meters`, `distance_cycling_meters`, `step_count`, `cadence`, `cycling_power`, `cycling_speed`, `running_power`, `running_speed`, `running_stride_length`, `running_vertical_oscillation`, `running_ground_contact_time`, `swimming_stroke_count`, `distance_swimming`, `vo2_max`, `respiratory_rate`

### Computed

`pace_min_per_km`, `heart_rate_zone`

### Location

`latitude`, `longitude`, `elevation_meters`

### Custom

Any identifier + value type registered by the host app. Supports `double`, `int`, `string`, `bool`, and nested `object` types.

## License

MIT. See [LICENSE](LICENSE).
