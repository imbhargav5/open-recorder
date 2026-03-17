import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

let _ = NSApplication.shared

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

struct ThumbnailSize {
	let width: Int
	let height: Int
}

func normalize(_ value: String?) -> String? {
	guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
		return nil
	}

	return rawValue
}

func dataURL(for image: NSImage?, targetSize: ThumbnailSize, asJPEG: Bool = false) -> String? {
	guard let image, targetSize.width > 0, targetSize.height > 0 else {
		return nil
	}

	let outputSize = NSSize(width: targetSize.width, height: targetSize.height)
	let renderedImage = NSImage(size: outputSize)
	renderedImage.lockFocus()
	NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
	NSBezierPath(rect: NSRect(origin: .zero, size: outputSize)).fill()

	let imageSize = image.size
	let scale = min(outputSize.width / max(1, imageSize.width), outputSize.height / max(1, imageSize.height))
	let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
	let drawOrigin = NSPoint(
		x: (outputSize.width - drawSize.width) / 2,
		y: (outputSize.height - drawSize.height) / 2
	)
	image.draw(
		in: NSRect(origin: drawOrigin, size: drawSize),
		from: .zero,
		operation: .copy,
		fraction: 1
	)
	renderedImage.unlockFocus()

	guard
		let tiffData = renderedImage.tiffRepresentation,
		let bitmap = NSBitmapImageRep(data: tiffData)
	else {
		return nil
	}

	if asJPEG, let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) {
		return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
	}

	guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
		return nil
	}

	return "data:image/png;base64,\(pngData.base64EncodedString())"
}

func imageFromCGImage(_ cgImage: CGImage?) -> NSImage? {
	guard let cgImage else {
		return nil
	}

	return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

func appIconDataURL(bundleId: String?) -> String? {
	guard
		let bundleId,
		let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
	else {
		return nil
	}

	let icon = NSWorkspace.shared.icon(forFile: appURL.path)
	return dataURL(for: icon, targetSize: ThumbnailSize(width: 128, height: 128))
}

func fittingSize(for sourceSize: CGSize, targetSize: ThumbnailSize) -> ThumbnailSize {
	let safeWidth = max(sourceSize.width, 1)
	let safeHeight = max(sourceSize.height, 1)
	let scale = min(CGFloat(targetSize.width) / safeWidth, CGFloat(targetSize.height) / safeHeight)

	return ThumbnailSize(
		width: max(1, Int((safeWidth * scale).rounded(.down))),
		height: max(1, Int((safeHeight * scale).rounded(.down)))
	)
}

func captureImage(contentFilter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
	try await withCheckedThrowingContinuation { continuation in
		SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
			if let error {
				continuation.resume(throwing: error)
				return
			}

			if let image {
				continuation.resume(returning: image)
				return
			}

			continuation.resume(throwing: NSError(domain: "OpenRecorderSourceList", code: 1, userInfo: [
				NSLocalizedDescriptionKey: "ScreenCaptureKit returned no image",
			]))
		}
	}
}

func screenshotConfiguration(sourceSize: CGSize, targetSize: ThumbnailSize) -> SCStreamConfiguration {
	let fittedSize = fittingSize(for: sourceSize, targetSize: targetSize)
	let configuration = SCStreamConfiguration()
	configuration.width = fittedSize.width
	configuration.height = fittedSize.height
	configuration.showsCursor = false
	return configuration
}

func displayThumbnail(display: SCDisplay, targetSize: ThumbnailSize) async -> String? {
	let configuration = screenshotConfiguration(sourceSize: display.frame.size, targetSize: targetSize)
	let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

	do {
		let image = try await captureImage(contentFilter: filter, configuration: configuration)
		return dataURL(for: imageFromCGImage(image), targetSize: targetSize, asJPEG: true)
	} catch {
		return nil
	}
}

