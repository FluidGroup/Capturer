import StorybookKit

let book = Book(title: "MyBook") {
  BookSection(title: "Basics") {
    BookPush(title: "Preview") {
      DemoInputPreviewViewController()
    }
  }
}
