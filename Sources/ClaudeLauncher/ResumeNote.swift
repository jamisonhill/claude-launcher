import Foundation

// MARK: - Resume notes
//
// Most projects keep a handoff note at `.planning/RESUME.md` saying where work
// stopped and what comes next. That answer is the thing worth knowing before
// launching a session, and it was previously only visible by opening the file.
//
// This reads the note and pulls out a single line to show under the project
// path. It is deliberately forgiving: the notes are written by hand and their
// headings vary ("Next action", "Next actions (in order)", "Next steps"), so
// parsing falls through several strategies and gives up quietly rather than
// showing something wrong. A missing or unparseable note is normal, not an
// error — plenty of projects have no note at all.

/// A one-line summary of where a project left off.
struct ResumeNote: Equatable {

    /// What the summary represents, which drives how it is presented.
    enum Kind: Equatable {
        /// Something is explicitly blocked; the user can't just pick up and go.
        case blocked
        /// A concrete next step is waiting.
        case nextStep
        /// Neither was found — this is the reason work stopped, as context.
        case context
    }

    let kind: Kind
    let summary: String
    /// The `**Paused:**` date, shown alongside so a stale note is obvious.
    let pausedDate: String?

    // MARK: - Loading

    /// Relative location of the handoff note within a project.
    static let notePath = ".planning/RESUME.md"

