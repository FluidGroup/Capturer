
import Foundation
import os

public final class EventBusCancellable: Hashable, @unchecked Sendable {

  public static func == (lhs: EventBusCancellable, rhs: EventBusCancellable) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }


  private let _onCancel: (EventBusCancellable) -> Void

  init(onCancel: @escaping (EventBusCancellable) -> Void) {
    self._onCancel = onCancel
  }

  public func cancel() {
    _onCancel(self)
  }
}

/// [non-atomic]
public actor EventBus<Element : Sendable> {
  public typealias Handler = @Sendable (Element) -> Void

  public var hasTargets: Bool = false

  public init() {
  }

  private var targets: ContiguousArray<(cancellable: EventBusCancellable, handler: Handler)> = .init() {
    didSet {
      hasTargets = targets.isEmpty == false
    }
  }

  private func removeTarget(matchingCancellable: EventBusCancellable) {
    self.targets.removeAll { $0.cancellable == matchingCancellable }
  }

  public func addHandler(_ handler: @escaping Handler) -> EventBusCancellable {

    let cancellable = EventBusCancellable { [weak self] cancellable in
      guard let self = self else { return }
      Task {
        await self.removeTarget(matchingCancellable: cancellable)
      }
    }
    targets.append((cancellable, handler))
    return cancellable
  }

  public func emit(element: Element) {
    for target in targets {
      target.handler(element)
    }
  }

}
