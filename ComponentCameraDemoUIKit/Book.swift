import StorybookKit

let book = Book(title: "MyBook") {
  BookSection(title: "Basics") {
    if #available(iOS 14, *) {
      BookPush(title: "Preview") {
        DemoInputPreviewViewController()
      }
    }
  }
}
