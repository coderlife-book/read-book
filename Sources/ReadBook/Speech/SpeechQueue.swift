actor SpeechQueue {
    let lowWatermark: Int
    let targetCount: Int
    let hardLimit: Int

    private var generationValue: UInt64 = 0
    private var pending: [PreparedSentence] = []

    init(lowWatermark: Int = 10, targetCount: Int = 20, hardLimit: Int = 30) {
        precondition(lowWatermark >= 0)
        precondition(targetCount >= lowWatermark)
        precondition(hardLimit >= targetCount)
        self.lowWatermark = lowWatermark
        self.targetCount = targetCount
        self.hardLimit = hardLimit
    }

    var currentGeneration: SpeechGenerationID {
        SpeechGenerationID(rawValue: generationValue)
    }

    var count: Int { pending.count }
    var needsRefill: Bool { pending.count <= lowWatermark }
    var requestedCapacity: Int { max(targetCount - pending.count, 0) }

    func restart() -> SpeechGenerationID {
        generationValue &+= 1
        pending.removeAll(keepingCapacity: true)
        return currentGeneration
    }

    func append(
        _ sentences: [PreparedSentence],
        generation: SpeechGenerationID
    ) {
        guard generation == currentGeneration else { return }
        let available = max(hardLimit - pending.count, 0)
        pending.append(contentsOf: sentences.prefix(available))
    }

    func popFirst() -> PreparedSentence? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}
