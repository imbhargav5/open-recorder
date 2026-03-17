import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

struct SourceListEntry: Codable {
	let id: String
	let name: String
	let display_id: String
	let sourceType: String
	let thumbnail: String?
	let appIcon: String?
	let appName: String?
	let windowTitle: String?
	let windowId: UInt32?
}

func normalize(_ value: String?) -> String? {
	guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
		return nil
	}

	return rawValue
}

func pngDataURL(for image: NSImage?) -> String? {
	guard let image else {
		return nil
	}

	let outputSize = NSSize(width: 128, height: 128)
	let renderedImage = NSImage(size: outputSize)
	renderedImage.lockFocus()
	image.draw(in: NSRect(origin: .zero, size: outputSize))
	renderedImage.unlockFocus()

	guard
		let tiffData = renderedImage.tiffRepresentation,
		let bitmap = NSBitmapImageRep(data: tiffData),
		let pngData = bitmap.representation(using: .png, properties: [:])
	else {
		return nil
	}

	return "data:image/png;base64,\(pngData.base64EncodedString())"
}

func appIconDataURL(bundleId: String?) -> String? {
	guard
		let bundleId,
		let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
	else {
		return nil
	}

	let icon = NSWorkspace.shared.icon(forFile: appURL.path)
	return pngDataURL(for: icon)
}

let excludedBundleIds: Set<String> = [
	"com.apple.controlcenter",
	"com.apple.dock",
	"com.apple.WindowManager",
	"com.apple.wallpaper.agent",
]

let excludedWindowTitles: Set<String> = [
	"Display 1 Backstop",
	"Event Shield Window",
	"Menubar",
	"Offscreen Wallpaper Window",
	"Wallpaper-",
]

let ownAppNames: Set<String> = [
	"open recorder",
	"open-recorder",
]

let ownBundleIds: Set<String> = [
	"dev.openrecorder.app",
]

let _ = CGMainDisplayID()

let group = DispatchGroup()
group.enter()

Task {
	do {
		let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
		let sortedDisplays = shareableContent.displays.sorted { lhs, rhs in
			if lhs.frame.origin.x != rhs.frame.origin.x {
				return lhs.frame.origin.x < rhs.frame.origin.x
			}

			return lhs.frame.origin.y < rhs.frame.origin.y
		}

		let screenEntries = sortedDisplays.enumerated().map { index, display in
			let displayId = String(display.displayID)
			let screenIndex = index + 1
			let displayName = display.displayID == CGMainDisplayID() ? "Main Display" : "Display \(screenIndex)"

			return SourceListEntry(
				id: "screen:\(display.displayID):0",
				name: displayName,
				display_id: displayId,
				sourceType: "screen",
				thumbnail: nil,
				appIcon: nil,
				appName: nil,
				windowTitle: nil,
				windowId: nil
			)
		}

		let windowEntries = shareableContent.windows.compactMap { window -> SourceListEntry? in
			let appName = normalize(window.owningApplication?.applicationName)
			let windowTitle = normalize(window.title)
			let bundleId = normalize(window.owningApplication?.bundleIdentifier)
			let frame = window.frame

			guard window.windowLayer == 0 else {
				return nil
			}

			guard frame.width > 1, frame.height > 1 else {
				return nil
			}

			guard appName != nil || windowTitle != nil else {
				return nil
			}

			if let bundleId, excludedBundleIds.contains(bundleId) || ownBundleIds.contains(bundleId) {
				return nil
			}

			if let appName, ownAppNames.contains(appName.lowercased()) {
				return nil
			}

			if let windowTitle, excludedWindowTitles.contains(windowTitle) {
				return nil
			}

			let matchedDisplay = sortedDisplays.first(where: { display in
				display.frame.intersects(frame) || display.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
			})

			let resolvedWindowTitle = windowTitle ?? appName ?? "Window"
			let resolvedName: String
			if let appName, let windowTitle {
				resolvedName = "\(appName) — \(windowTitle)"
			} else {
				resolvedName = resolvedWindowTitle
			}

			return SourceListEntry(
				id: "window:\(window.windowID):0",
				name: resolvedName,
				display_id: matchedDisplay.map { String($0.displayID) } ?? "",
				sourceType: "window",
				thumbnail: nil,
				appIcon: appIconDataURL(bundleId: bundleId),
				appName: appName,
				windowTitle: resolvedWindowTitle,
				windowId: window.windowID
			)
		}
		.sorted { lhs, rhs in
			let lhsApp = lhs.appName ?? lhs.name
			let rhsApp = rhs.appName ?? rhs.name
			if lhsApp != rhsApp {
				return lhsApp.localizedCaseInsensitiveCompare(rhsApp) == .orderedAscending
			}

			return (lhs.windowTitle ?? lhs.name).localizedCaseInsensitiveCompare(rhs.windowTitle ?? rhs.name) == .orderedAscending
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		let data = try encoder.encode(screenEntries + windowEntries)
		FileHandle.standardOutput.write(data)
	} catch {
		fputs("Error listing sources: \(error.localizedDescription)\n", stderr)
		fflush(stderr)
		exit(1)
	}

	group.leave()
}

group.wait()