func windowThumbnail(window: SCWindow, targetSize: ThumbnailSize) async -> String? {
	let configuration = screenshotConfiguration(sourceSize: window.frame.size, targetSize: targetSize)
	configuration.ignoreShadowsSingleWindow = true
	let filter = SCContentFilter(desktopIndependentWindow: window)

	do {
		let image = try await captureImage(contentFilter: filter, configuration: configuration)
		return dataURL(for: imageFromCGImage(image), targetSize: targetSize, asJPEG: true)
	} catch {
		return nil
	}
}

func parseThumbnailSize(arguments: [String]) -> ThumbnailSize {
	var width = 320
	var height = 180

	var index = 0
	while index < arguments.count {
		let argument = arguments[index]
		if argument == "--thumbnail-width", index + 1 < arguments.count, let parsedWidth = Int(arguments[index + 1]), parsedWidth > 0 {
			width = parsedWidth
			index += 2
			continue
		}

		if argument == "--thumbnail-height", index + 1 < arguments.count, let parsedHeight = Int(arguments[index + 1]), parsedHeight > 0 {
			height = parsedHeight
			index += 2
			continue
		}

		index += 1
	}

	return ThumbnailSize(width: width, height: height)
}

func shouldSkipThumbnails(arguments: [String]) -> Bool {
	arguments.contains("--no-thumbnails")
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
let commandArguments = Array(CommandLine.arguments.dropFirst())
let thumbnailSize = parseThumbnailSize(arguments: commandArguments)
let skipThumbnails = shouldSkipThumbnails(arguments: commandArguments)

Task {
	do {
		let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
		let sortedDisplays = shareableContent.displays.sorted { lhs, rhs in
			if lhs.frame.origin.x != rhs.frame.origin.x {
				return lhs.frame.origin.x < rhs.frame.origin.x
			}

			return lhs.frame.origin.y < rhs.frame.origin.y
		}

		var screenEntries: [SourceListEntry] = []
		screenEntries.reserveCapacity(sortedDisplays.count)
		for (index, display) in sortedDisplays.enumerated() {
			let displayId = String(display.displayID)
			let screenIndex = index + 1
			let displayName = display.displayID == CGMainDisplayID() ? "Main Display" : "Display \(screenIndex)"

			screenEntries.append(SourceListEntry(
				id: "screen:\(display.displayID):0",
				name: displayName,
				display_id: displayId,
				sourceType: "screen",
				thumbnail: skipThumbnails ? nil : await displayThumbnail(display: display, targetSize: thumbnailSize),
				appIcon: nil,
				appName: nil,
				windowTitle: nil,
				windowId: nil
			))
		}

		var windowEntries: [SourceListEntry] = []
		for window in shareableContent.windows {
			let appName = normalize(window.owningApplication?.applicationName)
			let windowTitle = normalize(window.title)
			let bundleId = normalize(window.owningApplication?.bundleIdentifier)
			let frame = window.frame

			guard window.windowLayer == 0 else {
				continue
			}

			guard frame.width > 1, frame.height > 1 else {
				continue
			}

			guard appName != nil || windowTitle != nil else {
				continue
			}

			if let bundleId, excludedBundleIds.contains(bundleId) || ownBundleIds.contains(bundleId) {
				continue
			}

			if let appName, ownAppNames.contains(appName.lowercased()) {
				continue
			}

			if let windowTitle, excludedWindowTitles.contains(windowTitle) {
				continue
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

			windowEntries.append(SourceListEntry(
				id: "window:\(window.windowID):0",
				name: resolvedName,
				display_id: matchedDisplay.map { String($0.displayID) } ?? "",
				sourceType: "window",
				thumbnail: skipThumbnails ? nil : await windowThumbnail(window: window, targetSize: thumbnailSize),
				appIcon: appIconDataURL(bundleId: bundleId),
				appName: appName,
				windowTitle: resolvedWindowTitle,
				windowId: window.windowID
			))
		}
		windowEntries.sort { lhs, rhs in
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
		exit(0)
	} catch {
		fputs("Error listing sources: \(error.localizedDescription)\n", stderr)
		fflush(stderr)
		exit(1)
	}
}

RunLoop.main.run()
