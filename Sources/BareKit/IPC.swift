// IPC.swift
// Mirrors the BareIPC ObjC API from bare-kit/apple/BareKit/BareKit.h

import CBareKit
import Foundation

// ── C callback box — carries Swift closure through void* ──────────────────────

private final class IPCCallbackBox {
    let onReadable: (Data) -> Void
    init(_ cb: @escaping (Data) -> Void) { self.onReadable = cb }
}

// ── Top-level C-compatible poll callback ──────────────────────────────────────

private func ipcPollCallback(
    _ pollPtr: UnsafeMutablePointer<bare_ipc_poll_t>?,
    _ events: Int32
) {
    guard let pollPtr = pollPtr else { return }
    guard (events & Int32(bare_ipc_readable)) != 0 else { return }

    let rawCtx = bare_ipc_poll_get_data(pollPtr)!
    let box = Unmanaged<IPCCallbackBox>.fromOpaque(rawCtx).takeUnretainedValue()
    let ipcPtr = bare_ipc_poll_get_ipc(pollPtr)!

    var rawPtr: UnsafeMutableRawPointer? = nil
    var len: Int = 0
    while bare_ipc_read(ipcPtr, &rawPtr, &len) == 0, let ptr = rawPtr, len > 0 {
        box.onReadable(Data(bytes: ptr, count: len))
    }
}

// ── IPC ───────────────────────────────────────────────────────────────────────

public final class IPC {

    /// Called when JS writes data.
    /// The callback fires on bare-kit's epoll thread — dispatch to main
    /// thread yourself if needed for UI updates.
    public var readable: ((Data) -> Void)? {
        didSet { if readable != nil { startPolling() } }
    }

    private var ipc:            UnsafeMutablePointer<bare_ipc_t>?      = nil
    private var poll:           UnsafeMutablePointer<bare_ipc_poll_t>? = nil
    private var box:            Unmanaged<IPCCallbackBox>?              = nil
    private var pollingStarted: Bool                                    = false

    // ── Init ──────────────────────────────────────────────────────────────────
    // Must be called AFTER worklet.start() returns.
    // bare_worklet_start() blocks until the JS thread sets incoming/outgoing
    // pipe fds — so they are guaranteed valid when this init runs.

    public init(worklet: Worklet) {
        guard let wHandle = worklet.handle else {
            print("[BareKit] IPC init failed — call worklet.start() first")
            return
        }

        bare_ipc_alloc(&ipc)
        bare_ipc_init(ipc, wHandle)
        bare_ipc_poll_alloc(&poll)
        bare_ipc_poll_init(poll, ipc)
    }

    // ── Write ─────────────────────────────────────────────────────────────────

    public func write(_ data: Data) {
        guard let ipc = ipc else { return }
        var bytes = Array(data).map { Int8(bitPattern: $0) }
        bytes.withUnsafeMutableBufferPointer { buf in
            _ = bare_ipc_write(ipc, buf.baseAddress, buf.count)
        }
    }

    public func write(_ string: String) {
        write(Data(string.utf8))
    }

    // ── Read — synchronous ────────────────────────────────────────────────────

    public func read() -> Data? {
        guard let ipc = ipc else { return nil }
        var rawPtr: UnsafeMutableRawPointer? = nil
        var len: Int = 0
        guard bare_ipc_read(ipc, &rawPtr, &len) == 0,
              let ptr = rawPtr, len > 0 else { return nil }
        return Data(bytes: ptr, count: len)
    }

    // ── Close ─────────────────────────────────────────────────────────────────

    public func close() {
        if let poll = poll { bare_ipc_poll_destroy(poll); free(poll) }
        if let ipc  = ipc  { bare_ipc_destroy(ipc);       free(ipc)  }
        box?.release()
        self.poll = nil
        self.ipc  = nil
        self.box  = nil
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func startPolling() {
        guard !pollingStarted, let poll = poll, let ipc = ipc,
              let onReadable = readable else { return }
        pollingStarted = true

        let callbackBox = IPCCallbackBox(onReadable)
        box = Unmanaged.passRetained(callbackBox)
        bare_ipc_poll_set_data(poll, box!.toOpaque())
        bare_ipc_poll_start(poll, Int32(bare_ipc_readable), ipcPollCallback)

        // Drain data JS already wrote before poll was set up
        var rawPtr: UnsafeMutableRawPointer? = nil
        var len: Int = 0
        while bare_ipc_read(ipc, &rawPtr, &len) == 0, let ptr = rawPtr, len > 0 {
            onReadable(Data(bytes: ptr, count: len))
        }
    }

    deinit { close() }
}