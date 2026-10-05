/// RFC 4180-style CSV parsing: quoted fields, escaped quotes ("") and CRLF line endings.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                guard character == "\"" else {
                    field.append(character)
                    continue
                }
                // A doubled quote is a literal quote; anything else closes the quoted section.
                let next = iterator.next()
                if next == "\"" {
                    field.append("\"")
                } else {
                    inQuotes = false
                    pending = next
                }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",": endField()
            case "\n", "\r\n", "\r": endRow()  // "\r\n" is a single Character in Swift
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
