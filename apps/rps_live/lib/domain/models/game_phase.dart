/// The state-machine phases of a single "Tú vs. IA" round.
///
/// Drives the countdown -> reveal -> result UI without embedding timing or
/// widget concerns in the domain layer. The owning view model
/// (`ui/features/vs_ai/view_models`) is responsible for transitioning
/// between phases on a timer/user action.
enum GamePhase {
  /// No round in progress; camera may still be live for the confidence
  /// preview, but no countdown is running.
  idle,

  /// 3-2-1 countdown is running; the classifier keeps sampling frames but
  /// the player's committed move is not locked in until it reaches zero.
  countdown,

  /// Countdown hit zero: both the player's and the AI's moves are revealed
  /// simultaneously.
  revealing,

  /// Result (win/lose/tie) is computed and shown; scoreboard has been
  /// updated and the round can be persisted to history.
  result,
}
