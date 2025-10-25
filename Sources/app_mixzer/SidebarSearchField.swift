import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// A sidebar search field implemented with `NSSearchField` so we can programmatically focus it.
public struct SidebarSearchField: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String

    public init(text: Binding<String>, placeholder: String = "Search") {
        self._text = text
        self.placeholder = placeholder
    }

    public func makeNSView(context: Context) -> NSSearchField {
        let sf = NSSearchField(frame: .zero)
        sf.placeholderString = placeholder
        sf.delegate = context.coordinator
        sf.sendsSearchStringImmediately = true
        sf.cell?.usesSingleLineMode = true

        // Observe focus requests
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(Coordinator.focusSearchField),
                                               name: .appMixzerFocusSidebarSearch,
                                               object: nil)

        return sf
    }

    public func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor public class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SidebarSearchField
        weak var searchField: NSSearchField?

        init(_ parent: SidebarSearchField) {
            self.parent = parent
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let sf = obj.object as? NSSearchField else { return }
            DispatchQueue.main.async {
                self.parent.text = sf.stringValue
            }
        }

        @objc func focusSearchField() {
            DispatchQueue.main.async {
                guard let sf = self.searchField ?? NSApp.keyWindow?.contentView?.subviews.compactMap({ $0 as? NSSearchField }).first else {
                    // try to find in keyWindow's responder chain
                    if let responder = NSApp.keyWindow?.firstResponder as? NSSearchField {
                        responder.window?.makeFirstResponder(responder)
                    }
                    return
                }
                sf.window?.makeFirstResponder(sf)
            }
        }
    }
}

public extension Notification.Name {
    static let appMixzerFocusSidebarSearch = Notification.Name("appMixzer.focusSidebarSearch")
}
