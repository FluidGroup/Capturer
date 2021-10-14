import StorybookKit

let book = Book(title: "MyBook") {
  BookSection(title: "Basics") {
    if #available(iOS 14, *) {
      BookPush(title: "iOS 14") {
        DemoInputPreviewClassicViewController()
      }
    }
    if #available(iOS 15, *) {
      BookPush(title: "Preview") {
        DemoInputPreviewViewController()
      }
    }
  }
}
