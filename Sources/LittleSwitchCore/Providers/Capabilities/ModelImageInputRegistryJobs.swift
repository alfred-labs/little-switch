import Foundation
import LittleSwitchCommon

extension ModelImageInputRegistry {
    package func probeIfNeeded(
        provider: Provider,
        model: DiscoveredModel,
        wire: ModelImageInputWire,
        secret: String?,
        generation: UUID? = nil
    ) async throws -> ModelImageInputProbeResult? {
        if let generation, contexts[provider.id]?.generation != generation {
            throw GatewayAdmissionError.invalidated
        }
        let waiterID = UUID()
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await enqueue(provider: provider, model: model, wire: wire, secret: secret, waiterID: waiterID)
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
        try Task.checkCancellation()
        return result
    }

    private func enqueue(
        provider: Provider, model: DiscoveredModel, wire: ModelImageInputWire, secret: String?, waiterID: UUID
    ) async throws -> ModelImageInputProbeResult? {
        try Task.checkCancellation()
        guard !stopped, let context = contexts[provider.id],
            context.provider.hasSameImageInputIdentity(as: provider)
        else { throw GatewayAdmissionError.invalidated }
        let key = try ModelImageInputPolicyResolver.key(provider: provider, modelID: model.id, wire: wire)
        guard context.validKeys.contains(key) else { throw GatewayAdmissionError.invalidated }
        // The diagnostic is optional. A burst must not retain unbounded callers or
        // credentials before they reach the separately bounded business admission.
        guard waiterCount < Self.maximumWaiters else { return nil }
        guard
            try candidates(provider: context.provider, preferredModelIDs: [], wire: wire, limit: Int.max)
                .contains(where: { $0.id == model.id })
        else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            if let id = jobsByKey[key], var job = jobs[id] {
                job.waiters[waiterID] = continuation
                jobs[id] = job
            } else {
                let id = UUID()
                jobs[id] = Job(
                    key: key,
                    provider: provider,
                    model: model,
                    generation: context.generation,
                    secret: secret,
                    waiters: [waiterID: continuation])
                jobsByKey[key] = id
                queue.append((id: id, providerID: provider.id))
            }
            startAvailableJobs()
        }
    }

    private func startAvailableJobs() {
        guard !stopped else { return }
        var active = jobs.values.filter { $0.task != nil }
        while active.count < 2 {
            let busyProviders = Set(active.map(\.key.providerID))
            guard
                let index = queue.firstIndex(where: { !busyProviders.contains($0.providerID) })
            else { return }
            let id = queue.remove(at: index).id
            guard var job = jobs[id] else { continue }
            let request = job
            job.task = Task { await self.run(request, id: id) }
            jobs[id] = job
            active.append(job)
        }
    }

    private func run(_ job: Job, id: UUID) async {
        let result: Result<ModelImageInputProbeResult, any Error>
        do {
            try Task.checkCancellation()
            try await admission.admit(eventID: id, provider: job.provider, modelID: job.model.id)
            do {
                try Task.checkCancellation()
                let value = try await prober.probe(
                    provider: job.provider, model: job.model, wire: job.key.wire, secret: job.secret)
                try Task.checkCancellation()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            await admission.finish(eventID: id)
        } catch {
            result = .failure(error)
        }
        await complete(id: id, result: result)
    }

    private func complete(id: UUID, result: Result<ModelImageInputProbeResult, any Error>) async {
        guard let job = jobs.removeValue(forKey: id) else { return }
        if jobsByKey[job.key] == id { jobsByKey[job.key] = nil }
        defer { startAvailableJobs() }
        var result = result
        if !isCurrent(job.key, generation: job.generation) || job.waiters.isEmpty {
            result = .failure(CancellationError())
        }
        if case .success(let value) = result {
            switch value.outcome {
            case .verified, .unsupported:
                await record(
                    ModelImageInputObservation(
                        key: job.key,
                        verdict: value.outcome == .verified ? .verified : .unsupported,
                        source: .visualProbe,
                        observedAt: now()), generation: job.generation)
            case .inconclusive:
                cooldowns[job.key] = now().addingTimeInterval(ModelImageProbeSchedule.inconclusiveCooldown)
            }
            if isCurrent(job.key, generation: job.generation) {
                let diagnostic = ModelImageInputProbeDiagnostic(key: job.key, result: value)
                await onDiagnostic(diagnostic, job.generation)
            }
        }
        if !isCurrent(job.key, generation: job.generation) { result = .failure(CancellationError()) }
        for waiter in job.waiters.values { waiter.resume(with: result.map(Optional.some)) }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        for (id, var job) in jobs {
            guard let waiter = job.waiters.removeValue(forKey: waiterID) else { continue }
            jobs[id] = job
            waiter.resume(throwing: CancellationError())
            if job.waiters.isEmpty { cancelJob(id) }
            return
        }
    }

    func cancelJob(_ id: UUID) {
        guard var job = jobs[id] else { return }
        job.task?.cancel()
        for waiter in job.waiters.values { waiter.resume(throwing: CancellationError()) }
        job.waiters.removeAll()
        if jobsByKey[job.key] == id { jobsByKey[job.key] = nil }
        queue.removeAll { $0.id == id }
        jobs[id] = job.task == nil ? nil : job
    }
}
