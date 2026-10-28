import Foundation
import Testing
@testable import AdverbCore

@Suite struct StorageTests {
    @Test func slugsAreKebabAndUniqueCaseInsensitively() {
        #expect(Slug.make("Ambient — Café Reader!") == "ambient-cafe-reader")
        #expect(Slug.make("   ") == "untitled")
        #expect(Slug.unique("Ambient", taken: ["AMBIENT", "ambient-2"]) == "ambient-3")
        #expect(Slug.isTopicSlug("read-along"))
        #expect(!Slug.isTopicSlug("Read Along"))
        #expect(!Slug.isTopicSlug(String(repeating: "a", count: 25)))
    }

    @Test func volumeGateNamesTheDrive() {
        #expect(VolumeGate.volumeName(URL(fileURLWithPath: "/Volumes/T9/rao")) == "T9")
        #expect(VolumeGate.volumeName(URL(fileURLWithPath: "/Users/me")) == nil)
        #expect(VolumeGate.status(URL(fileURLWithPath: "/Volumes/NoSuchDriveAdverb/x")) == .notMounted(volume: "NoSuchDriveAdverb"))
        let temp = Fixture.temp()
        #expect(VolumeGate.status(temp) == .bootVolume)
        #expect(VolumeGate.status(temp.appendingPathComponent("gone")) == .missing)
    }

