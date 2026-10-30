// FixHebrewPaste — אפליקציית macOS נייטיבית (שורת התפריטים)
// מתקנת טקסט עברית+אנגלית בלוח ההעתקה כך שיודבק נכון ב-PowerPoint, תוך שמירה על העיצוב.
//
// PowerPoint במק לא מיישם את אלגוריתם הכיווניות של יוניקוד על פיסוק "ניטרלי" (רווח, נקודה,
// סוגריים, מקף, נקודתיים), ומתעלם מסימני כיוון נסתרים (RLM/RLE) — אפילו מציג אותם כמלבנים.
// לכן התוכנה מפצלת כל פסקה לקטעים מפורשים:
//   • קטעים באנגלית  →  <span dir="ltr" lang="en-US">   (RTF: \ltrch)
//   • עברית + הפיסוק שסביב האנגלית  →  <span dir="rtl" lang="he">   (RTF: \rtlch)
// ופסקאות שיש בהן עברית מקבלות dir="rtl". שאר ה-HTML (מודגש, תבליטים, כותרות) נשאר כמו שהוא.
//
// בנוסף: ⌘R פותח Terminal, ⌘D ממזער/מחזיר את כל החלונות (כמו Win+D).
//
// בנייה:  ./build.sh
// בדיקה:  ./FixHebrewPaste.app/Contents/MacOS/FixHebrewPaste --cli-html < in.html

import Cocoa
import Carbon
import ServiceManagement
import Vision

// MARK: - סיווג כיווניות

enum Cls { case L, R, D, N }

enum Bidi {
    static func isRTL(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
    }

    static func containsRTL(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isRTL)
    }

    static func cls(_ s: Unicode.Scalar) -> Cls {
        if isRTL(s) { return .R }
        if s.properties.numericType == .decimal { return .D }
        if s.properties.isAlphabetic { return .L }
        return .N
    }

    /// מחזיר לכל תו: true = שייך לקטע אנגלית (LTR), false = שייך לצד העברי.
    static func segment(_ input: [Cls], _ chars: [Unicode.Scalar]) -> [Bool] {
        var cs = input
        let n = cs.count

        // 1. מספרים: צמודים לאות לטינית או אחרי טקסט לטיני → אנגלית ("1j01", "Windows 95, 98")
        var i = 0
        var lastStrong: Cls? = nil
        while i < n {
            if cs[i] == .D {
                var j = i
                while j < n && cs[j] == .D { j += 1 }
                let adjacent = (i > 0 && cs[i - 1] == .L) || (j < n && cs[j] == .L)
                let c: Cls = (adjacent || lastStrong == .L) ? .L : .R
                for k in i..<j { cs[k] = c }
                lastStrong = c
                i = j
            } else {
                if cs[i] == .L || cs[i] == .R { lastStrong = cs[i] }
                i += 1
            }
        }

        // 2. זוגות סוגריים מקבלים כיוון זהה לשני הצדדים
        let openers: [Unicode.Scalar: Unicode.Scalar] = ["(": ")", "[": "]", "{": "}"]
        var stack: [(Int, Unicode.Scalar)] = []
        var pairs: [(Int, Int)] = []
        for k in 0..<n {
            let ch = chars[k]
            if let close = openers[ch] {
                stack.append((k, close))
            } else if ch == ")" || ch == "]" || ch == "}" {
                if let d = stack.lastIndex(where: { $0.1 == ch }) {
                    pairs.append((stack[d].0, k))
                    stack.removeSubrange(d...)
                }
            }
        }
        pairs.sort { $0.0 < $1.0 }
        for (a, b) in pairs {
            let inner = cs[(a + 1)..<b]
            let c: Cls
            if inner.contains(.R) {
                c = .R
            } else if inner.contains(.L) {
                var prev: Cls? = nil
                var k = a - 1
                while k >= 0 {
                    if cs[k] == .L || cs[k] == .R { prev = cs[k]; break }
                    k -= 1
                }
                c = (prev == .L) ? .L : .R
            } else {
                continue
            }
            cs[a] = c
            cs[b] = c
        }

        // 3. קטע אנגלית = מהאות הלטינית הראשונה עד האחרונה, כל עוד אין עברית באמצע
        var out = [Bool](repeating: false, count: n)
        i = 0
        while i < n {
            if cs[i] == .L {
                var last = i
                var j = i + 1
                while j < n && cs[j] != .R {
                    if cs[j] == .L { last = j }
                    j += 1
                }
                for k in i...last { out[k] = true }
                i = last + 1
            } else {
                i += 1
            }
        }
        return out
    }
}

func scalarsToString<S: Sequence>(_ s: S) -> String where S.Element == Unicode.Scalar {
    var v = String.UnicodeScalarView()
    v.append(contentsOf: s)
    return String(v)
}

// MARK: - תיקון HTML (שומר עיצוב)

enum HTMLFixer {
    static let marker = "<!--fixhebrewpaste-->"
    static let ltrOpen = "<span dir=\"ltr\" lang=\"en-US\">"
    static let rtlOpen = "<span dir=\"rtl\" lang=\"he\">"

    static let blockTags: Set<String> = ["p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6",
                                         "blockquote", "td", "th", "tr", "table", "pre", "section",
                                         "article", "body", "html", "br", "hr", "dd", "dt", "dl"]
    static let skipTags: Set<String> = ["style", "script", "head", "title"]

    final class Tok {
        let isTag: Bool
        let text: String
        let units: [String]
        var makeRTL = false
        var ltr: [Bool] = []
        var segHasR = false
        init(tag: String) { isTag = true; text = tag; units = [] }
        init(units: [String]) { isTag = false; text = ""; self.units = units }
    }

