//
//  ModelFiles.swift
//  AdverbModels
//
//  WHAT: What a model folder says about the model without loading it: its type, whether it has a
//        vision tower, its context length, whether its template can think, its sampling defaults.
//

import AdverbCore
import Foundation

struct ModelFiles {
    let directory: URL
    let config: JSONValue
    let chatTemplate: String
    let generation: JSONValue?

    static func load(_ directory: URL) -> ModelFiles? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("config.json")),
              let config = try? JSONValue.parse(data) else { return nil }
        func json(_ name: String) -> JSONValue? {
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { try? JSONValue.parse($0) }
        }
        var template = (try? String(contentsOf: directory.appendingPathComponent("chat_template.jinja"), encoding: .utf8)) ?? ""
        if template.isEmpty { template = json("chat_template.json")?["chat_template"]?.stringValue ?? "" }
        if template.isEmpty { template = json("tokenizer_config.json")?["chat_template"]?.stringValue ?? "" }
        return ModelFiles(directory: directory, config: config, chatTemplate: template, generation: json("generation_config.json"))
    }

    var modelType: String { config["model_type"]?.stringValue ?? "unknown" }
    var hasVision: Bool { config["vision_config"] != nil }
    var maxPositions: Int {
        (config["max_position_embeddings"] ?? config["text_config"]?["max_position_embeddings"])?.intValue ?? 32_768
    }
    /// The template turns thinking on and off (`enable_thinking`), or writes `<think>` itself.
    var thinks: Bool { chatTemplate.contains("enable_thinking") || chatTemplate.contains("<think>") || chatTemplate.contains("<|think|>") }
    var takesThinkingSwitch: Bool { chatTemplate.contains("enable_thinking") }

    var temperature: Double? { generation?["temperature"]?.doubleValue }
    var topP: Double? { generation?["top_p"]?.doubleValue }
    var topK: Int? { generation?["top_k"]?.intValue }

    func info(id: String) -> ModelInfo {
        ModelInfo(id: id, revision: ModelHome.commit(of: directory), title: ModelCatalog.spec(id)?.title,
                  contextTokens: min(maxPositions, 262_144), acceptsImages: hasVision, thinks: thinks)
    }
}
