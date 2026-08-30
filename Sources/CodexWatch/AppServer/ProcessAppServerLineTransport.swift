import Foundation

actor ProcessAppServerLineTransport: AppServerLineTransport {
    private let executableURL: URL
    private let maximumLineBytes: Int
    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var readerTask: Task<Void, Never>?

    init(
        executableURL: URL,
        maximumLineBytes: Int = CodexAppServerClient.maximumLineBytes
    ) {
        self.executableURL = executableURL
        self.maximumLineBytes = maximumLineBytes
    }

    init(
        locator: CodexExecutableLocator,
        maximumLineBytes: Int = CodexAppServerClient.maximumLineBytes
    ) throws {
        self.init(
            executableURL: try locator.locate(),
            maximumLineBytes: maximumLineBytes
        )
    }

    func start(
        receiveLine: @escaping @Sendable (Data) async -> Void,
        termination: @escaping @Sendable (Error?) async -> Void
    ) async throws {
        guard process == nil else {
            throw AppServerError.transportFailure
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let child = Process()
        child.executableURL = executableURL
        child.arguments = ["app-server"]
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
        } catch {
            throw AppServerError.transportFailure
        }

        let input = inputPipe.fileHandleForWriting
        let output = outputPipe.fileHandleForReading
        process = child
        standardInput = input
        standardOutput = output
        readerTask = Task.detached(priority: .utility) { [maximumLineBytes] in
            await Self.readLines(
                from: output,
                maximumLineBytes: maximumLineBytes,
                receiveLine: receiveLine,
                termination: termination
            )
        }
    }

    func send(_ line: Data) async throws {
        guard line.count <= maximumLineBytes,
              let standardInput,
              process?.isRunning == true else {
            throw AppServerError.transportFailure
        }
        var framedLine = line
        framedLine.append(0x0A)
        do {
            try standardInput.write(contentsOf: framedLine)
        } catch {
            throw AppServerError.transportFailure
        }
    }

    func stop() async {
        readerTask?.cancel()
        readerTask = nil

        try? standardInput?.close()
        standardInput = nil
        try? standardOutput?.close()
        standardOutput = nil

        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
    }

    private nonisolated static func readLines(
        from handle: FileHandle,
        maximumLineBytes: Int,
        receiveLine: @escaping @Sendable (Data) async -> Void,
        termination: @escaping @Sendable (Error?) async -> Void
    ) async {
        var buffer = Data()
        do {
            while !Task.isCancelled {
                let remainingThroughDetectionByte = maximumLineBytes - buffer.count + 1
                guard remainingThroughDetectionByte > 0 else {
                    await termination(AppServerError.lineTooLarge(maxBytes: maximumLineBytes))
                    return
                }
                let readCount = min(64 * 1_024, remainingThroughDetectionByte)
                guard let chunk = try handle.read(upToCount: readCount), !chunk.isEmpty else {
                    if !buffer.isEmpty {
                        await receiveLine(strippingCarriageReturn(from: buffer))
                    }
                    await termination(nil)
                    return
                }
                buffer.append(chunk)

                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newlineIndex])
                    buffer.removeSubrange(...newlineIndex)
                    let normalized = strippingCarriageReturn(from: line)
                    guard normalized.count <= maximumLineBytes else {
                        await termination(
                            AppServerError.lineTooLarge(maxBytes: maximumLineBytes)
                        )
                        return
                    }
                    await receiveLine(normalized)
                }

                guard buffer.count <= maximumLineBytes else {
                    await termination(AppServerError.lineTooLarge(maxBytes: maximumLineBytes))
                    return
                }
            }
        } catch {
            if !Task.isCancelled {
                await termination(AppServerError.transportFailure)
            }
        }
    }

    private nonisolated static func strippingCarriageReturn(from data: Data) -> Data {
        guard data.last == 0x0D else { return data }
        return data.dropLast()
    }
}
