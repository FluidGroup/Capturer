import StorybookKit

let book = Book(title: "MyBook") {
  BookSection(title: "Basics") {
    if #available(iOS 15, *) {
      BookPush(title: "Preview") {
        DemoInputPreviewViewController()
      }
    }
  }
}
