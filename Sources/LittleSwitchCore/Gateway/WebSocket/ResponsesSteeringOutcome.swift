/// Only an intent already entered in the connection's ledger can return an
/// owned failure. Its bounded connection drain owns the single failure signal;
/// returning this outcome does not claim that delivery to a lost client worked.
package enum ResponsesSteeringOutcome: Sendable {
    case forwarded
    case connectionOwnedFailure
}
