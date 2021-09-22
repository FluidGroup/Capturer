import Foundation

open class _StatefulObjectBase: Hashable {

  public static func == (lhs: _StatefulObjectBase, rhs: _StatefulObjectBase) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }

}
