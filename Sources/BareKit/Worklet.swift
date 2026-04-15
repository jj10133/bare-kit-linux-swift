import CBareKit
import Foundation

public final class Worklet {

    public struct Configuration {
        public var memoryLimit: Int = 32 * 1024 * 1024
        public var assets: String? = nil
        public init() {}
    }

    internal var handle: UnsafeMutablePointer<bare_worklet_t>? = nil
    private var config: Configuration
    private var sourceBuffer: [Int8] = []

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    public func start(_ filename: String, arguments: [String] = []) {
        _start(filename: filename, source: nil, arguments: arguments)
    }

    public func start(_ filename: String, source: String, arguments: [String] = []) {
        _start(filename: filename, source: source, arguments: arguments)
    }

    public func start(_ filename: String, source: Data, arguments: [String] = []) {
        _start(filename: filename,
               source: String(data: source, encoding: .utf8) ?? "",
               arguments: arguments)
    }

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

    private func _start(filename: String, source: String?, arguments: [String]) {
        bare_worklet_alloc(&handle)

        var opts = bare_worklet_options_t()
        opts.memory_limit = config.memoryLimit
        opts.assets = nil

        if let assets = config.assets {
            assets.withCString { ptr in
                opts.assets = ptr
                bare_worklet_init(handle, &opts)
            }
        } else {
            bare_worklet_init(handle, &opts)
        }

        if let src = source {
            sourceBuffer = Array(src.utf8).map { Int8(bitPattern: $0) }
        }

        // Recursive helper — keeps all CStrings alive on the stack
        func run(remaining: [String], ptrs: [UnsafePointer<CChar>?]) {
            if remaining.isEmpty {
                var argv = ptrs
                filename.withCString { path in
                    if source != nil {
                        sourceBuffer.withUnsafeMutableBufferPointer { buf in
                            var uvBuf = uv_buf_init(buf.baseAddress, UInt32(buf.count))
                            if argv.isEmpty {
                                _ = bare_worklet_start(handle, path, &uvBuf, 0, nil)
                            } else {
                                _ = bare_worklet_start(handle, path, &uvBuf,
                                                       Int32(argv.count), &argv)
                            }
                        }
                    } else {
                        if argv.isEmpty {
                            _ = bare_worklet_start(handle, path, nil, 0, nil)
                        } else {
                            _ = bare_worklet_start(handle, path, nil,
                                                   Int32(argv.count), &argv)
                        }
                    }
                }
            } else {
                remaining[0].withCString { ptr in
                    run(remaining: Array(remaining.dropFirst()),
                        ptrs: ptrs + [UnsafePointer<CChar>(ptr)])
                }
            }
        }

        run(remaining: arguments, ptrs: [])
    }

    deinit {
        if let h = handle {
            bare_worklet_destroy(h)
            free(h)
        }
    }
}