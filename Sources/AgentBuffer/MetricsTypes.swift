import Foundation

struct MetricsSummary: Codable {
    let generatedAt: String
    let config: MetricsConfig
    let current: MetricsCurrent
    let windows: [String: MetricsWindow]
}

struct MetricsConfig: Codable {
    let idleThreshold: Double
    let baseDir: String
}

struct MetricsCurrent: Codable {
    let running: Int
    let idle: Int
    let total: Int
    let utilization: Double
}

struct MetricsWindow: Codable {
    let windowStart: TimeInterval
    let windowEnd: TimeInterval
    let runningSeconds: Double
    let totalSeconds: Double
    let activeUtilization: Double
    let idleOverThreshold: Double
    let idleOverThresholdMinutes: Double
    let throughputPerHour: Double
    let taskSupplyRate: Double
    let tasksCompleted: Int
    let assignments: Int
    let responseSamples: Int
    let runtime: MetricsRuntime
    let responseTime: MetricsRuntime
    let responseHistogram: MetricsHistogram
    let bottleneckIndex: Double?
    let reworkRate: Double?
    let fragmentation: Double?
    let longTailRuntime: Double?
}

struct MetricsRuntime: Codable {
    let median: Double?
    let p90: Double?
}

struct MetricsHistogram: Codable {
    let buckets: [Int]
    let counts: [Int]
}

struct MetricsTimeseriesResponse: Codable {
    let window: String
    let windowStart: TimeInterval
    let windowEnd: TimeInterval
    let stepSeconds: Int
    let points: [MetricsTimeseriesPoint]
}

struct MetricsTimeseriesPoint: Codable {
    let t: TimeInterval
    let running: Int
    let total: Int
    let utilization: Double
}
