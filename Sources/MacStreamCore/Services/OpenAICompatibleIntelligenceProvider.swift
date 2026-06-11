import Foundation

public struct OpenAICompatibleProviderConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:1234/v1")!
    public static let defaultModel = "local-model"
    public static let defaultTimeout: TimeInterval = 30

    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var timeout: TimeInterval

    public init(
        baseURL: URL = Self.defaultBaseURL,
        model: String = Self.defaultModel,
        apiKey: String? = nil,
        timeout: TimeInterval = Self.defaultTimeout
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
    }
}

public struct OpenAICompatibleLocalIntelligenceProvider: LocalIntelligenceProvider {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public static let probeTimeout: TimeInterval = 10

    public var configuration: OpenAICompatibleProviderConfiguration

    private let transport: Transport
    private let promptBuilder = SetupPlanPromptBuilder()
    private let responseDecoder = SetupPlanResponseDecoder()
    private let fallback: any LocalIntelligenceProvider
    private let probedStatus: LocalIntelligenceStatus?

    public init(
        configuration: OpenAICompatibleProviderConfiguration = OpenAICompatibleProviderConfiguration(),
        fallback: any LocalIntelligenceProvider = RuleBasedLocalIntelligenceProvider(),
        probedStatus: LocalIntelligenceStatus? = nil,
        transport: @escaping Transport = { request in try await URLSession.shared.data(for: request) }
    ) {
        self.configuration = configuration
        self.fallback = fallback
        self.probedStatus = probedStatus
        self.transport = transport
    }

    public var status: LocalIntelligenceStatus {
        if let probedStatus { return probedStatus }
        guard validationFailureDetail == nil else {
            return LocalIntelligenceStatus(
                provider: .openAICompatible,
                availability: .unavailable,
                detail: "Configure a local OpenAI-compatible model."
            )
        }
        return LocalIntelligenceStatus(
            provider: .openAICompatible,
            availability: .fallback,
            detail: "Local server configured; rules fallback available."
        )
    }

    public func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        guard validationFailureDetail == nil else {
            throw OpenAICompatibleProviderError.invalidConfiguration("Configure a local OpenAI-compatible model.")
        }

        var request = try makeRequest(endpoint: "chat/completions", method: "POST", timeout: configuration.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatCompletionRequest(
            model: trimmedModel,
            messages: [
                Message(role: "system", content: "Return only the requested MacStream setup JSON."),
                Message(role: "user", content: promptBuilder.prompt(for: prompt))
            ],
            temperature: 0.1,
            stream: false,
            responseFormat: ResponseFormat(type: "json_object")
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await transport(request)
        try validateSuccess(response)
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw OpenAICompatibleProviderError.missingMessageContent
        }
        return try responseDecoder.decode(content)
    }

    public func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        try await fallback.explain(recommendation, snapshot: snapshot)
    }

    public func probeCapabilities() async -> LocalIntelligenceStatus {
        if let validationFailureDetail {
            return LocalIntelligenceStatus(provider: .openAICompatible, availability: .unavailable, detail: validationFailureDetail)
        }

        do {
            let request = try makeRequest(
                endpoint: "models",
                method: "GET",
                timeout: min(configuration.timeout, Self.probeTimeout)
            )
            let (_, response) = try await transport(request)
            try validateSuccess(response)
            return LocalIntelligenceStatus(
                provider: .openAICompatible,
                availability: .available,
                detail: "Local server reachable for \(trimmedModel)."
            )
        } catch let error as OpenAICompatibleProviderError {
            return LocalIntelligenceStatus(
                provider: .openAICompatible,
                availability: .unavailable,
                detail: error.localizedDescription
            )
        } catch {
            return LocalIntelligenceStatus(
                provider: .openAICompatible,
                availability: .unavailable,
                detail: "Local server probe failed: \(error.localizedDescription)"
            )
        }
    }

    public func replacingProbedStatus(_ status: LocalIntelligenceStatus) -> Self {
        Self(configuration: configuration, fallback: fallback, probedStatus: status, transport: transport)
    }

    private var trimmedModel: String {
        configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAPIKey: String? {
        guard let apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    private var validationFailureDetail: String? {
        guard !trimmedModel.isEmpty else { return "Configure a local OpenAI-compatible model." }
        guard configuration.baseURL.scheme?.isEmpty == false,
              configuration.baseURL.host?.isEmpty == false,
              normalizedBaseURL() != nil
        else {
            return "Configure a local OpenAI-compatible server URL."
        }
        return nil
    }

    private func makeRequest(endpoint: String, method: String, timeout: TimeInterval) throws -> URLRequest {
        guard let baseURL = normalizedBaseURL() else {
            throw OpenAICompatibleProviderError.invalidConfiguration("Configure a local OpenAI-compatible server URL.")
        }

        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let trimmedAPIKey {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func normalizedBaseURL() -> URL? {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false
        else {
            return nil
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
        if pathComponents.last == "v1" {
            components.path = "/" + pathComponents.joined(separator: "/")
        } else {
            components.path = "/" + (pathComponents + ["v1"]).joined(separator: "/")
        }
        return components.url
    }

    private func validateSuccess(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICompatibleProviderError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenAICompatibleProviderError.httpStatus(httpResponse.statusCode)
        }
    }
}

private enum OpenAICompatibleProviderError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case httpStatus(Int)
    case missingMessageContent

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail): detail
        case .invalidResponse: "Local server returned an invalid response."
        case .httpStatus(let statusCode): "Local server returned HTTP \(statusCode)."
        case .missingMessageContent: "Local server response did not include setup content."
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [Message]
    var temperature: Double
    var stream: Bool
    var responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case stream
        case responseFormat = "response_format"
    }
}

private struct Message: Codable {
    var role: String
    var content: String
}

private struct ResponseFormat: Encodable {
    var type: String
}

private struct ChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        var content: String
    }
}
