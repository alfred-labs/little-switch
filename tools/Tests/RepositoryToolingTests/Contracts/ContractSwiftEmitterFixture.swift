@testable import RepositoryTooling

enum ContractSwiftEmitter {
    static func emit(graph: ContractGraph) throws -> [GeneratedContractFile] {
        var emitter = ContractEmitter(graph: graph)
        return try emitter.emit()
    }
}