    @Test func sidecarsAreSkipped() throws {
        let temp = Fixture.temp()
        try "x".write(to: temp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: temp.appendingPathComponent("._a.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: temp.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        #expect(AtomicFile.contents(of: temp).map(\.lastPathComponent) == ["a.txt"])
    }

    @Test func projectsRoundTripAndRemoveNeverTouchesContext() throws {
        let workdir = Fixture.temp(), context = Fixture.temp("context")
        try "# App".write(to: context.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let kit = Fixture.temp("kit")
        for file in KitInstaller.files {
            let url = kit.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (file == "KIT-VERSION" ? "7" : "x").write(to: url, atomically: true, encoding: .utf8)
        }
        let workspace = Workspace(workdir: workdir)
        try workspace.prepare()
        // Install from the fixture kit rather than the bundle.
        let store = ProjectStore(workspace: workspace)
        try FileManager.default.createDirectory(at: workspace.projectFolder("seed"), withIntermediateDirectories: true)
        #expect(try KitInstaller.install(into: workspace.projectFolder("seed").appendingPathComponent("kit"), from: kit) == "7")
        var project = Project(slug: "ambient", name: "Ambient", contextPath: context.path, app: .ambient)
        try store.save(project)
        var index = workspace.readIndex(); index.projectOrder = ["ambient"]; try workspace.writeIndex(index)
        #expect(store.list().map(\.slug) == ["ambient"])
        project.tags = ["reader"]
        try store.save(project)
        #expect(store.list().first?.tags == ["reader"])
        // Keep the folder: it is set aside, the project is forgotten.
        try store.remove(project, deleteFolder: false)
        #expect(store.list().isEmpty)
        #expect(AtomicFile.contents(of: workspace.root).contains { $0.lastPathComponent.hasPrefix("ambient.removed-") })
        #expect(FileManager.default.fileExists(atPath: context.appendingPathComponent("README.md").path))
        // Delete it.
        let second = Project(slug: "second", name: "Second", contextPath: context.path, app: .aii)
        try store.save(second)
        try store.remove(second, deleteFolder: true)
        #expect(!FileManager.default.fileExists(atPath: workspace.projectFolder("second").path))
        #expect(FileManager.default.fileExists(atPath: context.appendingPathComponent("README.md").path))
    }

    @Test func oneLiveCampaignPerProject() throws {
        let workspace = Workspace(workdir: Fixture.temp())
        try workspace.prepare()
        let project = Project(slug: "p", name: "P", contextPath: "/tmp", app: .ambient)
        let store = CampaignStore(workspace: workspace, project: project)
        let a = try store.create(name: "November", brief: sampleBrief())
        let b = try store.create(name: "December", brief: sampleBrief(start: "2026-12-01"))
        _ = try store.setState(a.id, to: .live)
        #expect(throws: CampaignError.anotherIsLive("November")) { _ = try store.setState(b.id, to: .live) }
        _ = try store.setState(a.id, to: .archived)
        #expect(try store.setState(b.id, to: .live).state == .live)
        #expect(try store.load(a.id).archivedAt != nil)
    }

    @Test func settingsDecodeTolerantly() throws {
        let url = Fixture.temp().appendingPathComponent("settings.json")
        try #"{"workdir":"/Volumes/T9/rao","model":"claude-sonnet-5-5"}"#.write(to: url, atomically: true, encoding: .utf8)
        let s = AdverbSettings.load(from: url)
        #expect(s.workdir == "/Volumes/T9/rao")
        #expect(s.model == "claude-sonnet-5-5")
        #expect(s.effort == "high")
        #expect(s.renderer == .native)
        #expect(s.voiceOverDefault == false)
        #expect(s.voiceModel == "eleven_multilingual_v2")
        #expect(s.voiceLanguages.isEmpty)
        #expect(s.voiceSelection == nil)
        try #"{"voiceLanguages":["es","zz","fr"],"voiceOverDefault":true,"voiceID":"v1","voiceName":"Rachel"}"#.write(to: url, atomically: true, encoding: .utf8)
        let v = AdverbSettings.load(from: url)
        #expect(v.voiceLanguages == [.french, .spanish])
        #expect(v.voiceOverDefault)
        #expect(v.voiceSelection == VoiceSelection(voiceID: "v1", voiceName: "Rachel"))
        // Round trip keeps them.
        try v.save(to: url)
        #expect(AdverbSettings.load(from: url) == v)
    }

    @Test func secretsNeverPrint() {
        let secret = Secret("sk-ant-abcdefghijklmnop1234")!
        #expect("\(secret)" == "Secret(••••)")
        #expect(secret.masked == "sk-ant-…1234")
        #expect(Secret("   ") == nil)
        let resolver = KeyResolver(store: MemoryKeyStore(), environment: ["ANTHROPIC_API_KEY": "sk-env"])
        #expect(resolver.resolve()?.source == .environment)
        let both = KeyResolver(store: MemoryKeyStore(Secret("sk-own")), environment: ["ANTHROPIC_API_KEY": "sk-env"])
        #expect(both.resolve()?.secret.value == "sk-own")
        #expect(KeychainKeyStore.addCommand(service: "s", account: "a", secret: Secret("ab")!).hasSuffix("-X 6162\n"))
        // The ElevenLabs key: its own account and variable; the Claude variable never stands in for it.
        let voice = KeyResolver(store: MemoryKeyStore(), environment: ["ANTHROPIC_API_KEY": "sk-env"], envName: KeyResolver.elevenLabsEnv)
        #expect(voice.resolve() == nil)
        let fromEnv = KeyResolver(store: MemoryKeyStore(), environment: ["ELEVENLABS_API_KEY": "xi-env"], envName: KeyResolver.elevenLabsEnv)
        #expect(fromEnv.resolve()?.source == .environment)
        #expect(KeychainKeyStore(account: KeychainKeyStore.elevenLabsAccount).account == "ELEVENLABS_API_KEY")
        #expect(KeychainKeyStore().account == "ANTHROPIC_API_KEY")
        #expect(KeySource.environment.label(env: KeyResolver.elevenLabsEnv) == "ELEVENLABS_API_KEY in the environment")
        #expect(KeySource.environment.label == "ANTHROPIC_API_KEY in the environment")
    }

    @Test func campaignPathsName() {
        let paths = CampaignPaths(root: URL(fileURLWithPath: "/w/Adverb/p/campaigns/c"))
        let asset = paths.asset("03-highlight")
        #expect(asset.video(.portrait).lastPathComponent == "03-highlight-portrait.mp4")
        #expect(asset.vtt(.landscape).lastPathComponent == "03-highlight-landscape.vtt")
        #expect(asset.still(.portrait, 2.7).lastPathComponent == "03-highlight-P_02.70.jpg")
        #expect(paths.relative(asset.page) == "assets/03-highlight/page.html")
    }
}
