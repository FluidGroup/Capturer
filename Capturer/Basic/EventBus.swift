
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
public final class EventBus<Element> {

  public typealias Handler = (Element) -> Void

  public var hasTargets: Bool = false

  public init() {

  }

  private var targets: ContiguousArray<(EventBusCancellable, Handler)> = .init() {
    didSet {
      hasTargets = targets.isEmpty == false
    }
  }

  public func addHandler(_ handler: @escaping Handler) -> EventBusCancellable {

    let cancellable = EventBusCancellable { [weak self] cancellable in
      guard let self = self else { return }
      self.targets.removeAll { $0.0 == cancellable }
    }

    targets.append((cancellable, handler))
    return cancellable
  }

  public func emit(element: Element) {
    for target in targets {
      target.1(element)
    }
  }

}
