import OrderedCollections

/// A JSON value.
///
/// This type represents a JSON value, which can be a string, number, object, array, boolean, or null.
///
/// You can create a `Value` instance using the enum cases, or by using the provided
/// `ExpressibleBy*Literal` conformances.
/// ```swift
///     let value: Value = "Hello, world!"
///     let value: Value = 42
///     let value: Value = 42.0
///     let value: Value = ["key": "value"]
///     let value: Value = ["Hello", "world"]
///     let value: Value = true
///     let value: Value = false
///     let value: Value = nil
/// ```
///
/// Object values use insertion-ordered ``JSONObject`` storage with exact decoded
/// UTF-8 key identity. Equality remains order-insensitive; canonically equivalent
/// spellings are distinct JSON member names.
///
/// - SeeAlso: ``JSONType``
public enum JSONValue: Hashable, Equatable, Sendable {
  case string(String)
  case numberLiteral(JSONNumberLiteral)
  case object(JSONObject)
  case array([Self])
  case boolean(Bool)
  case null

  public var primitive: JSONType {
    switch self {
    case .string: return .string
    case .numberLiteral(let number): return number.isInteger ? .integer : .number
    case .object: return .object
    case .array: return .array
    case .boolean: return .boolean
    case .null: return .null
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch self {
    case .string(let value):
      hasher.combine(0)
      // String equality (below) compares unicode scalars verbatim — *not*
      // Swift's canonical String equality — so the hash must use the same
      // representation. Hashing the scalar array preserves the contract
      // `lhs == rhs` ⇒ `lhs.hashValue == rhs.hashValue`.
      hasher.combine(Array(value.unicodeScalars))
    case .numberLiteral(let value):
      hasher.combine(1)
      hasher.combine(value)
    case .object(let dictionary):
      hasher.combine(2)
      hasher.combine(dictionary)
    case .array(let array):
      hasher.combine(3)
      hasher.combine(array)
    case .boolean(let value):
      hasher.combine(4)
      hasher.combine(value)
    case .null:
      hasher.combine(5)
    }
  }

  public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.string(let lhsValue), .string(let rhsValue)):
      // Swift uses canonical equality for strings, but JSON string equality is based on Unicode scalar equality.
      // For example, "ä" (U+00E4) and "ä" (U+0061 U+0308) are canonically equal in Swift, but not in JSON.
      // See `const.json` test cases in JSON Schema Test Suite for more details.
      return lhsValue.unicodeScalars.elementsEqual(rhsValue.unicodeScalars)
    case (.numberLiteral(let lhsValue), .numberLiteral(let rhsValue)):
      return lhsValue == rhsValue
    case (.object(let lhsValue), .object(let rhsValue)):
      return lhsValue == rhsValue
    case (.array(let lhsValue), .array(let rhsValue)):
      return lhsValue == rhsValue
    case (.boolean(let lhsValue), .boolean(let rhsValue)):
      return lhsValue == rhsValue
    case (.null, .null):
      return true
    default:
      return false
    }
  }
}

extension JSONValue {
  /// Constructs a JSON integer without losing precision.
  public static func integer(_ value: Int) -> Self {
    .numberLiteral(JSONNumberLiteral(value))
  }

  /// Constructs a number from a finite Swift double's decimal representation.
  ///
  /// - Precondition: `value` is finite. For untrusted values, use the throwing
  ///   ``JSONNumberLiteral/init(_:)-(Double)`` initializer instead.
  public static func number(_ value: Double) -> Self {
    do {
      return .numberLiteral(try JSONNumberLiteral(value))
    } catch {
      preconditionFailure("Cannot construct a JSON number: \(error)")
    }
  }

  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// The original, validated JSON number token.
  public var numberLiteral: JSONNumberLiteral? {
    if case .numberLiteral(let value) = self { return value }
    return nil
  }

  /// A finite double approximation, or `nil` for nonnumbers or range failures.
  /// Use ``JSONNumberLiteral/doubleValue()`` to receive conversion errors.
  public var number: Double? {
    try? numberLiteral?.doubleValue()
  }

  /// An exact Swift integer, regardless of the number's original spelling.
  public var integer: Int? {
    try? numberLiteral?.integerValue()
  }

  public var object: JSONObject? {
    if case .object(let value) = self { return value }
    return nil
  }

  public var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  public var boolean: Bool? {
    if case .boolean(let value) = self { return value }
    return nil
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }
}

/// Insertion-ordered JSON fields with exact decoded UTF-8 key identity.
/// Swift's String equality normalizes Unicode; JSON member names must not.
/// String subscripts expose the original spelling without normalizing storage.
public struct JSONObject: RandomAccessCollection, ExpressibleByDictionaryLiteral, Sendable, Hashable {
  public typealias Index = Int
  public typealias Element = (key: String, value: JSONValue)
  public typealias Key = String
  public typealias Value = JSONValue

  private struct ExactKey: Hashable, Sendable {
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(Array(text.utf8))
    }
  }

  private var storage: OrderedDictionary<ExactKey, JSONValue> = [:]

  public init() {}

  public init<S: Sequence>(uniqueKeysWithValues elements: S) where S.Element == (String, JSONValue) {
    storage = OrderedDictionary(uniqueKeysWithValues: elements.map { (ExactKey(text: $0.0), $0.1) })
  }

  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    reserveCapacity(elements.count)
    for (key, value) in elements { self[key] = value }
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { storage.count }
  public func index(after index: Int) -> Int { index + 1 }
  public func index(before index: Int) -> Int { index - 1 }

  public subscript(position: Int) -> Element {
    let pair = storage.elements[position]
    return (pair.key.text, pair.value)
  }

  public subscript(key: String) -> JSONValue? {
    get { storage[ExactKey(text: key)] }
    set { storage[ExactKey(text: key)] = newValue }
  }

  public var keys: [String] { storage.keys.map(\.text) }
  public var values: [JSONValue] { Array(storage.values) }

  public mutating func reserveCapacity(_ capacity: Int) {
    storage.reserveCapacity(capacity)
  }

  @discardableResult
  public mutating func removeValue(forKey key: String) -> JSONValue? {
    storage.removeValue(forKey: ExactKey(text: key))
  }

  public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Self {
    var result = Self()
    for pair in self where try isIncluded(pair) { result[pair.key] = pair.value }
    return result
  }

  public func mapValues(_ transform: (JSONValue) throws -> JSONValue) rethrows -> Self {
    try Self(uniqueKeysWithValues: map { ($0.key, try transform($0.value)) })
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return lhs.allSatisfy { rhs[$0.key] == $0.value }
  }

  public func hash(into hasher: inout Hasher) {
    var combined = 0
    for (key, value) in storage {
      var pairHasher = Hasher()
      pairHasher.combine(key)
      pairHasher.combine(value)
      combined ^= pairHasher.finalize()
    }
    hasher.combine(combined)
  }
}

extension JSONValue {
  public var numeric: Double? {
    number
  }
}

extension JSONValue: CustomStringConvertible {
  public var description: String {
    switch self {
    case .string(let value):
      return "\"\(value)\""
    case .numberLiteral(let value):
      return value.rawValue
    case .object(let value):
      let pairs = value.map { "\"\($0.key)\": \($0.value.description)" }
      return "{\(pairs.joined(separator: ", "))}"
    case .array(let value):
      return "[\(value.map { $0.description }.joined(separator: ", "))]"
    case .boolean(let value):
      return value ? "true" : "false"
    case .null:
      return "null"
    }
  }
}
