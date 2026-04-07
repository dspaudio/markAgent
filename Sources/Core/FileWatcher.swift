@preconcurrency import Foundation

// FileWatcher는 DispatchSource를 사용하여 단일 파일을 감시한다.
// Swift 6 strict concurrency를 준수하기 위해 actor로 구현한다.
actor FileWatcher {
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    private let debounceInterval: TimeInterval = 0.2

    // 파일 변경 시 MainActor에서 호출할 콜백
    private let onChange: @MainActor @Sendable () -> Void

    init(onChange: @MainActor @Sendable @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        // deinit은 actor-isolated 메서드를 호출할 수 없으므로 직접 정리한다.
        debounceWorkItem?.cancel()
        source?.cancel()
        if fileDescriptor != -1 {
            close(fileDescriptor)
        }
    }

    // 지정된 URL의 파일 감시를 시작한다.
    func startWatching(url: URL) {
        stopWatching()
        openAndWatch(url: url)
    }

    // 파일 감시를 중단하고 리소스를 해제한다.
    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        source?.cancel()
        source = nil

        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // 파일 디스크립터를 열고 DispatchSource를 등록한다.
    private func openAndWatch(url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else { return }

        fileDescriptor = fd

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )

        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.handleEvent(url: url)
            }
        }

        newSource.setCancelHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.closeDescriptorIfCurrent(fd)
            }
        }

        source = newSource
        newSource.resume()
    }

    // DispatchSource 이벤트를 처리한다.
    private func handleEvent(url: URL) {
        guard let currentSource = source else { return }

        let eventData = currentSource.data

        if eventData.contains(.delete) || eventData.contains(.rename) {
            // 파일이 삭제되거나 이름이 변경된 경우: 소스를 취소하고 재오픈 시도
            source?.cancel()
            source = nil

            // 짧은 지연 후 파일이 다시 생겼는지 확인 (에디터의 atomic save 등 대응)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task {
                    await self.retryOpen(url: url)
                }
            }
            debounceWorkItem?.cancel()
            debounceWorkItem = workItem
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + debounceInterval,
                execute: workItem
            )
        } else {
            // .write / .extend: 디바운싱 후 콜백 호출
            scheduleCallback()
        }
    }

    // 디바운싱을 적용해 onChange 콜백을 예약한다.
    private func scheduleCallback() {
        debounceWorkItem?.cancel()

        let callback = onChange
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                callback()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }

    // 파일 삭제 후 재오픈을 시도한다.
    private func retryOpen(url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            openAndWatch(url: url)
            scheduleCallback()
        } else {
            // 파일이 없으면 onChange를 호출해 Document에 에러 상태를 반영한다.
            let callback = onChange
            Task { @MainActor in
                callback()
            }
        }
    }

    // cancel handler에서 파일 디스크립터를 안전하게 닫는다.
    private func closeDescriptorIfCurrent(_ fd: CInt) {
        if fileDescriptor == fd {
            close(fd)
            fileDescriptor = -1
        }
    }
}
