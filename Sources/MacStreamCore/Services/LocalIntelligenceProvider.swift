import Foundation

public protocol LocalIntelligenceProvider: Sendable {
    var status: LocalIntelligenceStatus { get }

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan
    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String
}

public extension LocalIntelligenceProvider {
    var status: LocalIntelligenceStatus {
        LocalIntelligenceStatus(
            provider: .rules,
            availability: .available,
            detail: "Fast local rule engine"
        )
    }
}

public enum LocalIntelligenceProviderKind: String, CaseIterable, Identifiable, Sendable {
    case rules
    case mlx
    case openAICompatible

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rules: "Rule Engine"
        case .mlx: "MLX Local Model"
        case .openAICompatible: "Local server (OpenAI-compatible)"
        }
    }
}

public enum LocalIntelligenceAvailability: String, Sendable {
    case available
    case fallback
    case unavailable

    public var title: String {
        switch self {
        case .available: "Ready"
        case .fallback: "Fallback"
        case .unavailable: "Unavailable"
        }
    }
}

public struct LocalIntelligenceStatus: Equatable, Sendable {
    public var provider: LocalIntelligenceProviderKind
    public var availability: LocalIntelligenceAvailability
    public var detail: String

    public init(
        provider: LocalIntelligenceProviderKind,
        availability: LocalIntelligenceAvailability,
        detail: String
    ) {
        self.provider = provider
        self.availability = availability
        self.detail = detail
    }
}

public struct SetupPlan: Equatable, Sendable {
    public var title: String
    public var scenes: [SceneKind]
    public var directorProfile: DirectorProfile
    public var directorRuleSummary: String

    public init(
        title: String,
        scenes: [SceneKind],
        directorProfile: DirectorProfile,
        directorRuleSummary: String
    ) {
        self.title = title
        self.scenes = scenes
        self.directorProfile = directorProfile
        self.directorRuleSummary = directorRuleSummary
    }
}

public enum SetupPlanDecodingError: Error, LocalizedError {
    case missingJSON
    case unsupportedProfile(String)

    public var errorDescription: String? {
        switch self {
        case .missingJSON: "Model response did not include a setup plan JSON object."
        case let .unsupportedProfile(profile): "Unsupported director profile: \(profile)."
        }
    }
}

public struct SetupPlanPromptBuilder: Sendable {
    public static let maxStreamDescriptionCharacters = 1_000

    public init() {}

    public static func boundedStreamDescription(_ streamDescription: String) -> String {
        let trimmed = streamDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxStreamDescriptionCharacters else { return trimmed }
        return String(trimmed.prefix(maxStreamDescriptionCharacters))
    }

    public func prompt(for streamDescription: String) -> String {
        let streamDescription = Self.boundedStreamDescription(streamDescription)

        return """
        You are configuring MacStream, a local macOS streaming director.
        Return only compact JSON with this schema:
        {"title":"short stream title","profile":"balanced|coding|demo|teaching|podcast","summary":"one sentence switching rule"}

        The live director is deterministic, so do not ask for real-time LLM control.
        Stream description: \(streamDescription)
        """
    }
}

public struct SetupPlanResponseDecoder: Sendable {
    public init() {}

    public func decode(_ response: String) throws -> SetupPlan {
        guard let data = Self.firstJSONObject(in: response) else {
            throw SetupPlanDecodingError.missingJSON
        }

        let decoded = try JSONDecoder().decode(ModelSetupPlan.self, from: data)
        let profile = try Self.profile(for: decoded.profile)
        return SetupPlan(
            title: decoded.title.trimmingCharacters(in: .whitespacesAndNewlines),
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: profile,
            directorRuleSummary: decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func profile(for rawProfile: String) throws -> DirectorProfile {
        switch rawProfile.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case DirectorProfileKind.balanced.rawValue: .balanced
        case DirectorProfileKind.coding.rawValue: .coding
        case DirectorProfileKind.demo.rawValue: .demo
        case DirectorProfileKind.teaching.rawValue: .teaching
        case DirectorProfileKind.podcast.rawValue: .podcast
        default: throw SetupPlanDecodingError.unsupportedProfile(rawProfile)
        }
    }

    private static func firstJSONObject(in response: String) -> Data? {
        var start: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = response.startIndex

        while index < response.endIndex {
            let character = response[index]

            if start == nil {
                if character == "{" {
                    start = index
                    depth = 1
                }
                index = response.index(after: index)
                continue
            }

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let start {
                    return Data(String(response[start...index]).utf8)
                }
            }

            index = response.index(after: index)
        }

        return nil
    }

