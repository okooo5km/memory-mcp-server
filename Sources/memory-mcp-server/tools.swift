import AppKit
import Foundation
import JSONSchemaBuilder
@preconcurrency import MCPServer

/// Error type for tool operations
struct ToolError: Error {
    let message: String
}

// MARK: - Memory Knowledge Graph Tools

/// Defines the memory file path using environment variable or default location
let memoryFilePath: String = {
    let currentDir = FileManager.default.currentDirectoryPath
    mcpLogger.info("Current working directory: \(currentDir, privacy: .public)")

    if let envPath = ProcessInfo.processInfo.environment["MEMORY_FILE_PATH"] {
        mcpLogger.info("Using memory file path from environment variable: \(envPath, privacy: .public)")
        return URL(fileURLWithPath: envPath).isFileURL && envPath.hasPrefix("/")
            ? envPath
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(envPath).path
    } else {
        let defaultPath = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        ).appendingPathComponent("memory.json").path
        mcpLogger.info(
            "Environment variable MEMORY_FILE_PATH not set, using default path: \(defaultPath, privacy: .public)")
        return defaultPath
    }
}()

/// Represents an entity in the knowledge graph
@Schemable
struct Entity: Codable, Sendable {
    @SchemaOptions(
        description: "The name of the entity"
    )
    let name: String

    @SchemaOptions(
        description: "The type of the entity"
    )
    let entityType: String

    @SchemaOptions(
        description: "An array of observation contents associated with the entity"
    )
    var observations: [String]
}

/// Represents a relation between entities in the knowledge graph
@Schemable
struct Relation: Codable, Sendable {
    @SchemaOptions(
        description: "The name of the entity where the relation starts"
    )
    let from: String

    @SchemaOptions(
        description: "The name of the entity where the relation ends"
    )
    let to: String

    @SchemaOptions(
        description: "The type of the relation"
    )
    let relationType: String
}

/// Represents the complete knowledge graph structure
struct KnowledgeGraph: Codable, Sendable {
    var entities: [Entity]
    var relations: [Relation]

    init() {
        entities = []
        relations = []
    }

    init(entities: [Entity], relations: [Relation]) {
        self.entities = entities
        self.relations = relations
    }
}

