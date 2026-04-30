import Foundation
import SwiftData

// MARK: - Versioned Schema
//
// SwiftData 스키마를 버저닝해 후속 변경 시 lightweight/custom migration 을 끼워 넣을
// 수 있게 한다. 현재는 V1 만 존재하므로 stages 는 비어 있다.
//
// 새 스키마를 추가할 때 절차:
//   1) 변경된 모델 정의를 담은 enum TodoSchemaV2 추가 (또는 모델을 enum 내부에 nest).
//   2) `TodoMigrationPlan.schemas` 에 V2 를 추가하고 V1 → V2 stage 정의.
//   3) ModelContainer init 호출부는 자동으로 plan 을 따른다.
//
// 마지막 수단으로 todo_widgetApp.swift 에 store 삭제 fallback 이 있지만, 이는 진짜
// 복구 불가능한 corruption 일 때만 발동해야 한다.

enum TodoSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Todo.self, SubTodo.self]
    }
}

enum TodoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TodoSchemaV1.self]
    }
    static var stages: [MigrationStage] {
        []
    }
}
