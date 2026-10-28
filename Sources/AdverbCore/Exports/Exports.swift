//
//  Exports.swift
//  AdverbCore
//
//  WHAT: The month in forms the person follows by hand until posting is automated: a Markdown
//        sheet of every day (caption, hashtags, alt text, files and each voice-over language's
//        files, why that time), a CSV for a
//        spreadsheet or a scheduler, and an iCalendar file whose events alarm at each post time.
//

import Foundation

public enum Exports {
    public static func captionsMarkdown(_ campaign: Campaign, project: Project, paths: CampaignPaths) -> String {
        let zone = campaign.brief.zone
        var out = "# \(campaign.name)\n\n\(project.name) · \(campaign.brief.windowDates.first ?? "") to \(campaign.brief.windowDates.last ?? "") · times in \(campaign.brief.timeZone)\n\n"
        if let plan = campaign.plan { out += "\(plan.summary)\n\n" }
        for day in campaign.days {
            let weekday = weekdayName(day.date, zone)
            out += "## \(weekday) \(day.date), \(day.postTimeLocal) · \(day.targets.map(\.platform.title).joined(separator: ", "))\n\n"
            out += "**\(day.topic.title)** (\(day.topic.duration) s). \(day.timeReason)\n\n"
            out += "```\n\(day.postText)\n```\n\n"
            if let asset = day.asset {
                if !asset.a11y.altText.isEmpty { out += "**Alt text.** \(asset.a11y.altText)\n\n" }
                for target in day.targets {
                    if let render = asset.render(target.orientation) {
                        var line = "- \(target.platform.title): `\(render.path)`"
                        if PlatformLimits.acceptsCaptionFile(target.platform), let cc = asset.a11y.captions(target.orientation) {
                            line += " with captions `\(cc.srt)`"
                        }
                        out += line + "\n"
                    }
                }
                if let t = asset.a11y.transcriptPath { out += "- Transcript: `\(t)`\n" }
                if let vo = asset.voiceOver {
                    out += "- Voice-over: \(vo.voiceName)\(vo.isConfirmed ? "" : " (English not confirmed yet)")\n"
                    for track in vo.languages where track.isFresh {
                        for target in day.targets {
                            guard let render = track.render(target.orientation) else { continue }
                            var line = "- \(track.language.title), \(target.platform.title): `\(render.path)`"
                            if PlatformLimits.acceptsCaptionFile(target.platform), let cc = track.captions[target.orientation.rawValue] {
                                line += " with captions `\(cc.srt)`"
                            }
                            out += line + "\n"
                        }
                        if let t = track.transcriptPath { out += "- \(track.language.title) transcript: `\(t)`\n" }
                    }
                }
                out += "\n"
                if !asset.notes.illustrative.isEmpty { out += "Illustrative: \(asset.notes.illustrative.joined(separator: "; ")).\n\n" }
            } else {
                out += "_Not built yet._\n\n"
            }
        }
        return out
    }

    public static func csv(_ campaign: Campaign) -> String {
        let header = ["date", "time", "timezone", "post_at_utc", "platforms", "title", "duration", "caption", "hashtags",
                      "alt_text", "portrait", "landscape", "captions_portrait_srt", "captions_landscape_srt", "status", "reason",
                      "voice", "voice_languages"]
        let iso = ISO8601DateFormatter()
        var rows = [header.joined(separator: ",")]
        for day in campaign.days {
            let a = day.asset
            let files: [String] = [a?.render(.portrait)?.path ?? "", a?.render(.landscape)?.path ?? "",
                                   a?.a11y.captions(.portrait)?.srt ?? "", a?.a11y.captions(.landscape)?.srt ?? ""]
            let voice: [String] = [a?.voiceOver?.voiceName ?? "", a?.voiceOver?.freshLanguages.map(\.code).joined(separator: " ") ?? ""]
            let post: [String] = [day.date, day.postTimeLocal, campaign.brief.timeZone, iso.string(from: day.postAt),
                                  day.targets.map(\.platform.rawValue).joined(separator: " "), day.topic.title, String(day.topic.duration),
                                  day.caption, day.hashtags.map { "#\($0)" }.joined(separator: " "), a?.a11y.altText ?? ""]
            let fields: [String] = post + files + [day.status.rawValue, day.timeReason] + voice
            rows.append(fields.map(csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// RFC 5545: UTC times, CRLF line ends, lines folded at 75 octets, an alarm at the post time.
    public static func ics(_ campaign: Campaign, project: Project, now: Date = Date()) -> String {
        let stamp = utc(now)
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Rao Studios//Adverb//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
                     "X-WR-CALNAME:\(escape("\(project.name): \(campaign.name)"))"]
        for day in campaign.days {
            let platforms = day.targets.map(\.platform.title).joined(separator: ", ")
            var description = "\(day.timeReason)\n\n\(day.postText)"
            if let alt = day.asset?.a11y.altText, !alt.isEmpty { description += "\n\nAlt text: \(alt)" }
            if let path = day.asset?.render(day.targets.first?.orientation ?? .portrait)?.path { description += "\n\nVideo: \(path)" }
            lines += ["BEGIN:VEVENT", "UID:\(day.id.uuidString.lowercased())@adverb.rao.nyc", "DTSTAMP:\(stamp)",
                      "DTSTART:\(utc(day.postAt))", "DTEND:\(utc(day.postAt.addingTimeInterval(15 * 60)))",
                      "SUMMARY:\(escape("Post: \(day.topic.title) (\(platforms))"))", "DESCRIPTION:\(escape(description))",
                      "X-ADVERB-PLATFORM:\(day.targets.map(\.platform.rawValue).joined(separator: ","))",
                      "STATUS:\(day.status == .skipped ? "CANCELLED" : "CONFIRMED")",
                      "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape("Post \(day.topic.title)"))", "TRIGGER:PT0S", "END:VALARM",
                      "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func utc(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Folds a content line at 75 octets, never inside a UTF-8 sequence.
    static func fold(_ line: String) -> String {
        var out = "", current = 0
        for ch in line {
            let n = String(ch).utf8.count
            if current + n > 75 { out += "\r\n "; current = 1 }
            out.append(ch); current += n
        }
        return out
    }

    static func weekdayName(_ date: String, _ zone: TimeZone) -> String {
        guard let d = CalendarDate.date(date, in: zone) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "EEEE"
        return f.string(from: d)
    }

    /// Writes all three into the campaign's exports/ folder.
    public static func writeAll(_ campaign: Campaign, project: Project, paths: CampaignPaths) throws -> [URL] {
        let md = paths.exports.appendingPathComponent("captions.md"), csvURL = paths.exports.appendingPathComponent("campaign.csv")
        let icsURL = paths.exports.appendingPathComponent("campaign.ics")
        try AtomicFile.write(captionsMarkdown(campaign, project: project, paths: paths), to: md)
        try AtomicFile.write(csv(campaign), to: csvURL)
        try AtomicFile.write(ics(campaign, project: project), to: icsURL)
        return [md, csvURL, icsURL]
    }
}
