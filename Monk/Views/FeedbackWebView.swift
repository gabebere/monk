import SwiftUI
import WebKit

struct FeedbackWebView: UIViewRepresentable {
    let projectId: String
    let userId: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let signature: String?
    let onClose: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "userjotClose")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "userjotClose" {
                onClose()
            }
        }
    }

    private var html: String {
        let signatureField: String = {
            guard let signature, !signature.isEmpty else { return "" }
            return ",\n                  signature: '\(escape(signature))'"
        }()
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            body {
              margin: 0;
              padding: 0;
              background: #0a0a0f;
              color: white;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            #closeBar {
              display: flex;
              align-items: center;
              justify-content: flex-end;
              padding: 10px 14px;
              background: rgba(255,255,255,0.04);
              border-bottom: 1px solid rgba(255,255,255,0.1);
              position: sticky;
              top: 0;
              z-index: 10;
            }
            #closeButton {
              appearance: none;
              border: 1px solid rgba(255,255,255,0.2);
              background: rgba(255,255,255,0.08);
              color: white;
              border-radius: 10px;
              padding: 8px 12px;
              font-weight: 600;
              cursor: pointer;
            }
            #closeButton:active {
              transform: scale(0.98);
            }
          </style>
          <script>
            window.$ujq = window.$ujq || [];
            window.uj = window.uj || new Proxy({}, {
              get: (_, p) => (...a) => window.$ujq.push([p, ...a])
            });
            document.head.appendChild(Object.assign(document.createElement('script'), {
              src: 'https://cdn.userjot.com/sdk/v2/uj.js',
              type: 'module',
              async: true
            }));
          </script>
        </head>
        <body style="background:#0a0a0f;color:white;">
          <div id="closeBar">
            <button id="closeButton">Close</button>
          </div>
          <div id="app"></div>
          <script>
            document.getElementById('closeButton').addEventListener('click', () => {
              try {
                window.webkit?.messageHandlers?.userjotClose?.postMessage('close');
              } catch (e) {
                console.log('close handler not available', e);
              }
            });
            (async () => {
              try {
                uj.init('\(projectId)');
                uj.identify({
                  id: '\(escape(userId))',
                  email: '\(escape(email ?? ""))',
                  firstName: '\(escape(firstName ?? ""))',
                  lastName: '\(escape(lastName ?? ""))'\(signatureField)
                });
                uj.showWidget({ section: 'feedback' });
              } catch (err) {
                document.body.innerHTML = '<pre style="color:white;">UserJot init error: ' + err + '</pre>';
              }
            })();
          </script>
        </body>
        </html>
        """
    }
}

private func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}
