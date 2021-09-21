//
//  Multicaster.swift
//  ComponentCamera
//
//  Created by muukii on 2020/10/17.
//

import Foundation

public final class MulticastCancellable: Hashable {

  public static func == (lhs: MulticastCancellable, rhs: MulticastCancellable) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }

  private let _onCancel: (MulticastCancellable) -> Void

  init(onCancel: @escaping (MulticastCancellable) -> Void) {
    self._onCancel = onCancel
  }

  public func cancel() {
    _onCancel(self)
  }
}

public final class EventBus<Event> {

  public typealias Handler = (Event) -> Void

  public init() {

  }

  var targets: ContiguousArray<(MulticastCancellable, Handler)> = .init()

  public func addHandler(_ handler: @escaping Handler) -> MulticastCancellable {
    let cancellable = MulticastCancellable { [weak self] cancellable in
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
