import Foundation

extension JSONValue {
  /// Options for ``JSONValue/serialized(options:)``.
  public struct SerializationOptions: Sendable, Hashable {
    public var prettyPrinted: Bool
    /// The string used to indent each pretty-printed level. Defaults to two
    /// spaces, matching `JSONEncoder`'s default.
    public var indent: String
    public init(
      prettyPrinted: Bool = false,
      indent: String = "  "
    ) {
      self.prettyPrinted = prettyPrinted
      self.indent = indent
    }

    public static let compact = SerializationOptions(prettyPrinted: false)
    public static let pretty = SerializationOptions(prettyPrinted: true)
  }

  /// Serializes this value to a JSON-encoded `String`.
  ///
  /// Object keys are emitted in their stored (insertion) order, so output is
  /// fully deterministic across processes — `JSONEncoder` does not preserve
  /// insertion order for keyed containers, so use this when you need
  /// reproducible bytes (snapshot tests, generated artifacts, signed
  /// payloads). See issue #149.
  ///
  /// Number tokens are emitted verbatim, including values outside the range
  /// of `Double` or `Decimal`. Non-finite Swift values cannot enter this tree.
  public func serialized(options: SerializationOptions = .compact) throws -> String {
    var out = ""
    try write(to: &out, level: 0, options: options)
    return out
  }

  /// UTF-8 encoded form of ``serialized(options:)``.
  public func serializedData(options: SerializationOptions = .compact) throws -> Data {
    Data(try serialized(options: options).utf8)
  }

  private func write(
    to out: inout String,
    level: Int,
    options: SerializationOptions
  ) throws {
    switch self {
    case .null:
      out.append("null")
    case .boolean(let b):
      out.append(b ? "true" : "false")
    case .numberLiteral(let number):
      out.append(number.rawValue)
    case .string(let s):
      JSONValue.appendQuoted(s, to: &out)
    case .array(let array):
      if array.isEmpty {
        out.append("[]")
        return
      }
      out.append("[")
      for (i, element) in array.enumerated() {
        if options.prettyPrinted {
          out.append("\n")
          out.append(String(repeating: options.indent, count: level + 1))
        }
        try element.write(to: &out, level: level + 1, options: options)
        if i < array.count - 1 {
          out.append(",")
        }
      }
      if options.prettyPrinted {
        out.append("\n")
        out.append(String(repeating: options.indent, count: level))
      }
      out.append("]")
    case .object(let dictionary):
      if dictionary.isEmpty {
        out.append("{}")
        return
      }
      out.append("{")
      var first = true
      for (key, value) in dictionary {
        if !first {
          out.append(",")
        }
        first = false
        if options.prettyPrinted {
          out.append("\n")
          out.append(String(repeating: options.indent, count: level + 1))
        }
        JSONValue.appendQuoted(key, to: &out)
        out.append(options.prettyPrinted ? " : " : ":")
        try value.write(to: &out, level: level + 1, options: options)
      }
      if options.prettyPrinted {
        out.append("\n")
        out.append(String(repeating: options.indent, count: level))
      }
      out.append("}")
    }
  }

  private static func appendQuoted(_ string: String, to out: inout String) {
    out.append("\"")
    var utf8Source = string
    utf8Source.withUTF8 { bytes in
      var segmentStart = 0
      for index in bytes.indices {
        let byte = bytes[index]
        guard byte < 0x20 || byte == 0x22 || byte == 0x5C else { continue }
        if segmentStart < index {
          out.append(String(decoding: bytes[segmentStart..<index], as: UTF8.self))
        }
        switch byte {
        case 0x22: out.append("\\\"")
        case 0x5C: out.append("\\\\")
        case 0x0A: out.append("\\n")
        case 0x0D: out.append("\\r")
        case 0x09: out.append("\\t")
        case 0x08: out.append("\\b")
        case 0x0C: out.append("\\f")
        default: out.append(String(format: "\\u%04x", UInt32(byte)))
        }
        segmentStart = index + 1
      }
      if segmentStart == 0 {
        out.append(string)
      } else if segmentStart < bytes.count {
        out.append(String(decoding: bytes[segmentStart..<bytes.count], as: UTF8.self))
      }
    }
    out.append("\"")
  }
}
