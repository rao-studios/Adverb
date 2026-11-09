import Foundation
import Testing
@testable import AdverbRender

@Suite struct ScriptCheckTests {
    @Test func aSyntaxErrorIsSaidWithItsLine() throws {
        let html = """
        <!doctype html><html><head><script src="kit.js"></script></head><body>
        <script>
        window.DUR=15;
        const items=[{title:'Morrow's margin'}];
        </script></body></html>
        """
        let problems = ScriptCheck.problems(html)
        #expect(problems.count == 1)
        let problem = try #require(problems.first)
        #expect(problem.hasPrefix("page.html line 4: SyntaxError"))
        #expect(problem.contains("Morrow's margin"))
        #expect(ScriptCheck.problems("<script>window.DUR=15;ready({dur:15,setup(){},seek(t){}});</script>").isEmpty)
        #expect(ScriptCheck.problems("<script src=\"kit.js\">this is not checked</script>").isEmpty)
    }
}
