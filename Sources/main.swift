// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import JSONSchemaBuilder
import MCPServer
import OSLog

// 定义版本信息
let APP_VERSION = "0.1.1"
let APP_NAME = "memory-mcp-server"

let mcpLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier.map { "\($0).mcp" } ?? "tech.5km.memory.mcp-server", category: "mcp")

// 解析命令行参数
func processCommandLineArguments() -> Bool {
    let arguments = CommandLine.arguments

    if arguments.contains("--version") || arguments.contains("-v") {
        print("\(APP_NAME) version \(APP_VERSION)")
        return false
    }

    if arguments.contains("--help") || arguments.contains("-h") {
        printHelp()
        return false
    }

    return true
}

// 显示帮助信息
func printHelp() {
    print(
        """
        \(APP_NAME) - A knowledge graph memory server for MCP

        USAGE:
            \(APP_NAME) [OPTIONS]

        OPTIONS:
            -h, --help       Show this help message and exit
            -v, --version    Show version information and exit

        ENVIRONMENT VARIABLES:
            MEMORY_FILE_PATH    Path to the memory storage JSON file (default: memory.json in the current directory)

        DESCRIPTION:
            This MCP server provides knowledge graph management capabilities, 
            enabling LLMs to create, read, update, and delete entities and relations
            in a persistent knowledge graph, helping AI assistants maintain memory across conversations.
        """)
}

// 只有在没有特殊命令行参数时才运行服务器
if processCommandLineArguments() {
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

    do {
        let server = try await MCPServer(
            info: Implementation(name: APP_NAME, version: APP_VERSION),
            capabilities: ServerCapabilityHandlers(tools: memoryTools),
            transport: proxy(transport))

        print("\(APP_NAME) v\(APP_VERSION) started successfully")
        print("Knowledge Graph MCP Server running on stdio")

        try await server.waitForDisconnection()
    } catch {
        print("Error starting server: \(error)")
        exit(1)
    }
}
