import Foundation
import AppKit

// ─── Area Selection Overlay ─────────────────────────────────────────────────
// Shows a fullscreen transparent overlay on all displays.
// The user drags to select a rectangle, then the coordinates are printed
// as JSON to stdout. Press Escape to cancel.

final class SelectionOverlayView: NSView {
	private var startPoint: NSPoint?
	private var currentPoint: NSPoint?
	private var selectionRect: NSRect?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .crosshair)
	}

	override func mouseDown(with event: NSEvent) {
		startPoint = convert(event.locationInWindow, from: nil)
		currentPoint = startPoint
		selectionRect = nil
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		guard let start = startPoint else { return }
		currentPoint = convert(event.locationInWindow, from: nil)
		guard let current = currentPoint else { return }

		let x = min(start.x, current.x)
		let y = min(start.y, current.y)
		let width = abs(current.x - start.x)
		let height = abs(current.y - start.y)
		selectionRect = NSRect(x: x, y: y, width: width, height: height)
		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
			// Selection too small — treat as a click (cancel)
			printCancelled()
			return
		}

		// Convert from view coordinates (origin bottom-left) to display-local
		// coordinates with top-left origin (as expected by SCStreamConfiguration.sourceRect)
		guard let window = self.window, let screen = window.screen else {
			printCancelled()
			return
		}

		let screenFrame = screen.frame
		// View coordinates are already display-local (overlay covers exactly one screen).
		// Just flip Y: view has bottom-left origin, ScreenCaptureKit expects top-left.
		let displayLocalX = rect.origin.x
		let displayLocalY = screenFrame.height - (rect.origin.y + rect.height)

		// Find the display ID for this screen
		let displayID = screenDisplayID(for: screen) ?? CGMainDisplayID()

		let result: [String: Any] = [
			"x": Double(displayLocalX),
			"y": Double(displayLocalY),
			"width": Double(rect.width),
			"height": Double(rect.height),
			"displayId": displayID
		]

		if let jsonData = try? JSONSerialization.data(withJSONObject: result),
		   let jsonString = String(data: jsonData, encoding: .utf8) {
			print(jsonString)
			fflush(stdout)
		}
		NSApp.terminate(nil)
	}

	override func keyDown(with event: NSEvent) {
		if event.keyCode == 53 { // Escape
			printCancelled()
		}
	}

	override var acceptsFirstResponder: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)

		guard let rect = selectionRect else { return }

		// Draw dimmed overlay with cutout for selection
		let path = NSBezierPath(rect: bounds)
		let cutout = NSBezierPath(rect: rect)
		path.append(cutout)
		path.windingRule = .evenOdd
		NSColor.black.withAlphaComponent(0.35).setFill()
		path.fill()

		// Clear the selection area (remove the base dim layer inside)
		NSGraphicsContext.current?.cgContext.clear(rect)

		// Draw selection border
		NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
		let borderPath = NSBezierPath(rect: rect)
		borderPath.lineWidth = 2
		borderPath.stroke()

		// Light fill inside selection
		NSColor.systemBlue.withAlphaComponent(0.08).setFill()
		NSBezierPath(rect: rect).fill()
	}

	private func printCancelled() {
		print("{}")
		fflush(stdout)
		NSApp.terminate(nil)
	}
}

func screenDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
	guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
		return nil
	}
	return CGDirectDisplayID(screenNumber.uint32Value)
}

// ─── Main ───────────────────────────────────────────────────────────────────

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

var overlayWindows: [NSWindow] = []

for screen in NSScreen.screens {
	let frame = screen.frame
	let window = NSWindow(
		contentRect: frame,
		styleMask: [.borderless],
		backing: .buffered,
		defer: false,
		screen: screen
	)

	window.isOpaque = false
	window.backgroundColor = .clear
	window.hasShadow = false
	window.level = .screenSaver
	window.collectionBehavior = [
		.canJoinAllSpaces,
		.fullScreenAuxiliary,
		.stationary,
		.ignoresCycle,
	]

	let overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: frame.size))
	window.contentView = overlayView
	window.setFrame(frame, display: true)
	window.makeKeyAndOrderFront(nil)
	window.makeFirstResponder(overlayView)

	overlayWindows.append(window)
}

// Activate the app so it receives keyboard events
application.activate(ignoringOtherApps: true)
application.run()
