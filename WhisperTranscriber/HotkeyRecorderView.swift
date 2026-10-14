import SwiftUI
import AppKit

/// A SwiftUI wrapper around a custom NSView that captures a single key chord
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var chord: String
    var onChordCaptured: (String) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onChordCaptured = { newChord in
            onChordCaptured(newChord)
            // drop focus immediately so highlight goes away
            DispatchQueue.main.async { v.window?.makeFirstResponder(nil) }
        }
        return v
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.chordToShow = chord
        nsView.needsDisplay = true
    }

    class KeyCaptureView: NSView {
        var chordToShow: String = ""
        var onChordCaptured: ((String) -> Void)?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override init(frame frameRect: NSRect = .zero) {
            super.init(frame: frameRect)
            setUpLayer()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpLayer()
        }

        // Styled like a keycap, with a dynamic background that adapts to light/dark
        private func setUpLayer() {
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.cornerCurve = .continuous
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            // highlight border when focused, and prompt for the new chord
            let isFocused = window?.firstResponder === self
            layer?.borderColor = isFocused
                ? NSColor.keyboardFocusIndicatorColor.cgColor
                : NSColor.separatorColor.cgColor

            // draw the chord text, centered, in the panel's rounded font
            let base = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            let font = base.fontDescriptor.withDesign(.rounded)
                .flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
            let attrs: [NSAttributedString.Key:Any] = [
                .font: font,
                .foregroundColor: isFocused ? NSColor.secondaryLabelColor : NSColor.labelColor
            ]
            let str = NSAttributedString(string: isFocused ? "Type keys…" : chordToShow, attributes: attrs)
            let size = str.size()
            let x = (bounds.width - size.width) / 2
            let y = (bounds.height - size.height) / 2
            str.draw(at: CGPoint(x: x, y: y))
        }

        override func mouseDown(with event: NSEvent) {
            _ = becomeFirstResponder()
        }

        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            needsDisplay = true
            return ok
        }

        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            needsDisplay = true
            return ok
        }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.uppercased() ?? ""
            guard let c = chars.first else { return }
            let key = c == " " ? "Space" : String(c)
            let parts: [String] = [
                flags.contains(.control) ? "⌃" : "",
                flags.contains(.option)  ? "⌥" : "",
                flags.contains(.shift)   ? "⇧" : "",
                flags.contains(.command) ? "⌘" : "",
                key
            ].filter { !$0.isEmpty }
            onChordCaptured?(parts.joined())
        }

        override var intrinsicContentSize: NSSize {
            .init(width: 100, height: 24)
        }

        // ← Respond to appearance changes
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            // Refresh dynamic background color
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            needsDisplay = true
        }
    }
}