/// Handles all interactions with the knowledge graph
@available(macOS 10.15, *)
final class KnowledgeGraphManager: @unchecked Sendable {
    /// Loads the graph from the file system
    private func loadGraph() async throws -> KnowledgeGraph {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: memoryFilePath))
            let dataString = String(data: data, encoding: .utf8) ?? ""
            let lines = dataString.split(separator: "\n").filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            var graph = KnowledgeGraph()
            for line in lines {
                if let lineData = line.data(using: .utf8) {
                    let item = try JSONDecoder().decode(JSONItem.self, from: lineData)
                    if item.type == "entity", let entity = try? JSONDecoder().decode(EntityItem.self, from: lineData) {
                        graph.entities.append(
                            Entity(name: entity.name, entityType: entity.entityType, observations: entity.observations))
                    } else if item.type == "relation",
                        let relation = try? JSONDecoder().decode(RelationItem.self, from: lineData)
                    {
                        graph.relations.append(
                            Relation(from: relation.from, to: relation.to, relationType: relation.relationType))
                    }
                }
            }
            return graph
        } catch {
            if let nsError = error as NSError?, nsError.code == NSFileReadNoSuchFileError {
                return KnowledgeGraph()
            }
            throw error
        }
    }

    /// Saves the graph to the file system
    private func saveGraph(_ graph: KnowledgeGraph) async throws {
        var lines: [String] = []

        // Serialize entities
        for entity in graph.entities {
            let entityItem = EntityItem(
                type: "entity", name: entity.name, entityType: entity.entityType, observations: entity.observations)
            if let jsonData = try? JSONEncoder().encode(entityItem),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                lines.append(jsonString)
            }
        }

        // Serialize relations
        for relation in graph.relations {
            let relationItem = RelationItem(
                type: "relation", from: relation.from, to: relation.to, relationType: relation.relationType)
            if let jsonData = try? JSONEncoder().encode(relationItem),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                lines.append(jsonString)
            }
        }

        // Write to file
        let outputString = lines.joined(separator: "\n")
        try outputString.write(to: URL(fileURLWithPath: memoryFilePath), atomically: true, encoding: .utf8)
    }

    /// Helper types for encoding/decoding
    private struct JSONItem: Codable {
        let type: String
    }

    private struct EntityItem: Codable {
        let type: String
        let name: String
        let entityType: String
        let observations: [String]
    }

    private struct RelationItem: Codable {
        let type: String
        let from: String
        let to: String
        let relationType: String
    }

    /// Creates new entities in the knowledge graph
    func createEntities(_ entities: [Entity]) async throws -> [Entity] {
        var graph = try await loadGraph()
        var newEntities: [Entity] = []

        for entity in entities {
            if !graph.entities.contains(where: { $0.name == entity.name }) {
                graph.entities.append(entity)
                newEntities.append(entity)
            }
        }

        try await saveGraph(graph)
        return newEntities
    }

    /// Creates new relations in the knowledge graph
    func createRelations(_ relations: [Relation]) async throws -> [Relation] {
        var graph = try await loadGraph()
        var newRelations: [Relation] = []

        for relation in relations {
            if !graph.relations.contains(where: {
                $0.from == relation.from && $0.to == relation.to && $0.relationType == relation.relationType
            }) {
                graph.relations.append(relation)
                newRelations.append(relation)
            }
        }

        try await saveGraph(graph)
        return newRelations
    }

    /// Adds observations to existing entities
    func addObservations(_ observations: [ObservationAddition]) async throws -> [ObservationResult] {
        var graph = try await loadGraph()
        var results: [ObservationResult] = []

        for addition in observations {
            if let entityIndex = graph.entities.firstIndex(where: { $0.name == addition.entityName }) {
                var addedObservations: [String] = []

                for content in addition.contents {
                    if !graph.entities[entityIndex].observations.contains(content) {
                        graph.entities[entityIndex].observations.append(content)
                        addedObservations.append(content)
                    }
                }

                results.append(ObservationResult(entityName: addition.entityName, addedObservations: addedObservations))
            } else {
                throw ToolError(message: "Entity with name \(addition.entityName) not found")
            }
        }

        try await saveGraph(graph)
        return results
    }

    /// Deletes entities and their associated relations
    func deleteEntities(_ entityNames: [String]) async throws {
        var graph = try await loadGraph()

        graph.entities.removeAll(where: { entityNames.contains($0.name) })
        graph.relations.removeAll(where: { entityNames.contains($0.from) || entityNames.contains($0.to) })

        try await saveGraph(graph)
    }

    /// Deletes specific observations from entities
    func deleteObservations(_ deletions: [ObservationDeletion]) async throws {
        var graph = try await loadGraph()

        for deletion in deletions {
            if let entityIndex = graph.entities.firstIndex(where: { $0.name == deletion.entityName }) {
                graph.entities[entityIndex].observations.removeAll(where: { deletion.observations.contains($0) })
            }
        }

        try await saveGraph(graph)
    }

    /// Deletes relations from the knowledge graph
    func deleteRelations(_ relations: [Relation]) async throws {
        var graph = try await loadGraph()

        graph.relations.removeAll(where: { relation in
            relations.contains(where: {
                $0.from == relation.from && $0.to == relation.to && $0.relationType == relation.relationType
            })
        })

        try await saveGraph(graph)
    }

    /// Reads the entire knowledge graph
    func readGraph() async throws -> KnowledgeGraph {
        return try await loadGraph()
    }

    /// Searches for nodes in the knowledge graph
    func searchNodes(_ query: String) async throws -> KnowledgeGraph {
        let graph = try await loadGraph()
        let lowercaseQuery = query.lowercased()

        // Filter entities
        let filteredEntities = graph.entities.filter { entity in
            entity.name.lowercased().contains(lowercaseQuery) || entity.entityType.lowercased().contains(lowercaseQuery)
                || entity.observations.contains(where: { $0.lowercased().contains(lowercaseQuery) })
        }

        // Get entity names for quick lookup
        let filteredEntityNames = Set(filteredEntities.map { $0.name })

        // Filter relations to only include those between filtered entities
        let filteredRelations = graph.relations.filter { relation in
            filteredEntityNames.contains(relation.from) && filteredEntityNames.contains(relation.to)
        }

        return KnowledgeGraph(entities: filteredEntities, relations: filteredRelations)
    }

    /// Opens specific nodes by their names
    func openNodes(_ names: [String]) async throws -> KnowledgeGraph {
        let graph = try await loadGraph()

        // Filter entities
        let filteredEntities = graph.entities.filter { entity in
            names.contains(entity.name)
        }

        // Get entity names for quick lookup
        let filteredEntityNames = Set(filteredEntities.map { $0.name })

        // Filter relations to only include those between filtered entities
        let filteredRelations = graph.relations.filter { relation in
            filteredEntityNames.contains(relation.from) && filteredEntityNames.contains(relation.to)
        }

        return KnowledgeGraph(entities: filteredEntities, relations: filteredRelations)
    }
}

