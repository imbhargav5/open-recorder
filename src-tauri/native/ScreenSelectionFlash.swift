import Foundation
import AppKit

func parseDisplayID(arguments: [String]) -> CGDirectDisplayID? {
	var index = 0
	while index < arguments.count {
		let argument = arguments[index]
		if argument == "--display-id", index + 1 < arguments.count {
			return UInt32(arguments[index + 1])
		}
		index += 1
	}

	return nil
}

func screenDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
	guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
		return nil
	}

	return CGDirectDisplayID(screenNumber.uint32Value)
}

final class FlashBorderView: NSView {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.95).cgColor
		layer?.borderWidth = 14
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

func showFlash(on screen: NSScreen) {
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
	window.ignoresMouseEvents = true
	window.level = .screenSaver
	window.collectionBehavior = [
		.canJoinAllSpaces,
		.fullScreenAuxiliary,
		.stationary,
		.ignoresCycle,
	]
	window.alphaValue = 0
	window.contentView = FlashBorderView(frame: NSRect(origin: .zero, size: frame.size))
	window.setFrame(frame, display: true)
	window.orderFrontRegardless()
	window.display()

	NSAnimationContext.runAnimationGroup { context in
		context.duration = 0.08
		window.animator().alphaValue = 1
	} completionHandler: {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.18
				window.animator().alphaValue = 0
			} completionHandler: {
				window.orderOut(nil)
				NSApp.terminate(nil)
			}
		}
	}
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

guard let targetDisplayID = parseDisplayID(arguments: Array(CommandLine.arguments.dropFirst())) else {
	fputs("Missing --display-id\n", stderr)
	exit(1)
}

guard let screen = NSScreen.screens.first(where: { screenDisplayID(for: $0) == targetDisplayID }) else {
	fputs("Unable to find screen for display id \(targetDisplayID)\n", stderr)
	exit(1)
}

showFlash(on: screen)
application.run()