    /// Reads and parses a project's note, or nil when there isn't a usable one.
    static func load(forProjectAt path: String) -> ResumeNote? {
        let url = URL(fileURLWithPath: path).appendingPathComponent(notePath)

        // A note that can't be read is indistinguishable from no note, which is
        // the common case — don't surface it as a problem.
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> ResumeNote? {
        let lines = text.components(separatedBy: .newlines)
        let paused = pausedDate(in: lines)

        // Order matters: a blocker outranks a next step, because a next step
        // you can't actually take is misleading on its own.
        if let blocked = blockedLine(in: lines) {
            return ResumeNote(kind: .blocked, summary: blocked, pausedDate: paused)
        }
        if let next = firstNextAction(in: lines) {
            return ResumeNote(kind: .nextStep, summary: next, pausedDate: paused)
        }
        // Some notes record only why they stopped. A finished project usually
        // says so under Status rather than leaving a next action.
        for field in ["Reason", "Status"] {
            if let value = inlineField(field, in: lines) {
                return ResumeNote(kind: .context, summary: tidyEnding(value), pausedDate: paused)
            }
        }
        return nil
    }

    /// Drops a dangling colon left behind when a line introduced a list that
    /// isn't being shown.
    private static func tidyEnding(_ text: String) -> String {
        text.hasSuffix(":") ? String(text.dropLast()) : text
    }

    /// Finds an explicitly labelled blocker.
    ///
    /// Matching requires the line to *begin* with the label. Searching for the
    /// word anywhere would misread "There is **no blocker** and nothing
    /// half-finished" — a sentence that means the exact opposite — as a
    /// blocked project.
    private static func blockedLine(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let stripped = plainText(stripListMarker(line))
            guard let range = stripped.range(of: #"^(Blocked|Blocker)\b[:—-]"#,
                                             options: [.regularExpression, .caseInsensitive])
            else { continue }

            let body = String(stripped[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            let full = joinWrapped(body, from: index, in: lines, requireIndent: true).text
            if !full.isEmpty { return tidyEnding(full) }
        }
        return nil
    }

    /// The first item under a "Next action"/"Next steps" heading that is
    /// actually still outstanding.
    ///
    /// The notes number their next actions in priority order, so the earliest
    /// live item is the one worth surfacing. Two things get skipped on the way:
    /// items already marked done, and lines that merely introduce the list
    /// ("In rough order:"), which promise content on the following line and say
    /// nothing on their own.
    private static func firstNextAction(in lines: [String]) -> String? {
        guard let headingIndex = lines.firstIndex(where: { isNextHeading($0) }) else { return nil }

        var index = lines.index(after: headingIndex)
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop at the next heading — the section had no usable content.
            if trimmed.hasPrefix("#") { return nil }
            if trimmed.isEmpty {
                index = lines.index(after: index)
                continue
            }

            let isListItem = startsNewItem(trimmed)
            let indent = indentWidth(line)
            let body = plainText(stripListMarker(line))
            let (text, resume) = joinWrapped(body,
                                             from: index,
                                             in: lines,
                                             requireIndent: isListItem)
            index = resume

            if text.isEmpty || isCompleted(text) {
                // Detail bullets nested under a finished item are part of that
                // item, not the next thing to do — skip them with their parent.
                index = skipNested(deeperThan: indent, from: index, in: lines)
                continue
            }
            // A trailing colon means the real item is on the next line.
            if text.hasSuffix(":") { continue }
            return text
        }
        return nil
    }

    /// Whether an item has already been done, and so isn't a next step.
    ///
    /// Notes keep completed items in place for context rather than deleting
    /// them, so the first entry in a list is often finished work.
    private static func isCompleted(_ text: String) -> Bool {
        if text.hasPrefix("✅") || text.hasPrefix("~~") { return true }
        // Only an early "DONE" marks the item itself; later in a sentence it is
        // more likely describing what being done would mean.
        let head = String(text.prefix(48))
        return head.range(of: #"\bDONE\b"#, options: .regularExpression) != nil
    }

    private static func isNextHeading(_ line: String) -> Bool {
        line.range(of: #"^#{1,4}\s+next\s+(action|step)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Value of a `**Label:** value` field, which may share a line with others
    /// separated by "·".
    ///
    /// The bold sometimes closes after the colon and sometimes wraps the whole
    /// field ("**Status: COMPLETE.**"), so the closing marker is optional here;
    /// any stray one is stripped with the rest of the Markdown.
    private static func inlineField(_ label: String, in lines: [String]) -> String? {
        for line in lines {
            guard let range = line.range(of: #"\*\*\s*\#(label):(\*\*)?"#,
                                         options: [.regularExpression, .caseInsensitive])
            else { continue }

            var value = String(line[range.upperBound...])
            // Fields are chained on one line ("**Paused:** … · **Reason:** …"),
            // so a following separator ends this value.
            if let sep = value.range(of: "·") { value = String(value[..<sep.lowerBound]) }
            let cleaned = plainText(value)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private static func pausedDate(in lines: [String]) -> String? {
        if let raw = inlineField("Paused", in: lines) {
            // Keep just the date, dropping trailing colour like "late evening".
            if let match = raw.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
                return String(raw[match])
            }
            return raw
        }
        // Not every note uses the "**Paused:** …" field; some write the date
        // into a bold headline instead ("**⏸ PAUSED 2026-06-20 — …**").
        for line in lines {
            guard line.range(of: #"PAUSED"#, options: .caseInsensitive) != nil else { continue }
            if let match = line.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
                return String(line[match])
            }
        }
        return nil
    }

    // MARK: - Text tidying

    /// Joins a line with its wrapped continuation lines, and reports where the
    /// next item starts.
    ///
    /// Entries routinely run across two or three lines; taking only the first
    /// would cut sentences mid-clause.
    ///
    /// `requireIndent` distinguishes the two ways text wraps here. A list
    /// item's continuations are indented under it, and a flush-left line after
    /// one is a new paragraph rather than more of the item. Plain prose has no
    /// such indentation, so demanding it there would truncate the sentence.
    private static func joinWrapped(_ first: String,
                                    from index: Int,
                                    in lines: [String],
                                    requireIndent: Bool) -> (text: String, nextIndex: Int) {
        var parts = [first]
        var cursor = lines.index(after: index)

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A blank line, a heading, or a new list item ends this one.
            if trimmed.isEmpty || trimmed.hasPrefix("#") { break }
            if startsNewItem(trimmed) { break }
            if requireIndent, !(line.hasPrefix(" ") || line.hasPrefix("\t")) { break }

            parts.append(plainText(trimmed))
            cursor = lines.index(after: cursor)
        }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (joined, cursor)
    }

    /// Advances past lines indented deeper than `indent`, i.e. the sub-bullets
    /// belonging to the item that started at that level.
    private static func skipNested(deeperThan indent: Int, from index: Int, in lines: [String]) -> Int {
        var cursor = index
        while cursor < lines.count {
            let line = lines[cursor]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if indentWidth(line) <= indent { break }
            cursor = lines.index(after: cursor)
        }
        return cursor
    }

    /// Leading whitespace width, counting a tab as four columns.
    private static func indentWidth(_ line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 }
            else if character == "\t" { width += 4 }
            else { break }
        }
        return width
    }

    private static func startsNewItem(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^([-*+]\s|\d+[.)]\s)"#, options: .regularExpression) != nil
    }

    private static func stripListMarker(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: #"^([-*+]\s+|\d+[.)]\s+)"#, options: .regularExpression)
        else { return trimmed }
        return String(trimmed[range.upperBound...])
    }

    /// Reduces inline Markdown to something readable in a single label.
    private static func plainText(_ input: String) -> String {
        var text = input

        // Links become their text; the URL is noise at a glance.
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#,
                                         with: "$1",
                                         options: .regularExpression)
        // Emphasis and code fences carry no meaning once styling is stripped.
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"(?<![A-Za-z0-9])[_*]([^_*]+)[_*](?![A-Za-z0-9])"#,
                                         with: "$1",
                                         options: .regularExpression)
        // Collapse the whitespace that wrapping and indentation introduce.
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }
}