// Create a singleton instance of the knowledge graph manager
let knowledgeGraphManager = KnowledgeGraphManager()

// MARK: - Memory Tool Input/Output Types

/// Input for creating entities
@Schemable
struct CreateEntitiesInput {
    @SchemaOptions(
        description: "An array of entities to create"
    )
    let entities: [Entity]
}

/// Input for creating relations
@Schemable
struct CreateRelationsInput {
    @SchemaOptions(
        description: "An array of relations to create"
    )
    let relations: [Relation]
}

/// Input structure for adding observations to entities
@Schemable
struct ObservationAddition: Codable {
    @SchemaOptions(
        description: "The name of the entity to add the observations to"
    )
    let entityName: String

    @SchemaOptions(
        description: "An array of observation contents to add"
    )
    let contents: [String]
}

/// Result structure for added observations
struct ObservationResult: Codable {
    let entityName: String
    let addedObservations: [String]
}

/// Input for adding observations
@Schemable
struct AddObservationsInput {
    @SchemaOptions(
        description: "An array of observations to add to entities"
    )
    let observations: [ObservationAddition]
}

/// Input for deleting entities
@Schemable
struct DeleteEntitiesInput {
    @SchemaOptions(
        description: "An array of entity names to delete"
    )
    let entityNames: [String]
}

/// Input structure for deleting observations from entities
@Schemable
struct ObservationDeletion: Codable {
    @SchemaOptions(
        description: "The name of the entity containing the observations"
    )
    let entityName: String

    @SchemaOptions(
        description: "An array of observations to delete"
    )
    let observations: [String]
}

/// Input for deleting observations
@Schemable
struct DeleteObservationsInput {
    @SchemaOptions(
        description: "An array of observations to delete from entities"
    )
    let deletions: [ObservationDeletion]
}

/// Input for deleting relations
@Schemable
struct DeleteRelationsInput {
    @SchemaOptions(
        description: "An array of relations to delete"
    )
    let relations: [Relation]
}

/// Input for reading the graph (dummy parameter for consistency)
@Schemable
struct ReadGraphInput {
    @SchemaOptions(
        description: "Dummy parameter for no-parameter tools"
    )
    let random_string: String?
}

/// Input for searching nodes
@Schemable
struct SearchNodesInput {
    @SchemaOptions(
        description: "The search query to match against entity names, types, and observation content"
    )
    let query: String
}

/// Input for opening nodes
@Schemable
struct OpenNodesInput {
    @SchemaOptions(
        description: "An array of entity names to retrieve"
    )
    let names: [String]
}

// MARK: - Memory Knowledge Graph Tools

