
import Foundation

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

/// Hands every element to every handler, synchronously, on the thread that emits it.
///
/// This is the delegate model AVFoundation itself uses, and it is what keeps a frame pipeline
/// honest: a handler runs while the producer waits, so a slow handler costs the producer frames
/// — the camera drops them, a video source skips to the current one — and nothing is ever queued
/// up behind it. Handlers should therefore do little: take the element, hand it to their own
/// queue, return. A handler added after an element was emitted does not see that element; a
/// handler cancelled during an emit may still receive that one element.
public final class EventBus<Element: Sendable>: @unchecked Sendable {
  public typealias Handler = @Sendable (Element) -> Void

  private let lock = NSLock()
  private var targets: ContiguousArray<(cancellable: EventBusCancellable, handler: Handler)> = .init()

  public init() {
  }

  /// Whether anyone is listening — a producer can skip work that nobody would receive.
  public var hasTargets: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !targets.isEmpty
  }

  public func addHandler(_ handler: @escaping Handler) -> EventBusCancellable {
    let cancellable = EventBusCancellable { [weak self] cancellable in
      self?.removeTarget(matchingCancellable: cancellable)
    }
    lock.lock()
    targets.append((cancellable, handler))
    lock.unlock()
    return cancellable
  }

  public func emit(element: Element) {
    lock.lock()
    let handlers = targets
    lock.unlock()
    for target in handlers {
      target.handler(element)
    }
  }

  private func removeTarget(matchingCancellable: EventBusCancellable) {
    lock.lock()
    targets.removeAll { $0.cancellable == matchingCancellable }
    lock.unlock()
  }
}
