import Foundation

/// DeepSeek OpenAI 兼容 Chat Completions 的真实解析实现（技术基线 §9.1）。
/// 编译交付、结构正确即可；联网端到端验收由用户后续自测（已确认约定 1）。
///
/// - 仅传文本，无图片 / 语音（隐私边界）。
/// - 不做自动重试：失败即抛，重试为用户在入口层手动再触发——
///   避免对计费 API 隐式重试放大成本（本 TRD 决策，切片 02 据此设计失败态）。
struct DeepSeekClient: TransactionParsing {
    var keychain: KeychainStore = .shared
    var session: URLSession = .shared
    var model = "deepseek-chat"
    var endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    var timeout: TimeInterval = 20   // 明确超时（技术基线 §11 落地值）

    func parse(text: String, categories: [LedgerCategory]) async throws -> ParsedTransaction {
        guard let key = keychain.deepSeekKey, !key.isEmpty else { throw RecognitionError.noKey }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encodeBody(text: text, categories: categories)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw RecognitionError.timeout
        } catch {
            throw RecognitionError.network
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecognitionError.invalidResponse
        }
        return try decode(data)
    }

    // MARK: - 请求体

    /// system 交代"提取记账字段、只输出 JSON"，user 拼文本 + 可选分类名清单 + 目标 schema。
    /// response_format 走 json_object，让模型稳定吐 JSON（技术基线 §9.1 JSON output mode）。
    private func encodeBody(text: String, categories: [LedgerCategory]) throws -> Data {
        let categoryNames = categories.map(\.name).joined(separator: "、")
        let systemPrompt = """
        你是记账助手。从用户给的文本中提取一笔账单，只输出 JSON，不要任何解释文字。
        JSON 字段：amount（金额数字字符串，正数）、direction（"expense" 或 "income"）、\
        occurredAt（时间，格式 "yyyy-MM-dd HH:mm"，取不到留空）、merchant（商户，取不到留空）、\
        cardTail（银行卡尾号，取不到留空）、category（分类名，尽量从可选分类里选）。
        可选分类：\(categoryNames.isEmpty ? "无" : categoryNames)。
        """
        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text),
            ],
            responseFormat: .init(type: "json_object")
        )
        return try JSONEncoder().encode(payload)
    }

    // MARK: - 响应解码

    /// 解 choices[0].message.content 里的 JSON → ParsedTransaction；缺字段 / 非 JSON → invalidResponse。
    private func decode(_ data: Data) throws -> ParsedTransaction {
        guard let envelope = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = envelope.choices.first?.message.content,
              let contentData = content.data(using: .utf8),
              let fields = try? JSONDecoder().decode(ExtractedFields.self, from: contentData) else {
            throw RecognitionError.invalidResponse
        }

        let direction: TransactionDirection = (fields.direction == "income") ? .income : .expense
        return ParsedTransaction(
            amountText: fields.amount ?? "",
            direction: direction,
            occurredAt: Self.parseDate(fields.occurredAt),
            merchant: fields.merchant.nonEmpty,
            cardTail: fields.cardTail.nonEmpty,
            categoryName: fields.category.nonEmpty
        )
    }

    /// "yyyy-MM-dd HH:mm" → Date（解析失败 → nil，归一取当前）。
    private static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)
    }
}

// MARK: - 线格式 DTO

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

/// content 内层 JSON。amount 兼容模型输出为字符串或数字两种形态。
private struct ExtractedFields: Decodable {
    let amount: String?
    let direction: String?
    let occurredAt: String?
    let merchant: String?
    let cardTail: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case amount, direction, occurredAt, merchant, cardTail, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // amount 可能是 "256.00" 或裸数字 256 / 256.0，统一转字符串交给归一。
        // 裸数字用 Decimal.self 直解：JSONDecoder 从 JSON 数字原文构造 Decimal，不经 Double，
        // 避免 99.99 / 0.1 等十进制小数的浮点偏差（金额精度是记账红线）。
        if let string = try? container.decode(String.self, forKey: .amount) {
            amount = string
        } else if let number = try? container.decode(Decimal.self, forKey: .amount) {
            amount = number.description
        } else {
            amount = nil
        }
        direction = try? container.decode(String.self, forKey: .direction)
        occurredAt = try? container.decode(String.self, forKey: .occurredAt)
        merchant = try? container.decode(String.self, forKey: .merchant)
        cardTail = try? container.decode(String.self, forKey: .cardTail)
        category = try? container.decode(String.self, forKey: .category)
    }
}

private extension Optional where Wrapped == String {
    /// 去空白后为空 → nil（模型对取不到的字段常回空串）。
    var nonEmpty: String? {
        guard let self, !self.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return self
    }
}
