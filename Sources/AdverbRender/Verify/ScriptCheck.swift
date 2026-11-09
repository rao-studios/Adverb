//
//  ScriptCheck.swift
//  AdverbRender
//
//  WHAT: A page's inline scripts parsed by JavaScriptCore before the renderer boots it: a syntax
//        error said with its line in page.html and the line itself ("line 172: SyntaxError:
//        Unexpected identifier 's' — title:'Morrow's margin'"), which is what the writer needs to
//        fix it. WebKit reports a file page's script errors only as "Script error.".
//  PIN:  Parsed, never run. A script with `src` is the kit's and is not checked here.
//

import Foundation
import JavaScriptCore

public enum ScriptCheck {
    public static func problems(_ html: String) -> [String] {
        var out: [String] = []
        guard let context = JSGlobalContextCreate(nil) else { return [] }
        defer { JSGlobalContextRelease(context) }
        for (script, line) in inlineScripts(html) {
            let source = JSStringCreateWithUTF8CString(script)
            defer { JSStringRelease(source) }
            var exception: JSValueRef?
            if !JSCheckScriptSyntax(context, source, nil, Int32(line), &exception), let exception {
                let message = describe(exception, context: context)
                let errorLine = lineNumber(exception, context: context) ?? line
                let text = html.components(separatedBy: "\n").dropFirst(errorLine - 1).first?
                    .trimmingCharacters(in: .whitespaces).prefix(160) ?? ""
                out.append("page.html line \(errorLine): \(message)" + (text.isEmpty ? "" : " — `\(text)`"))
            }
        }
        return out
    }

    /// Each `<script>` without `src`, with the line of page.html its first line is on.
    static func inlineScripts(_ html: String) -> [(String, Int)] {
        guard let regex = try? NSRegularExpression(pattern: "<script(?![^>]*\\bsrc=)[^>]*>(.*?)</script>", options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { match in
            let body = match.range(at: 1)
            let before = ns.substring(to: body.location)
            return (ns.substring(with: body), before.components(separatedBy: "\n").count)
        }
    }

    static func describe(_ value: JSValueRef, context: JSGlobalContextRef) -> String {
        guard let string = JSValueToStringCopy(context, value, nil) else { return "a syntax error" }
        defer { JSStringRelease(string) }
        let length = JSStringGetMaximumUTF8CStringSize(string)
        var buffer = [CChar](repeating: 0, count: length)
        JSStringGetUTF8CString(string, &buffer, length)
        return String(cString: buffer)
    }

    static func lineNumber(_ value: JSValueRef, context: JSGlobalContextRef) -> Int? {
        guard let object = JSValueToObject(context, value, nil) else { return nil }
        let name = JSStringCreateWithUTF8CString("line")
        defer { JSStringRelease(name) }
        let line = JSValueToNumber(context, JSObjectGetProperty(context, object, name, nil), nil)
        return line.isFinite && line > 0 ? Int(line) : nil
    }
}
