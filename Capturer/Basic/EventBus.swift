
import Foundation

public final class EventBusCancellable: Hashable {

  public static func == (lhs: EventBusCancellable, rhs: EventBusCancellable) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }

  private var isAutoCancelEnabled: Bool = false

  private let _onCancel: (EventBusCancellable) -> Void

  init(onCancel: @escaping (EventBusCancellable) -> Void) {
    self._onCancel = onCancel
  }

  public func cancel() {
    _onCancel(self)
  }

  /// Enables auto cancellation on deinitialization.
  /// [non-atomic]
  public func enableAutoCancel() {
    isAutoCancelEnabled = true
  }

  deinit {
    if isAutoCancelEnabled {
      cancel()
    }
  }
}

/// [non-atomic]
public final class EventBus<Event> {

  public typealias Handler = (Event) -> Void

  public init() {

  }

  var targets: ContiguousArray<(EventBusCancellable, Handler)> = .init()

  public func addHandler(_ handler: @escaping Handler) -> EventBusCancellable {
    let cancellable = EventBusCancellable { [weak self] cancellable in
      guard let self = self else { return }
      self.targets.removeAll { $0.0 == cancellable }
    }
    targets.append((cancellable, handler))
    return cancellable
  }

  public func emit(event: Event) {
    targets.forEach {
      $0.1(event)
    }
  }

}