/// Tool for creating new entities
let createEntitiesTool = Tool(
    name: "create_entities",
    description: "Create multiple new entities in the knowledge graph"
) { (input: CreateEntitiesInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        let newEntities = try await knowledgeGraphManager.createEntities(input.entities)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(newEntities)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        return [.text(TextContent(text: jsonString))]
    } catch {
        mcpLogger.error("Failed to create entities: \(error)")
        throw error
    }
}

/// Tool for creating new relations
let createRelationsTool = Tool(
    name: "create_relations",
    description:
        "Create multiple new relations between entities in the knowledge graph. Relations should be in active voice"
) { (input: CreateRelationsInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        let newRelations = try await knowledgeGraphManager.createRelations(input.relations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(newRelations)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        return [.text(TextContent(text: jsonString))]
    } catch {
        mcpLogger.error("Failed to create relations: \(error)")
        throw error
    }
}

/// Tool for adding observations to entities
let addObservationsTool = Tool(
    name: "add_observations",
    description: "Add new observations to existing entities in the knowledge graph"
) { (input: AddObservationsInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        let results = try await knowledgeGraphManager.addObservations(input.observations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(results)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        return [.text(TextContent(text: jsonString))]
    } catch {
        mcpLogger.error("Failed to add observations: \(error)")
        throw error
    }
}

/// Tool for deleting entities
let deleteEntitiesTool = Tool(
    name: "delete_entities",
    description: "Delete multiple entities and their associated relations from the knowledge graph"
) { (input: DeleteEntitiesInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        try await knowledgeGraphManager.deleteEntities(input.entityNames)
        return [.text(TextContent(text: "Entities deleted successfully"))]
    } catch {
        mcpLogger.error("Failed to delete entities: \(error)")
        throw error
    }
}

/// Tool for deleting observations
let deleteObservationsTool = Tool(
    name: "delete_observations",
    description: "Delete specific observations from entities in the knowledge graph"
) { (input: DeleteObservationsInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        try await knowledgeGraphManager.deleteObservations(input.deletions)
        return [.text(TextContent(text: "Observations deleted successfully"))]
    } catch {
        mcpLogger.error("Failed to delete observations: \(error)")
        throw error
    }
}

/// Tool for deleting relations
let deleteRelationsTool = Tool(
    name: "delete_relations",
    description: "Delete multiple relations from the knowledge graph"
) { (input: DeleteRelationsInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        try await knowledgeGraphManager.deleteRelations(input.relations)
        return [.text(TextContent(text: "Relations deleted successfully"))]
    } catch {
        mcpLogger.error("Failed to delete relations: \(error)")
        throw error
    }
}

/// Tool for reading the entire knowledge graph
let readGraphTool = Tool(
    name: "read_graph",
    description: "Read the entire knowledge graph"
) { (_: ReadGraphInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        let graph = try await knowledgeGraphManager.readGraph()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(graph)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"entities\": [], \"relations\": []}"
        return [.text(TextContent(text: jsonString))]
    } catch {
        mcpLogger.error("Failed to read graph: \(error)")
        throw error
    }
}

/// Tool for searching nodes in the knowledge graph
let searchNodesTool = Tool(
    name: "search_nodes",
    description: "Search for nodes in the knowledge graph based on a query"
) { (input: SearchNodesInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        let result = try await knowledgeGraphManager.searchNodes(input.query)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"entities\": [], \"relations\": []}"
        return [.text(TextContent(text: jsonString))]
    } catch {
        mcpLogger.error("Failed to search nodes: \(error)")
        throw error
    }
}

/// Tool for opening specific nodes in the knowledge graph
let openNodesTool = Tool(
    name: "open_nodes",
    description: "Open specific nodes in the knowledge graph by their names"
) { (input: OpenNodesInput) async throws -> [TextContentOrImageContentOrEmbeddedResource] in
    do {
        let result = try await knowledgeGraphManager.openNodes(input.names)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"entities\": [], \"relations\": []}"
        return [.text(TextContent(text: jsonString))]
    } catch {
        mcpLogger.error("Failed to open nodes: \(error)")
        throw error
    }
}
