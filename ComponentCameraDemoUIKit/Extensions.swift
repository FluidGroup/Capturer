import UIKit

extension UIButton {

  @available(iOS 14, *)
  static func make(title: String, handler: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system, primaryAction: .init(handler: { _ in
      handler()
    }))

    button.setTitle(title, for: .normal)

    return button
  }

}
