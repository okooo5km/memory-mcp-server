// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import JSONSchemaBuilder
import MCPServer
import OSLog

let mcpLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier.map { "\($0).mcp" } ?? "tech.5km.memory.mcp-server", category: "mcp")

let transport = Transport.stdio()
func proxy(_ transport: Transport) -> Transport {
    var sendToDataSequence: AsyncStream<Data>.Continuation?
    let dataSequence = AsyncStream<Data>.init { continuation in
        sendToDataSequence = continuation
    }

    Task {
        for await data in transport.dataSequence {
            mcpLogger.info("Reading data from transport: \(String(data: data, encoding: .utf8)!, privacy: .public)")
            sendToDataSequence?.yield(data)
        }
    }

    return Transport(
        writeHandler: { data in
            mcpLogger.info("Writing data to transport: \(String(data: data, encoding: .utf8)!, privacy: .public)")
            try await transport.writeHandler(data)
        },
        dataSequence: dataSequence)
}

// Register all tools
let memoryTools: [any CallableTool] = [
    createEntitiesTool,
    createRelationsTool,
    addObservationsTool,
    deleteEntitiesTool,
    deleteObservationsTool,
    deleteRelationsTool,
    readGraphTool,
    searchNodesTool,
    openNodesTool,
]

let server = try await MCPServer(
    info: Implementation(name: "memory-mcp-server", version: "0.1.0"),
    capabilities: ServerCapabilityHandlers(tools: memoryTools),
    transport: proxy(transport))

try await server.waitForDisconnection()