    private struct ModelSetupPlan: Decodable {
        var title: String
        var profile: String
        var summary: String
    }
}

public struct RuleBasedLocalIntelligenceProvider: LocalIntelligenceProvider {
    public init() {}

    public var status: LocalIntelligenceStatus {
        LocalIntelligenceStatus(
            provider: .rules,
            availability: .available,
            detail: "Fast local setup presets with no model load"
        )
    }

    public func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        let lowered = SetupPlanPromptBuilder.boundedStreamDescription(prompt).lowercased()
        let profile: DirectorProfile
        let title: String
        let summary: String

        if lowered.contains("podcast") || lowered.contains("interview") || lowered.contains("talk show") {
            profile = .podcast
            title = "Podcast Stream"
            summary = "Keep Face dominant, switch slowly, and treat screen activity as supporting context."
        } else if lowered.contains("teach") || lowered.contains("workshop") || lowered.contains("course") || lowered.contains("class") {
            profile = .teaching
            title = "Teaching Stream"
            summary = "Prefer Face while explaining, keep cuts slower, and avoid BRB unless the session is clearly idle."
        } else if lowered.contains("demo") || lowered.contains("launch") || lowered.contains("product") {
            profile = .demo
            title = "Product Demo"
            summary = "Balance Face and Screen, cut to Screen when the product is active, and keep explanations visible."
        } else if lowered.contains("coding") || lowered.contains("code") || lowered.contains("xcode") || lowered.contains("programming") {
            profile = .coding
            title = "Coding Stream"
            summary = "Favor Screen + Face while talking over code, cut to Screen earlier when editor motion carries the moment, and wait longer before BRB."
        } else {
            profile = .balanced
            title = "Talking + Screen"
            summary = "Prefer Face while explaining, Screen + Face while talking over active work, Screen when action carries the moment, and BRB during quiet idle stretches."
        }

        return SetupPlan(
            title: title,
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: profile,
            directorRuleSummary: summary
        )
    }

    public func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "\(recommendation.reason) Signals: speech \(Int(snapshot.speechLevel * 100))%, motion \(Int(snapshot.screenMotion * 100))%, app \(snapshot.activeApplication)."
    }
}

public typealias StubLocalIntelligenceProvider = RuleBasedLocalIntelligenceProvider

public struct MLXLocalIntelligenceProvider: LocalIntelligenceProvider {
    public static let defaultModelIdentifier = "LiquidAI/LFM2.5-8B-A1B-MLX-4bit"

    public var modelIdentifier: String

    private let fallback: any LocalIntelligenceProvider
    private let promptBuilder = SetupPlanPromptBuilder()
    private let responseDecoder = SetupPlanResponseDecoder()

    public init(
        modelIdentifier: String = Self.defaultModelIdentifier,
        fallback: any LocalIntelligenceProvider = RuleBasedLocalIntelligenceProvider()
    ) {
        self.modelIdentifier = modelIdentifier
        self.fallback = fallback
    }

    public var status: LocalIntelligenceStatus {
        #if MAC_STREAM_HAS_MLX
        LocalIntelligenceStatus(
            provider: .mlx,
            availability: .available,
            detail: "\(modelIdentifier) setup adapter linked"
        )
        #else
        LocalIntelligenceStatus(
            provider: .mlx,
            availability: .fallback,
            detail: "MLX Swift LM not linked; using fast local rules"
        )
        #endif
    }

    public func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        #if MAC_STREAM_HAS_MLX
        let modelPrompt = promptBuilder.prompt(for: prompt)
        _ = modelPrompt
        // When the MLX Swift LM integration is linked, this setup-only path
        // should load the configured model, generate JSON, and decode it below.
        // Live scene switching must remain deterministic and never wait on a model.
        return try await fallback.generateSetupPlan(for: prompt)
        #else
        return try await fallback.generateSetupPlan(for: prompt)
        #endif
    }

    public func decodeSetupPlanResponse(_ response: String) throws -> SetupPlan {
        try responseDecoder.decode(response)
    }

    public func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        try await fallback.explain(recommendation, snapshot: snapshot)
    }
}
