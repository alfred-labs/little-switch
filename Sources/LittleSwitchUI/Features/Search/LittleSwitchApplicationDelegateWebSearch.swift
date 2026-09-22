extension LittleSwitchApplicationDelegate {
    func setWebSearchDraft(_ input: WebSearchPendingSettings?) {
        // Quit/disconnect can ask for pending changes before an actor call runs.
        guard let coordinator else {
            model.webSearchDraft = input
            return
        }
        let publication = model.beginWebSearchDraftPublication(input)
        let previous = webSearchDraftTask
        webSearchDraftTask = Task {
            await previous?.value
            let snapshot = await coordinator.setWebSearchDraft(input)
            model.completeWebSearchDraftPublication(publication, snapshot: snapshot)
        }
    }

    func saveWebSearch(_ input: WebSearchInput) async -> Bool {
        let draftTask = webSearchDraftTask
        return await perform {
            await draftTask?.value
            return try await $0.saveWebSearch(input)
        }
    }
}
