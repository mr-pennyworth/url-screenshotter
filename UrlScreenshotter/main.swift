import AppKit
import ArgumentParser
import Foundation
import WebKit

let app = NSApplication.shared

struct UrlScreenshotter: ParsableCommand {
  private(set) static var configuration =
    CommandConfiguration(commandName: "UrlScreenshotter")

  @Option(name: .shortAndLong, help: "Width of desired screenshot in pixels.")
  var width: Int = Int(NSScreen.main!.frame.width)

  @Option(name: .shortAndLong, help: "Height of desired screenshot in pixels.")
  var height: Int = Int(NSScreen.main!.frame.height)

  @Option(name: .shortAndLong, help: "Delay in seconds before taking the screenshot.")
  var delay: Int = 0

  @Option(name: .long, help: "The directory where the screenshot should be saved.")
  var baseDir: String = "/tmp"

  @Argument(help: "The http(s) URL whose screenshot is to be taken.")
  var url: String


  func run() {
    let screenshotter = Screenshotter(
      url: url,
      width: width,
      height: height,
      baseDir: URL(fileURLWithPath: baseDir, isDirectory: true),
      delay: delay
    )
    app.delegate = screenshotter
    app.run()
  }
}

struct Screenshot: Codable {
  let title: String?
  let path: String
}

struct Result: Codable {
  let error: String?
  let screenshot: Screenshot?

  func toJson() -> String {
    let encoder = JSONEncoder.init()
    if #available(OSX 10.15, *) {
      encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    } else {
      encoder.outputFormatting = [.prettyPrinted]
    }
    return try! String(data: encoder.encode(self), encoding: .utf8)!
  }
}


class Screenshotter: NSObject, NSApplicationDelegate, WKNavigationDelegate {
  var url: URL!
  var window: NSWindow!
  var width: Int!
  var height: Int!
  var baseDir: URL!
  var delay: Int!

  init(url: String, width: Int, height: Int, baseDir: URL, delay: Int) {
    super.init()
    self.baseDir = baseDir
    self.width = width
    self.height = height
    self.delay = delay
    encodeIfNeededAndAssign(url)
    self.window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false,
      screen: nil
    )
  }

  func encodeIfNeededAndAssign(_ urlStr: String) {
    // we don't know whether the string we have is the raw url
    // or whether it is an url after percent encoding
    // (depending on what you set in firefox, copying from firefox
    //  address bar could result in either of the two types)
    //
    // here, we make a reasonable assumption that the URL isn't
    // triple-encoded. (decoding already decoded has no effect)
    if let decoded = urlStr.removingPercentEncoding?.removingPercentEncoding {
      if let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
        if let url = URL(string: encoded) {
          self.url = url
          return
        }
      }
    }
    exit(Result(error: "'\(urlStr)' malformed.", screenshot: nil))
  }

  func exit(_ result: Result) {
    print(result.toJson())
    fflush(stdout)
    app.terminate(nil)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let config = WKSnapshotConfiguration()
    config.rect = CGRect(x: 0, y: 0, width: width, height: height)
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.delay)) {
      webView.takeSnapshot(with: config) { image, error in
        if let image = image {
          let imageFileName = "\(UUID().uuidString).png"
          let imagePath = self.baseDir.appendingPathComponent(imageFileName)
          self.write(image: image, file: imagePath)
          let result = Result(
            error: nil,
            screenshot: Screenshot(
              title: webView.title,
              path: imagePath.path
            )
          )
          self.exit(result)
        } else {
          let result = Result(error: error?.localizedDescription, screenshot: nil)
          self.exit(result)
        }
      }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    let result = Result(error: error.localizedDescription, screenshot: nil)
    exit(result)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    let result = Result(error: error.localizedDescription, screenshot: nil)
    exit(result)
  }


  func applicationDidFinishLaunching(_ notification: Notification) {
    let configuration = WKWebViewConfiguration()
    let webview = WKWebView(frame: .zero, configuration: configuration)
    webview.customUserAgent = (
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:83.0) "
        + "Gecko/20100101 Firefox/83.0"
    )

    window.contentView = webview
    webview.navigationDelegate = self
    webview.load(URLRequest(url: self.url))
    // window.makeKeyAndOrderFront(nil)
  }

  func write(image: NSImage, file: URL) {
    let cgRef = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    let newRep = NSBitmapImageRep.init(cgImage: cgRef!)
    newRep.size = image.size
    let pngData = newRep.representation(using: .png, properties: .init())
    try! pngData!.write(to: file)
  }
}


UrlScreenshotter.main()
