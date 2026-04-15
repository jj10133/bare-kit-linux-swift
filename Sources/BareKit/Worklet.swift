// Worklet.swift
// Mirrors the BareWorklet ObjC API from bare-kit/apple/BareKit/BareKit.h

import CBareKit
import Foundation

public final class Worklet {

    // ── Configuration ─────────────────────────────────────────────────────────

    public struct Configuration {
        /// Memory limit for the JS heap in bytes. Default: 32 MiB.
        public var memoryLimit: Int = 32 * 1024 * 1024

        /// Directory for worklet assets. nil = no assets.
        public var assets: String? = nil

        public init() {}
    }

    // ── Internal state ────────────────────────────────────────────────────────

    internal var handle: UnsafeMutablePointer<bare_worklet_t>? = nil
    private var config: Configuration
    private var sourceBuffer: [Int8] = []  // keeps source alive

    // ── Init ──────────────────────────────────────────────────────────────────

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    // ── Start ─────────────────────────────────────────────────────────────────

    /// Start the worklet loading JS from a file path.
    /// The file can be a plain .js file or a .bundle produced by bare-pack.
    public func start(_ filename: String, arguments: [String] = []) {
        _start(filename: filename, source: nil, arguments: arguments)
    }

    /// Start the worklet with inline JS source.
    public func start(
        _ filename: String, source: String,
        arguments: [String] = []
    ) {
        _start(filename: filename, source: source, arguments: arguments)
    }

    /// Start the worklet with raw Data source (e.g. loaded bundle).
    public func start(
        _ filename: String, source: Data,
        arguments: [String] = []
    ) {
        let str = String(data: source, encoding: .utf8) ?? ""
        _start(filename: filename, source: str, arguments: arguments)
    }

    // ── Lifecycle — matches bare-ios API exactly ───────────────────────────────

    /// Suspend the worklet. linger: ms to keep process alive before exit.
    public func suspend(linger: Int = 0) {
        guard let h = handle else { return }
        bare_worklet_suspend(h, Int32(linger))
    }

    public func resume() {
        guard let h = handle else { return }
        bare_worklet_resume(h)
    }

    public func terminate() {
        guard let h = handle else { return }
        bare_worklet_terminate(h)
        handle = nil
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func _start(
        filename: String, source: String?,
        arguments: [String]
    ) {
        // Alloc
        bare_worklet_alloc(&handle)

        // Options
        var opts = bare_worklet_options_t()
        opts.memory_limit = config.memoryLimit
        if let assets = config.assets {
            // Keep assets path alive — stored as C string in opts
            // (assets is short-lived here; full solution needs a stored copy)
            assets.withCString {
                opts.assets = $0
                bare_worklet_init(handle, &opts)
            }
        } else {
            bare_worklet_init(handle, &opts)
        }

        // Source buffer
        var uvBuf: uv_buf_t
        if let src = source {
            sourceBuffer = Array(src.utf8).map { Int8(bitPattern: $0) }
            uvBuf = sourceBuffer.withUnsafeMutableBufferPointer { buf in
                uv_buf_init(buf.baseAddress, UInt32(buf.count))
            }
        } else {
            uvBuf = uv_buf_init(nil, 0)
        }

        // Arguments
        var cArgs: [UnsafePointer<CChar>?] = arguments.map {
            strdup($0)
        }
        defer { cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }

        filename.withCString { path in
            _ = bare_worklet_start(
                handle, path,
                source != nil ? &uvBuf : nil,
                Int32(arguments.count),
                cArgs.isEmpty ? nil : &cArgs
            )
        }
    }

    deinit {
        if let h = handle {
            bare_worklet_destroy(h)
            free(h)
        }
    }
}