    static func tokenize(_ html: String) -> [Tok] {
        let s = Array(html.unicodeScalars)
        let n = s.count
        var toks: [Tok] = []
        var units: [String] = []
        func flushText() {
            if !units.isEmpty { toks.append(Tok(units: units)); units = [] }
        }
        var i = 0
        while i < n {
            let c = s[i]
            if c == "<" {
                var end: Int? = nil
                if i + 3 < n && s[i + 1] == "!" && s[i + 2] == "-" && s[i + 3] == "-" {
                    var k = i + 4
                    while k + 2 < n {
                        if s[k] == "-" && s[k + 1] == "-" && s[k + 2] == ">" { end = k + 2; break }
                        k += 1
                    }
                } else {
                    var k = i + 1
                    while k < n {
                        if s[k] == ">" { end = k; break }
                        k += 1
                    }
                }
                if let e = end {
                    flushText()
                    toks.append(Tok(tag: scalarsToString(s[i...e])))
                    i = e + 1
                    continue
                }
            } else if c == "&" {
                var k = i + 1
                var ok = false
                while k < n && k - i <= 10 {
                    let ch = s[k]
                    if ch == ";" { ok = k > i + 1; break }
                    let isAlnum = (ch.value >= 48 && ch.value <= 57) || (ch.value >= 65 && ch.value <= 90) || (ch.value >= 97 && ch.value <= 122)
                    if !(isAlnum || ch == "#") { break }
                    k += 1
                }
                if ok {
                    units.append(scalarsToString(s[i...k]))
                    i = k + 1
                    continue
                }
            }
            units.append(String(c))
            i += 1
        }
        flushText()
        return toks
    }

    static func unitScalar(_ u: String) -> Unicode.Scalar? {
        let sc = Array(u.unicodeScalars)
        if sc.count == 1 { return sc[0] }
        if u.hasPrefix("&#") && u.hasSuffix(";") {
            let body = String(u.dropFirst(2).dropLast())
            let v: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") { v = UInt32(body.dropFirst(), radix: 16) } else { v = UInt32(body) }
            if let v = v { return Unicode.Scalar(v) }
        }
        return nil
    }

    static func tagInfo(_ t: String) -> (name: String, closing: Bool, selfClosing: Bool)? {
        let s = Array(t.unicodeScalars)
        var i = 1
        while i < s.count && s[i] == " " { i += 1 }
        var closing = false
        if i < s.count && s[i] == "/" { closing = true; i += 1 }
        var name = String.UnicodeScalarView()
        while i < s.count {
            let v = s[i].value
            let isAlnum = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
            if !isAlnum { break }
            name.append(s[i])
            i += 1
        }
        if name.isEmpty { return nil }
        return (String(name).lowercased(), closing, t.hasSuffix("/>"))
    }

    static func insertBeforeEnd(_ tag: String, _ text: String) -> String {
        var t = tag
        let back = t.hasSuffix("/>") ? 2 : 1
        let idx = t.index(t.endIndex, offsetBy: -back)
        t.insert(contentsOf: text, at: idx)
        return t
    }

    static func addRTL(_ tag: String) -> String {
        var t = tag.replacingOccurrences(of: "\\sdir\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", with: "",
                                         options: [.regularExpression, .caseInsensitive])
        if let r = t.range(of: "\\sstyle\\s*=\\s*\"", options: [.regularExpression, .caseInsensitive]) {
            t.insert(contentsOf: "direction:rtl;text-align:right;", at: r.upperBound)
        } else {
            t = insertBeforeEnd(t, " style=\"direction:rtl;text-align:right;\"")
        }
        return insertBeforeEnd(t, " dir=\"rtl\"")
    }

