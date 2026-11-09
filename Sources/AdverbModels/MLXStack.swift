//
//  MLXStack.swift
//  AdverbModels
//
//  WHAT: MLX's kernels beside the running binary, and the GPU's limits. Lifted from Craft
//        (CraftMLX/MLXStack), unchanged but for the names.
//

import Darwin
import Foundation
import AdverbCore
import MLX



/// Where MLX looks for its Metal kernels: `mlx.metallib` beside the RUNNING binary.
/// PIN: Frigate emits `Frigate_Cmlx.bundle`, which MLX never probes (it looks for
/// `mlx-swift_Cmlx.bundle`, Frigate's Package.swift:214), so the only rung that works is
/// the file next to the executable, installed by scripts/build-metallib.sh.
/// `ensureMetallib` copies it out of that bundle when the build made one, so a plain
/// `swift build` + run works without the script; see its own comment for the limits.
public enum MLXStack {
    /// The directory MLX probes. PIN: MLX resolves it with `dladdr` on one of its own
    /// symbols (`current_binary_dir()`), NOT `Bundle.main`: under `xctest` the main
    /// bundle is the test host while MLX looks inside the `.xctest`. Cmlx is statically
    /// linked into the same image as this module, so a local anchor gives the same answer.
    public static var binaryDirectory: URL? {
        var info = Dl_info()
        let anchor = unsafeBitCast(adverbMLXAnchor as @convention(c) () -> Void, to: UnsafeRawPointer.self)
        guard dladdr(anchor, &info) != 0, let name = info.dli_fname else { return nil }
        return URL(fileURLWithPath: String(cString: name)).deletingLastPathComponent()
    }

    public static var metallibURL: URL? {
        binaryDirectory?.appendingPathComponent("mlx.metallib")
    }

    public static var isMetallibPresent: Bool {
        guard let directory = binaryDirectory else { return false }
        return metallibPresent(in: directory)
    }

    /// The rule, separated from where the binary happens to live.
    public static func metallibPresent(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("mlx.metallib").path)
    }

    public static let fixHint =
        "no mlx.metallib beside the binary — run ./Scripts/build-metallib.sh [debug|release] and retry"

    // MARK: - Self-heal

    /// The resource bundle Frigate's Cmlx target ships its compiled shaders in. The
    /// second name is upstream mlx-swift's, for a build made against that package.
    static let shaderBundleNames = ["Frigate_Cmlx", "mlx-swift_Cmlx"]

    /// Installs the metallib beside the running binary when it is missing, taking it from
    /// Frigate's resource bundle. Returns whether one is there afterwards.
    /// PIN: only into a plain directory — a `.build` product. Never into an `.app`,
    /// `.xctest` or `.framework`: codesign seals everything under `Contents/MacOS` as
    /// nested code, so an unsigned file dropped in at runtime breaks the next load or
    /// re-sign (which is exactly why build-metallib.sh signs and re-seals). There is
    /// nothing to copy unless the build compiled the shaders into the bundle: the default
    /// build system does, `--build-system native` does not.
    @discardableResult
    public static func ensureMetallib() -> Bool {
        guard let directory = binaryDirectory else { return false }
        if metallibPresent(in: directory) { return true }
        guard !isInsideSealedBundle(directory), let source = bundledMetallib() else { return false }
        return install(from: source, into: directory)
    }

    /// Copies `source` to `<directory>/mlx.metallib` when there isn't one already.
    /// Returns whether one is there afterwards; an unwritable directory is a false, not a
    /// throw, because the caller's next step is the same either way: say what to run.
    @discardableResult
    static func install(from source: URL, into directory: URL) -> Bool {
        if metallibPresent(in: directory) { return true }
        let manager = FileManager.default
        let staging = directory.appendingPathComponent("mlx.metallib.\(getpid()).partial")
        try? manager.removeItem(at: staging)
        do {
            try manager.copyItem(at: source, to: staging)
            // A rename, so a second process racing here never sees half a file.
            try manager.moveItem(at: staging, to: directory.appendingPathComponent("mlx.metallib"))
        } catch {
            // Lost the race, or the directory turned out not to be writable.
            try? manager.removeItem(at: staging)
        }
        return metallibPresent(in: directory)
    }

    /// `default.metallib` inside Frigate's resource bundle, wherever this binary carries
    /// it: beside the executable (a `.build` product), in an app's `Contents/Resources`,
    /// or in any bundle already loaded (a test bundle).
    static func bundledMetallib(binary: URL? = binaryDirectory, bundles: [Bundle] = Bundle.allBundles) -> URL? {
        var roots: [URL] = []
        if let binary { roots.append(binary) }
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots += bundles.compactMap(\.resourceURL)
        for root in roots {
            for name in shaderBundleNames {
                let candidate = root
                    .appendingPathComponent("\(name).bundle")
                    .appendingPathComponent("Contents/Resources/default.metallib")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    /// Whether `directory` sits inside a code-signed bundle's `Contents/MacOS`.
    static func isInsideSealedBundle(_ directory: URL) -> Bool {
        directory.pathComponents.contains { component in
            component.hasSuffix(".app") || component.hasSuffix(".xctest") || component.hasSuffix(".framework")
        }
    }
}

private func adverbMLXAnchor() {}

extension MLXStack {
    /// Process-wide GPU limits; set once per model load. The cache cap bounds MLX's
    /// reusable buffer pool; the memory limit makes it recycle rather than grow.
    /// PIN: the ONE door to the GPU before a model exists. Setting a limit initializes
    /// the Metal device, which loads the metallib, and MLX's default error handler is
    /// `exit(-1)` — so the check comes first and callers must be able to report a throw.
    /// `ensureMetallib` is true when one is already there, so this both installs and checks.
    public static func configureMemory(cacheLimitMB: Int, memoryLimitMB: Int) throws {
        guard ensureMetallib() else { throw ModelError.noMetal(fixHint) }
        GPU.set(cacheLimit: cacheLimitMB * 1024 * 1024)
        GPU.set(memoryLimit: memoryLimitMB * 1024 * 1024, relaxed: true)
    }

    public static var gpuActiveBytes: Int { GPU.activeMemory }
}
