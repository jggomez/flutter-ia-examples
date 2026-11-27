/// Enumeration of lifecycle states for the Snap & Sell session.
enum SellingFlowStatus {
  /// Waiting on the entry screen for the user to pick or capture an item photo.
  idle,

  /// Native camera or gallery picker is open for the initial item photo.
  capturingInitialPhoto,

  /// Initial item photo is being analyzed by the remote A2UI agent.
  analyzingItem,

  /// An A2UI surface is active and interactive.
  activeSurface,

  /// A user action or follow-up photo is being processed by the remote A2UI agent.
  submittingAction,

  /// The marketplace listing has been published.
  published,

  /// An error occurred during capture or agent communication.
  error,
}

/// Alias used by session state consumers.
typedef SellingSessionStatus = SellingFlowStatus;