    static func fix(_ html: String) -> String {
        if html.contains(marker) { return html }
        let toks = tokenize(html)

        var skip = 0
        var heb = 0
        var seg: [(tok: Tok, idx: Int, cls: Cls, ch: Unicode.Scalar)] = []
        var stack: [(tok: Tok, name: String, heb: Int)] = []

        func flush() {
            guard !seg.isEmpty else { return }
            let flags = Bidi.segment(seg.map { $0.cls }, seg.map { $0.ch })
            let hasR = seg.contains { $0.cls == .R }
            for (k, e) in seg.enumerated() {
                if e.tok.ltr.isEmpty { e.tok.ltr = [Bool](repeating: false, count: e.tok.units.count) }
                e.tok.ltr[e.idx] = flags[k]
                e.tok.segHasR = hasR
            }
            seg.removeAll()
        }
        func closeBlock(_ top: (tok: Tok, name: String, heb: Int)) {
            if heb > top.heb && top.name != "html" && top.name != "body" { top.tok.makeRTL = true }
        }

        for tok in toks {
            if tok.isTag {
                guard let info = tagInfo(tok.text) else { continue }
                if skipTags.contains(info.name) {
                    if info.closing { skip = max(0, skip - 1) } else if !info.selfClosing { skip += 1 }
                    continue
                }
                guard blockTags.contains(info.name) else { continue }
                flush()
                if info.name == "br" || info.name == "hr" { continue }
                if !info.closing {
                    if !info.selfClosing { stack.append((tok, info.name, heb)) }
                } else if stack.contains(where: { $0.name == info.name }) {
                    while let top = stack.popLast() {
                        closeBlock(top)
                        if top.name == info.name { break }
                    }
                }
            } else if skip == 0 {
                for (ui, u) in tok.units.enumerated() {
                    let sc = unitScalar(u)
                    let c: Cls = sc.map(Bidi.cls) ?? .N
                    if c == .R { heb += 1 }
                    seg.append((tok, ui, c, sc ?? "\u{0}"))
                }
            }
        }
        flush()
        while let top = stack.popLast() { closeBlock(top) }

        var out = ""
        for tok in toks {
            if tok.isTag {
                out += tok.makeRTL ? addRTL(tok.text) : tok.text
                continue
            }
            let whitespaceOnly = tok.units.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if tok.ltr.isEmpty || !tok.segHasR || whitespaceOnly {
                out += tok.units.joined()
                continue
            }
            var current: Bool? = nil
            var buf = ""
            for (ui, u) in tok.units.enumerated() {
                let f = tok.ltr[ui]
                if let cur = current, cur != f, !buf.isEmpty {
                    out += (cur ? ltrOpen : rtlOpen) + buf + "</span>"
                    buf = ""
                }
                current = f
                buf += u
            }
            if let cur = current, !buf.isEmpty { out += (cur ? ltrOpen : rtlOpen) + buf + "</span>" }
        }
        return out + marker
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// כשבלוח יש רק טקסט נקי — בונים ממנו HTML פשוט (שורה = פסקה, **מודגש**)
    static func htmlFromPlain(_ plain: String, cleanMarkdown: Bool) -> String {
        var body = ""
        let lines = plain.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines where !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            var l = escape(raw)
            if cleanMarkdown {
                l = l.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<b>$1</b>", options: .regularExpression)
                     .replacingOccurrences(of: "`", with: "")
                     .replacingOccurrences(of: "^\\s*#{1,6}\\s+", with: "", options: .regularExpression)
                     .replacingOccurrences(of: "^(\\s*)[*+\\-]\\s+", with: "$1• ", options: .regularExpression)
            }
            body += "<p>\(l)</p>"
        }
        return "<meta charset=\"utf-8\">" + body
    }
}

// MARK: - RTF עם כיוון מפורש לכל קטע (\rtlch / \ltrch)

enum RTFWriter {
    static func escape(_ s: String) -> String {
        var out = ""
        for u in s.utf16 {
            switch u {
            case 0x5C: out += "\\\\"
            case 0x7B: out += "\\{"
            case 0x7D: out += "\\}"
            case 0x09: out += "\\tab "
            case 0x20..<0x80: out += String(UnicodeScalar(UInt8(u)))
            default: out += "\\u\(Int16(bitPattern: u))?"
            }
        }
        return out
    }

    static func runCodes(ltr: Bool, bold: Bool, italic: Bool, underline: Bool) -> String {
        var c = ltr ? "\\ltrch\\lang1033" : "\\rtlch\\lang1037\\alang1037"
        if bold { c += "\\b\\ab" }
        if italic { c += "\\i\\ai" }
        if underline { c += "\\ul" }
        return c
    }

    static func rtf(from attr: NSAttributedString) -> String {
        var out = "{\\rtf1\\ansi\\ansicpg1252\\deff0\\deflang1037{\\fonttbl{\\f0\\fswiss\\fcharset0 Arial;}}\n"
        let ns = attr.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { sub, pr, _, _ in
            out += RTFWriter.paragraph(attr, sub ?? "", pr)
        }
        return out + "}"
    }

    static func paragraph(_ attr: NSAttributedString, _ para: String, _ pr: NSRange) -> String {
        let sc = Array(para.unicodeScalars)
        let n = sc.count
        guard n > 0, pr.length > 0 else { return "\\pard\\plain\\par\n" }

        var offs: [Int] = []
        var o = 0
        for s in sc { offs.append(o); o += UTF16.width(s) }

        let pstyle = attr.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
        let level = pstyle?.textLists.count ?? 0

        // סימן תבליט שמערכת ההפעלה מוסיפה לרשימות: "\t•\t"
        var start = 0
        var listMarker = ""
        if level > 0 {
            var k = 0
            while k < n && sc[k] == "\t" { k += 1 }
            var m = k
            while m < n && sc[m] != "\t" && m - k < 6 { m += 1 }
            if m < n && sc[m] == "\t" && m > k {
                listMarker = scalarsToString(sc[k..<m])
                start = m + 1
            }
        }

        let body = Array(sc[start...])
        let classes = body.map(Bidi.cls)
        let flags = Bidi.segment(classes, body)
        let hasR = classes.contains(.R)

        var out = "\\pard\\plain" + (hasR ? "\\rtlpar\\qr" : "\\ltrpar\\ql")
        if level > 0 { out += "\\li\(level * 360)\\ri\(level * 360)" }
        out += " "
        if !listMarker.isEmpty {
            out += "{" + runCodes(ltr: !hasR, bold: false, italic: false, underline: false) + " " + escape(listMarker + " ") + "}"
        }

        var key: (Bool, Bool, Bool, Bool)? = nil
        var buf = ""
        func emit() {
            if let k = key, !buf.isEmpty {
                out += "{" + runCodes(ltr: k.0, bold: k.1, italic: k.2, underline: k.3) + " " + escape(buf) + "}"
            }
            buf = ""
        }
        for k in start..<n {
            let attrs = attr.attributes(at: pr.location + offs[k], effectiveRange: nil)
            var bold = false, italic = false
            if let f = attrs[.font] as? NSFont {
                let t = f.fontDescriptor.symbolicTraits
                bold = t.contains(.bold)
                italic = t.contains(.italic)
            }
            let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            let newKey = (flags[k - start], bold, italic, underline)
            if let cur = key, cur != newKey { emit() }
            key = newKey
            buf += String(sc[k])
        }
        emit()
        return out + "\\par\n"
    }
}

