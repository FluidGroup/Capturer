# Capturer
A wrapper for AVCaptureSession - The way easier to use the Camera.

## Setting up

```swift
let captureBody = CaptureBody(
  configuration: .init {
    $0.sessionPreset = .photo
  }
)
```

```swift
let input = CameraInput.wideAngleCamera(position: .back)

await captureBody.attach(input: input)

let previewOutput = PreviewOutput()
let photoOutput = PhotoOutput()

await captureBody.attach(output: previewOutput)
await captureBody.attach(output: photoOutput)

let previewView = PixelBufferView()
previewView.attach(output: previewOutput)

captureBody.start()
```

## License

MIT
