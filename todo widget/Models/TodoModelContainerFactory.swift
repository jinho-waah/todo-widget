import Foundation
import SwiftData

enum TodoModelContainerFactory {
    static func make() -> ModelContainer {
        let schema = Schema(versionedSchema: TodoSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        if let container = try? ModelContainer(
            for: schema,
            migrationPlan: TodoMigrationPlan.self,
            configurations: [config]
        ) {
            return container
        }

        try? FileManager.default.removeItem(at: config.url)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