// MARK: - טקסט נקי (מצב גיבוי) — רק RLM, בלי RLE/PDF שמופיעים כמלבנים

enum PlainFixer {
    static let RLM: Unicode.Scalar = "\u{200F}"

    static func isBidiControl(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return v == 0x200E || v == 0x200F || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v)
    }

    static func cleanMarkdown(_ line: String) -> String {
        line.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "^(\\s*)#{1,6}\\s+", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "^(\\s*)[*+\\-]\\s+", with: "$1• ", options: .regularExpression)
    }

    static func fix(_ text: String, cleanMarkdown clean: Bool) -> String {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let stripped = scalarsToString(t.unicodeScalars.filter { !isBidiControl($0) })
        return stripped.components(separatedBy: "\n").map { raw -> String in
            let line = clean ? cleanMarkdown(raw) : raw
            guard Bidi.containsRTL(line) else { return line }
            let sc = Array(line.unicodeScalars)
            let flags = Bidi.segment(sc.map(Bidi.cls), sc)
            var out = String.UnicodeScalarView()
            for (k, s) in sc.enumerated() {
                // סוף קטע אנגלית → RLM, כדי שהפיסוק שאחריו יישאר בצד העברי
                if k > 0 && flags[k - 1] && !flags[k] { out.append(RLM) }
                out.append(s)
            }
            if let last = flags.last, last { out.append(RLM) }
            return String(out)
        }.joined(separator: "\n")
    }
}

// MARK: - OCR (זיהוי טקסט בתמונה — Apple Vision, מקומי לגמרי)

enum OCR {
    enum Failure: Error { case noImage, noText }

