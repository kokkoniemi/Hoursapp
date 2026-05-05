import Foundation

enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var inRecord = false

        let scalars = Array(text.unicodeScalars)
        var i = 0
        let n = scalars.count

        while i < n {
            let c = scalars[i]

            if inQuotes {
                if c == "\"" {
                    if i + 1 < n, scalars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    field.unicodeScalars.append(c)
                    i += 1
                }
                continue
            }

            switch c {
            case "\"":
                inQuotes = true
                inRecord = true
                i += 1
            case ",":
                row.append(field)
                field = ""
                inRecord = true
                i += 1
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                inRecord = false
                i += 1
            case "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                inRecord = false
                if i + 1 < n, scalars[i + 1] == "\n" {
                    i += 2
                } else {
                    i += 1
                }
            default:
                field.unicodeScalars.append(c)
                inRecord = true
                i += 1
            }
        }

        if inRecord {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }
            .joined(separator: "\n")
            + (rows.isEmpty ? "" : "\n")
    }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