    /// השפות שהזיהוי תומך בהן במערכת הזו
    static func supportedLanguages(for req: VNRecognizeTextRequest = VNRecognizeTextRequest()) -> [String] {
        req.recognitionLevel = .accurate
        if #available(macOS 12.0, *) {
            return (try? req.supportedRecognitionLanguages()) ?? []
        }
        return (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate, revision: VNRecognizeTextRequestRevision2)) ?? []
    }

    static let hebrewHelp =
        "זיהוי עברית דורש את מנוע ה-OCR החינמי Tesseract (ה-OCR המובנה של macOS לא תומך בעברית).\n" +
        "להתקנה, הרץ ב-Terminal:\n\nbrew install tesseract tesseract-lang\n\n" +
        "(נדרש Homebrew: brew.sh). אחרי ההתקנה FixHebrewPaste ישתמש בו אוטומטית."

    static var supportsHebrew: Bool {
        supportedLanguages().contains { $0.lowercased().hasPrefix("he") || $0.lowercased().hasPrefix("iw") }
    }

    /// תמונה מהלוח: צילום מסך / תמונה שהועתקה, או קובץ תמונה שהועתק מ-Finder
    static func imageFromPasteboard(_ pb: NSPasteboard) -> CGImage? {
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true,
                                               .urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           let url = urls.first,
           let img = NSImage(contentsOf: url),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        if let img = NSImage(pasteboard: pb),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        return nil
    }

    enum Engine: String { case tesseract = "Tesseract", vision = "Apple Vision" }

    /// מזהה טקסט ומחזיר אותו כטקסט רגיל. עברית דורשת Tesseract (Apple Vision לא תומך בעברית).
    static func recognize(_ image: CGImage) throws -> (text: String, engine: Engine) {
        if let tess = tesseractPath(), tesseractLanguages(tess).contains("heb") {
            return (try recognizeWithTesseract(image, binary: tess), .tesseract)
        }
        return (try recognizeWithVision(image), .vision)
    }

    // MARK: Tesseract (אם מותקן: brew install tesseract tesseract-lang)

    static func tesseractPath() -> String? {
        ["/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract", "/opt/local/bin/tesseract"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Hebrew OCR זמין במחשב הזה?
    static var hebrewAvailable: Bool {
        if let t = tesseractPath(), tesseractLanguages(t).contains("heb") { return true }
        return supportsHebrew
    }

    private static func run(_ binary: String, _ args: [String]) -> (status: Int32, out: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    static func tesseractLanguages(_ binary: String) -> [String] {
        let r = run(binary, ["--list-langs"])
        return String(decoding: r.out, as: UTF8.self)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("List of") }
    }

    /// מגדיל תמונות קטנות פי 2 — Tesseract מדויק יותר בטקסט גדול
    private static func upscaled(_ image: CGImage) -> CGImage {
        guard image.width < 2000 else { return image }
        let w = image.width * 2, h = image.height * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func recognizeWithTesseract(_ image: CGImage, binary: String) throws -> String {
        let rep = NSBitmapImageRep(cgImage: upscaled(image))
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.noImage }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixhebrewpaste-ocr-\(UUID().uuidString).png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let langs = tesseractLanguages(binary).contains("eng") ? "heb+eng" : "heb"
        let r = run(binary, [file.path, "stdout", "-l", langs, "--psm", "3", "tsv"])
        guard r.status == 0 else { throw Failure.noText }
        let text = textFromTSV(String(decoding: r.out, as: UTF8.self))
        guard !text.isEmpty else { throw Failure.noText }
        return text
    }

    private static func isBidiControl(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return v == 0x200E || v == 0x200F || v == 0x061C || (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v)
    }

    /// בונה טקסט בסדר לוגי ממיקומי המילים (לא סומך על ניחוש הכיוון של Tesseract),
    /// ומסיר את סימני הכיוון הנסתרים שהוא מוסיף.
    static func textFromTSV(_ tsv: String) -> String {
        struct Word { let x: Int; let text: String }
        var lines: [(key: String, block: String, words: [Word])] = []
        for row in tsv.components(separatedBy: "\n").dropFirst() {
            let c = row.components(separatedBy: "\t")
            guard c.count >= 12, c[0] == "5", let x = Int(c[6]) else { continue }
            let word = String(String.UnicodeScalarView(c[11...].joined(separator: " ").unicodeScalars.filter { !isBidiControl($0) }))
                .trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            let key = "\(c[2]).\(c[3]).\(c[4])"
            if lines.last?.key == key {
                lines[lines.count - 1].words.append(Word(x: x, text: word))
            } else {
                lines.append((key, c[2], [Word(x: x, text: word)]))
            }
        }

        func hebrew(_ w: String) -> Int { w.unicodeScalars.filter(Bidi.isRTL).count }
        func latin(_ w: String) -> Int { w.unicodeScalars.filter { $0.properties.isAlphabetic && !Bidi.isRTL($0) }.count }

        var out: [String] = []
        var lastBlock: String? = nil
        for line in lines {
            if let b = lastBlock, b != line.block { out.append("") }
            lastBlock = line.block
            let all = line.words.map { $0.text }.joined()
            let rtl = hebrew(all) >= latin(all) && hebrew(all) > 0
            // מילים בסדר הקריאה של השורה (מימין לשמאל בשורה עברית)
            let ordered = line.words.sorted { rtl ? $0.x > $1.x : $0.x < $1.x }
            // רצפים בכיוון ההפוך (אנגלית בתוך עברית / עברית בתוך אנגלית) — מחזירים לסדר שלהם
            func isForeign(_ t: String) -> Bool { rtl ? (hebrew(t) == 0 && latin(t) > 0) : hebrew(t) > 0 }
            func isNeutral(_ t: String) -> Bool { hebrew(t) == 0 && latin(t) == 0 }   // מספרים, סימנים
            var result: [String] = []
            var run: [String] = []
            for (k, w) in ordered.enumerated() {
                var foreign = isForeign(w.text)
                if isNeutral(w.text) {
                    // מספר שצמוד לרצף זר ("Windows 95, 98") שייך לרצף
                    let next = ordered[(k + 1)...].first { !isNeutral($0.text) }
                    foreign = next.map { isForeign($0.text) } ?? false
                }
                if foreign {
                    run.append(w.text)
                } else {
                    result += run.reversed(); run = []
                    result.append(w.text)
                }
            }
            result += run.reversed()
            out.append(result.joined(separator: " "))
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Apple Vision (מובנה; בלי עברית)

    static func recognizeWithVision(_ image: CGImage) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let supported = supportedLanguages(for: req)
        // עברית קודם, כדי שתקבל עדיפות; אחריה אנגלית
        let hebrew = supported.filter { $0.lowercased().hasPrefix("he") || $0.lowercased().hasPrefix("iw") }
        let english = supported.filter { $0.lowercased().hasPrefix("en") }
        if !(hebrew + english).isEmpty { req.recognitionLanguages = hebrew + english }

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let obs = (req.results ?? []).compactMap { o -> (CGRect, String)? in
            guard let s = o.topCandidates(1).first?.string, !s.isEmpty else { return nil }
            return (o.boundingBox, s)
        }
        guard !obs.isEmpty else { throw Failure.noText }

        // קיבוץ לשורות לפי גובה (בקואורדינטות של Vision, y=0 בתחתית)
        let sorted = obs.sorted { $0.0.midY > $1.0.midY }
        var lines: [[(CGRect, String)]] = []
        for o in sorted {
            if let last = lines.last?.first, abs(last.0.midY - o.0.midY) < max(last.0.height, o.0.height) * 0.5 {
                lines[lines.count - 1].append(o)
            } else {
                lines.append([o])
            }
        }
        return lines.map { line -> String in
            let rtl = line.map { $0.1 }.joined().unicodeScalars.filter(Bidi.isRTL).count
                    > line.map { $0.1 }.joined().unicodeScalars.filter { $0.properties.isAlphabetic && !Bidi.isRTL($0) }.count
            let ordered = line.sorted { rtl ? $0.0.minX > $1.0.minX : $0.0.minX < $1.0.minX }
            return ordered.map { $0.1 }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// מצייר טקסט לתמונה (לבדיקה עצמית)
    static func renderTestImage(_ text: String) -> CGImage? {
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 44),
            .foregroundColor: NSColor.black,
        ])
        let size = attr.boundingRect(with: NSSize(width: 2000, height: 2000), options: [.usesLineFragmentOrigin]).size
        let w = Int(size.width) + 80, h = Int(size.height) + 80
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        attr.draw(with: NSRect(x: 40, y: 40, width: size.width + 1, height: size.height + 1), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}

// MARK: - גרסה

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static let repoURL = "https://github.com/udiweinstein/FixHebrewPaste"
}

// MARK: - מצב שורת פקודה (לבדיקות)

let cliArgs = CommandLine.arguments
if cliArgs.contains("--version") {
    print("FixHebrewPaste \(AppInfo.version)")
    exit(0)
}
if cliArgs.contains("--ocr-selftest") {
    // מדפיס את שפות ה-OCR הנתמכות ומריץ OCR על תמונה עם עברית ואנגלית
    print("OCR languages: \(OCR.supportedLanguages().joined(separator: ", "))")
    print("Hebrew in Apple Vision: \(OCR.supportsHebrew)")
    if let t = OCR.tesseractPath() {
        print("Tesseract: \(t) — languages: \(OCR.tesseractLanguages(t).joined(separator: ", "))")
    } else {
        print("Tesseract: not installed")
    }
    let sample = "שלום עולם, זו בדיקה של OCR\nHello World 2026\nהפרויקט ב-GitHub הוא JS Paint\nגרסאות Windows 95, 98 ו-XP"
    guard let img = OCR.renderTestImage(sample) else { print("render failed"); exit(1) }
    do {
        let r = try OCR.recognize(img)
        print("OCR engine: \(r.engine.rawValue)\nOCR result:\n\(r.text)")
    } catch {
        print("OCR error: \(error)")
        exit(1)
    }
    exit(0)
}
if let i = cliArgs.firstIndex(of: "--cli-ocr"), i + 1 < cliArgs.count {
    guard let img = NSImage(contentsOfFile: cliArgs[i + 1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("cannot read image"); exit(1)
    }
    print((try? OCR.recognize(img).text) ?? "")
    exit(0)
}
if cliArgs.contains("--cli-html") || cliArgs.contains("--cli-text") || cliArgs.contains("--cli-rtf") {
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    if cliArgs.contains("--cli-html") {
        print(HTMLFixer.fix(input))
    } else if cliArgs.contains("--cli-text") {
        print(PlainFixer.fix(input, cleanMarkdown: true))
    } else if let data = input.data(using: .utf8),
              let a = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                     .characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil) {
        print(RTFWriter.rtf(from: a))
    }
    exit(0)
}

// MARK: - האפליקציה

enum OutputMode: String, CaseIterable {
    case html, rtf, text
    var title: String {
        switch self {
        case .html: return "HTML — שומר עיצוב (מומלץ)"
        case .rtf: return "RTF — שומר עיצוב (חלופה)"
        case .text: return "טקסט נקי"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var autoItem: NSMenuItem!
    private var markdownItem: NSMenuItem!
    private var modeItems: [NSMenuItem] = []
    private var windowKeysItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var windowKeyRefs: [EventHotKeyRef?] = []
    private var minimizedByUs: [AXUIElement] = []
    private var window: NSWindow?
    private var textView: NSTextView?
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    private let defaults = UserDefaults.standard
    private var autoMode: Bool {
        get { defaults.bool(forKey: "autoMode") }
        set { defaults.set(newValue, forKey: "autoMode") }
    }
    private var cleanMarkdown: Bool {
        get { defaults.object(forKey: "cleanMarkdown") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cleanMarkdown") }
    }
    private var windowShortcuts: Bool {
        get { defaults.object(forKey: "windowShortcuts") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "windowShortcuts") }
    }
    private var mode: OutputMode {
        get { OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "") ?? .html }
        set { defaults.set(newValue.rawValue, forKey: "outputMode") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMainMenu()
        buildStatusItem()
        registerHotKeys()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    // תפריט ראשי נסתר — נדרש כדי ש-⌘C/⌘V יעבדו בחלון ההמרה
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "אA"

        let menu = NSMenu()
        let fixItem = NSMenuItem(title: "תקן את הלוח עכשיו", action: #selector(fixClipboardAction), keyEquivalent: "v")
        fixItem.keyEquivalentModifierMask = [.control, .option]
        fixItem.target = self
        let pasteItem = NSMenuItem(title: "תקן והדבק", action: #selector(fixAndPasteAction), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = [.control, .option, .command]
        pasteItem.target = self
        let ocrItem = NSMenuItem(title: "OCR: תמונה בלוח ← טקסט רגיל", action: #selector(ocrClipboardAction), keyEquivalent: "o")
        ocrItem.keyEquivalentModifierMask = [.control, .option]
        ocrItem.target = self
        menu.addItem(fixItem)
        menu.addItem(pasteItem)
        menu.addItem(ocrItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "פורמט ההדבקה:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for m in OutputMode.allCases {
            let item = NSMenuItem(title: "   " + m.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.representedObject = m.rawValue
            item.target = self
            modeItems.append(item)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        autoItem = NSMenuItem(title: "תיקון אוטומטי בכל העתקה של עברית", action: #selector(toggleAuto), keyEquivalent: "")
        autoItem.target = self
        markdownItem = NSMenuItem(title: "המר סימוני Markdown (** ` # *)", action: #selector(toggleMarkdown), keyEquivalent: "")
        markdownItem.target = self
        menu.addItem(autoItem)
        menu.addItem(markdownItem)
        menu.addItem(.separator())
        let winItem = NSMenuItem(title: "חלון המרה…", action: #selector(showWindow), keyEquivalent: "")
        winItem.target = self
        menu.addItem(winItem)
        menu.addItem(.separator())

        let termItem = NSMenuItem(title: "פתח Terminal", action: #selector(openTerminal), keyEquivalent: "r")
        termItem.keyEquivalentModifierMask = [.command]
        termItem.target = self
        let minItem = NSMenuItem(title: "מזער / החזר את כל החלונות", action: #selector(toggleMinimizeAll), keyEquivalent: "d")
        minItem.keyEquivalentModifierMask = [.command]
        minItem.target = self
        windowKeysItem = NSMenuItem(title: "הפעל את הקיצורים ⌘R / ⌘D", action: #selector(toggleWindowShortcuts), keyEquivalent: "")
        windowKeysItem.target = self
        loginItem = NSMenuItem(title: "פתח אוטומטית בהפעלת המחשב", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(termItem)
        menu.addItem(minItem)
        menu.addItem(windowKeysItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "אודות FixHebrewPaste (גרסה \(AppInfo.version))", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "יציאה", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshChecks()
    }

    private func refreshChecks() {
        autoItem.state = autoMode ? .on : .off
        markdownItem.state = cleanMarkdown ? .on : .off
        windowKeysItem.state = windowShortcuts ? .on : .off
        loginItem.state = launchAtLogin ? .on : .off
        for item in modeItems {
            item.state = (item.representedObject as? String) == mode.rawValue ? .on : .off
        }
    }

    @objc private func toggleAuto() { autoMode.toggle(); refreshChecks() }
    @objc private func toggleMarkdown() { cleanMarkdown.toggle(); refreshChecks() }
    @objc private func selectMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = OutputMode(rawValue: raw) { mode = m }
        refreshChecks()
    }

    // MARK: לוח העתקה

    /// כותב ללוח את הגרסה המתוקנת לפי הפורמט שנבחר
    private func writeFixed(html: String?, plain: String) {
        let pb = NSPasteboard.general
        switch mode {
        case .text:
            let fixed = PlainFixer.fix(plain, cleanMarkdown: cleanMarkdown)
            pb.clearContents()
            pb.setString(fixed, forType: .string)

        case .html:
            let source = html ?? HTMLFixer.htmlFromPlain(plain, cleanMarkdown: cleanMarkdown)
            let fixed = HTMLFixer.fix(source)
            pb.clearContents()
            pb.declareTypes([.html, .string], owner: nil)
            pb.setString(fixed, forType: .html)
            pb.setString(plain, forType: .string)

        case .rtf:
            let source = html ?? HTMLFixer.htmlFromPlain(plain, cleanMarkdown: cleanMarkdown)
            guard let data = source.data(using: .utf8),
                  let attr = try? NSAttributedString(data: data,
                                                     options: [.documentType: NSAttributedString.DocumentType.html,
                                                               .characterEncoding: String.Encoding.utf8.rawValue],
                                                     documentAttributes: nil) else {
                NSSound.beep()
                return
            }
            let rtf = RTFWriter.rtf(from: attr)
            pb.clearContents()
            pb.declareTypes([.rtf, .string], owner: nil)
            pb.setData(rtf.data(using: .utf8) ?? Data(), forType: .rtf)
            pb.setString(plain, forType: .string)
        }
        lastChangeCount = pb.changeCount
        flashIcon()
    }

    @discardableResult
    private func fixClipboard() -> Bool {
        let pb = NSPasteboard.general
        let html = pb.string(forType: .html)
        let plain = pb.string(forType: .string) ?? ""
        if let h = html, h.contains(HTMLFixer.marker) { return true }   // כבר תוקן
        guard Bidi.containsRTL(plain) || Bidi.containsRTL(html ?? "") else {
            NSSound.beep()
            return false
        }
        writeFixed(html: html, plain: plain)
        return true
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard autoMode else { return }
        let html = pb.string(forType: .html)
        if let h = html, h.contains(HTMLFixer.marker) { return }
        let plain = pb.string(forType: .string) ?? ""
        guard Bidi.containsRTL(plain) else { return }
        writeFixed(html: html, plain: plain)
    }

    private func flashIcon() {
        statusItem.button?.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.statusItem.button?.title = "אA"
        }
    }

    @objc func fixClipboardAction() { fixClipboard() }

    // MARK: OCR מהלוח

    private var ocrRunning = false

    @objc func ocrClipboardAction() {
        guard !ocrRunning else { return }
        let pb = NSPasteboard.general
        guard let image = OCR.imageFromPasteboard(pb) else {
            showMessage("אין תמונה בלוח",
                        "העתק קודם תמונה או צילום מסך ללוח (למשל ⌃⇧⌘4), ואז הפעל OCR שוב.")
            return
        }
        ocrRunning = true
        statusItem.button?.title = "…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try OCR.recognize(image) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ocrRunning = false
                self.statusItem.button?.title = "אA"
                switch result {
                case .success(let r):
                    pb.clearContents()
                    pb.setString(r.text, forType: .string)
                    self.lastChangeCount = pb.changeCount   // שהתיקון האוטומטי לא ימיר אותו ל-HTML
                    self.flashIcon()
                    if r.engine == .vision && !OCR.supportsHebrew
                        && !UserDefaults.standard.bool(forKey: "warnedNoHebrewOCR") {
                        UserDefaults.standard.set(true, forKey: "warnedNoHebrewOCR")
                        self.showMessage("הטקסט הועתק — אבל בלי תמיכה בעברית",
                                         OCR.hebrewHelp + "\n\nטקסט באנגלית מזוהה גם בלי זה. ההודעה הזו לא תוצג שוב.")
                    }
                case .failure:
                    let hint = OCR.hebrewAvailable ? "" : "\n\n" + OCR.hebrewHelp
                    self.showMessage("לא נמצא טקסט בתמונה", "נסה תמונה חדה יותר או צילום מסך של אזור קטן יותר." + hint)
                }
            }
        }
    }

    private func showMessage(_ title: String, _ text: String) {
        NSSound.beep()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    // MARK: אודות

    @objc func showAbout() {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                   .foregroundColor: NSColor.labelColor]
        credits.append(NSAttributedString(string:
            "תיקון טקסט עברית/אנגלית להדבקה ב-PowerPoint, OCR מהלוח וקיצורי חלונות.\n\n" +
            "⌃⌥V  תקן את הלוח\n⌃⌥⌘V  תקן והדבק\n⌃⌥O  OCR מהלוח\n⌘R  Terminal    ⌘D  מזעור חלונות\n\n",
            attributes: body))
        var link = body
        link[.link] = URL(string: AppInfo.repoURL)!
        credits.append(NSAttributedString(string: "github.com/udiweinstein/FixHebrewPaste", attributes: link))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FixHebrewPaste",
            .applicationVersion: AppInfo.version,
            .version: "",
            .credits: credits,
        ])
    }

    @objc func fixAndPasteAction() {
        guard fixClipboard() else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }  // macOS יציג בקשת הרשאת נגישות
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vKey = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    func handleHotKey(_ id: UInt32) {
        switch id {
        case 1: fixClipboardAction()
        case 2: fixAndPasteAction()
        case 3: openTerminal()
        case 4: toggleMinimizeAll()
        case 5: ocrClipboardAction()
        default: break
        }
    }

    // MARK: קיצורי מקשים גלובליים (לא דורשים הרשאה)

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = hkID.id
            DispatchQueue.main.async { AppDelegate.shared?.handleHotKey(id) }
            return noErr
        }, 1, &spec, nil, nil)

        _ = registerKey(id: 1, keyCode: kVK_ANSI_V, mods: controlKey | optionKey)            // ⌃⌥V  — תקן את הלוח
        _ = registerKey(id: 2, keyCode: kVK_ANSI_V, mods: controlKey | optionKey | cmdKey)   // ⌃⌥⌘V — תקן והדבק
        _ = registerKey(id: 5, keyCode: kVK_ANSI_O, mods: controlKey | optionKey)            // ⌃⌥O  — OCR מהלוח
        setWindowShortcuts(enabled: windowShortcuts)
    }

    private func registerKey(id: UInt32, keyCode: Int, mods: Int) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: OSType(0x48465058), id: id)
        RegisterEventHotKey(UInt32(keyCode), UInt32(mods), hk, GetApplicationEventTarget(), 0, &ref)
        return ref
    }

    // ⌘R ו-⌘D תופסים את המקשים בכל המערכת, לכן אפשר לכבות אותם מהתפריט.
    // קודי המקשים פיזיים — עובד גם כשהמקלדת על עברית.
    private func setWindowShortcuts(enabled: Bool) {
        for ref in windowKeyRefs { if let r = ref { UnregisterEventHotKey(r) } }
        windowKeyRefs = []
        guard enabled else { return }
        windowKeyRefs.append(registerKey(id: 3, keyCode: kVK_ANSI_R, mods: cmdKey))   // ⌘R — Terminal
        windowKeyRefs.append(registerKey(id: 4, keyCode: kVK_ANSI_D, mods: cmdKey))   // ⌘D — מזעור כל החלונות
    }

    // MARK: Terminal

    @objc func openTerminal() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }

    // MARK: מזעור / שחזור כל החלונות (כמו Win+D: לחיצה שנייה מחזירה)

    private func axTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    private static func isMinimized(_ w: AXUIElement) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &v)
        return (v as? Bool) == true
    }

    @objc func toggleMinimizeAll() {
        guard axTrusted(prompt: true) else { return }   // דורש הרשאת נגישות

        let previous = minimizedByUs
        minimizedByUs = []

        // לחיצה שנייה: אם חלונות שמזערנו עדיין ממוזערים — מחזירים אותם
        if previous.contains(where: AppDelegate.isMinimized) {
            DispatchQueue.global(qos: .userInitiated).async {
                for w in previous.reversed() {
                    AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
            }
            return
        }

        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid() }
            .map { $0.processIdentifier }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var done: [AXUIElement] = []
            for pid in pids {
                let axApp = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(axApp, 1.0)
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                      let windows = value as? [AXUIElement] else { continue }
                for w in windows {
                    var sub: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sub)
                    guard (sub as? String) == (kAXStandardWindowSubrole as String) else { continue }
                    if AppDelegate.isMinimized(w) { continue }
                    if AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                        done.append(w)
                    }
                }
            }
            let result = done
            DispatchQueue.main.async { self?.minimizedByUs = result }
        }
    }

    // MARK: הפעלה אוטומטית עם הכניסה למחשב

    private var launchAtLogin: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch {
                NSSound.beep()
            }
        }
        refreshChecks()
    }

    @objc private func toggleWindowShortcuts() {
        windowShortcuts.toggle()
        setWindowShortcuts(enabled: windowShortcuts)
        refreshChecks()
    }

    // MARK: חלון המרה ידני (לטקסט שמקלידים/מדביקים)

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "המרת טקסט עברית/אנגלית ל-PowerPoint"
            w.isReleasedWhenClosed = false

            let scroll = NSTextView.scrollableTextView()
            let tv = scroll.documentView as! NSTextView
            tv.isRichText = false
            tv.allowsUndo = true
            tv.font = .systemFont(ofSize: 15)
            tv.baseWritingDirection = .rightToLeft
            tv.alignment = .right
            textView = tv

            let convert = NSButton(title: "המר והעתק ללוח", target: self, action: #selector(convertWindowText))
            convert.bezelColor = .controlAccentColor
            let buttons = NSStackView(views: [convert])
            buttons.orientation = .horizontal

            let content = NSView()
            for v in [scroll, buttons] as [NSView] {
                v.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(v)
            }
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
                buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ])
            w.contentView = content
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func convertWindowText() {
        guard let tv = textView, !tv.string.isEmpty else { return }
        writeFixed(html: nil, plain: tv.string)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
