import AppKit
import CoreGraphics
import Darwin
import Foundation

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

struct DisplayInfo {
	let displayID: CGDirectDisplayID
	let frame: CGRect
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

func parseRequestedTypes(arguments: [String]) -> Set<String> {
	var requestedTypes: Set<String> = ["screen", "window"]
	var index = 0

	while index < arguments.count {
		let argument = arguments[index]
		if argument == "--types", index + 1 < arguments.count {
			let parsedTypes = arguments[index + 1]
				.split(separator: ",")
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
				.filter { $0 == "screen" || $0 == "window" }

			if !parsedTypes.isEmpty {
				requestedTypes = Set(parsedTypes)
			}

			index += 2
			continue
		}

		index += 1
	}

	return requestedTypes
}

func availableDisplays() throws -> [DisplayInfo] {
	var displayCount: UInt32 = 0
	let countStatus = CGGetOnlineDisplayList(0, nil, &displayCount)
	guard countStatus == .success else {
		throw NSError(
			domain: "OpenRecorderSourceList",
			code: Int(countStatus.rawValue),
			userInfo: [NSLocalizedDescriptionKey: "Unable to enumerate online displays"]
		)
	}

	guard displayCount > 0 else {
		return []
	}

	var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
	let listStatus = CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)
	guard listStatus == .success else {
		throw NSError(
			domain: "OpenRecorderSourceList",
			code: Int(listStatus.rawValue),
			userInfo: [NSLocalizedDescriptionKey: "Unable to read online display list"]
		)
	}

	return displayIDs
		.prefix(Int(displayCount))
		.map { displayID in
			DisplayInfo(displayID: displayID, frame: CGDisplayBounds(displayID))
		}
		.sorted { lhs, rhs in
			if lhs.frame.origin.x != rhs.frame.origin.x {
				return lhs.frame.origin.x < rhs.frame.origin.x
			}

			return lhs.frame.origin.y < rhs.frame.origin.y
		}
}

func canCaptureScreen() -> Bool {
	if #available(macOS 10.15, *) {
		guard CGPreflightScreenCaptureAccess() else {
			return false
		}
	}

	// Probe with a real capture to detect cases where preflight passes but capture hangs
	let semaphore = DispatchSemaphore(value: 0)
	var probeSucceeded = false
	DispatchQueue.global(qos: .userInitiated).async {
		if let _ = createDisplayImage(displayID: CGMainDisplayID()) {
			probeSucceeded = true
		}
		semaphore.signal()
	}

	return semaphore.wait(timeout: .now() + 2.0) == .success && probeSucceeded
}

func displayThumbnail(displayID: CGDirectDisplayID, targetSize: ThumbnailSize) -> String? {
	guard let image = createDisplayImage(displayID: displayID) else {
		return nil
	}

	return dataURL(for: imageFromCGImage(image), targetSize: targetSize, asJPEG: true)
}

func cgRect(from boundsValue: Any?) -> CGRect? {
	if let dictionary = boundsValue as? NSDictionary {
		return CGRect(dictionaryRepresentation: dictionary)
	}

	return nil
}

func windowThumbnail(windowID: CGWindowID, bounds: CGRect, targetSize: ThumbnailSize) -> String? {
	guard bounds.width > 1, bounds.height > 1 else {
		return nil
	}

	guard let image = createWindowImage(
		bounds,
		.optionIncludingWindow,
		windowID,
		[.boundsIgnoreFraming, .bestResolution]
	) else {
		return nil
	}

	return dataURL(for: imageFromCGImage(image), targetSize: targetSize, asJPEG: true)
}

typealias CGDisplayCreateImageFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?
typealias CGWindowListCreateImageFunction = @convention(c) (
	CGRect,
	CGWindowListOption,
	CGWindowID,
	CGWindowImageOption
) -> Unmanaged<CGImage>?

func createDisplayImage(displayID: CGDirectDisplayID) -> CGImage? {
	guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGDisplayCreateImage") else {
		return nil
	}

	let function = unsafeBitCast(symbol, to: CGDisplayCreateImageFunction.self)
	return function(displayID)?.takeRetainedValue()
}

func createWindowImage(
	_ bounds: CGRect,
	_ listOption: CGWindowListOption,
	_ windowID: CGWindowID,
	_ imageOption: CGWindowImageOption
) -> CGImage? {
	guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
		return nil
	}

	let function = unsafeBitCast(symbol, to: CGWindowListCreateImageFunction.self)
	return function(bounds, listOption, windowID, imageOption)?.takeRetainedValue()
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

let commandArguments = Array(CommandLine.arguments.dropFirst())
let thumbnailSize = parseThumbnailSize(arguments: commandArguments)
let skipThumbnails = shouldSkipThumbnails(arguments: commandArguments) || !canCaptureScreen()
let requestedTypes = parseRequestedTypes(arguments: commandArguments)
let wantsScreens = requestedTypes.contains("screen")
let wantsWindows = requestedTypes.contains("window")

do {
	let displays = try availableDisplays()
	let mainDisplayID = CGMainDisplayID()

	var screenEntries: [SourceListEntry] = []
	if wantsScreens {
		screenEntries.reserveCapacity(displays.count)
		for (index, display) in displays.enumerated() {
			let displayName = display.displayID == mainDisplayID ? "Main Display" : "Display \(index + 1)"
			screenEntries.append(SourceListEntry(
				id: "screen:\(display.displayID):0",
				name: displayName,
				display_id: String(display.displayID),
				sourceType: "screen",
				thumbnail: skipThumbnails ? nil : displayThumbnail(displayID: display.displayID, targetSize: thumbnailSize),
				appIcon: nil,
				appName: nil,
				windowTitle: nil,
				windowId: nil
			))
		}
	}

	var windowEntries: [SourceListEntry] = []
	if wantsWindows, let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
		for info in windowInfoList {
			let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
			guard layer == 0 else {
				continue
			}

			let bounds = cgRect(from: info[kCGWindowBounds as String]) ?? .zero
			guard bounds.width > 1, bounds.height > 1 else {
				continue
			}

			let ownerName = normalize(info[kCGWindowOwnerName as String] as? String)
			let rawWindowTitle = normalize(info[kCGWindowName as String] as? String)
			guard ownerName != nil || rawWindowTitle != nil else {
				continue
			}

			let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
			let runningApp = pid > 0 ? NSRunningApplication(processIdentifier: pid_t(pid)) : nil
			let bundleId = normalize(runningApp?.bundleIdentifier)
			let appName = normalize(runningApp?.localizedName) ?? ownerName

			if let bundleId, excludedBundleIds.contains(bundleId) || ownBundleIds.contains(bundleId) {
				continue
			}

			if let appName, ownAppNames.contains(appName.lowercased()) {
				continue
			}

			if let rawWindowTitle, excludedWindowTitles.contains(rawWindowTitle) {
				continue
			}

			let windowID = UInt32((info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
			guard windowID != 0 else {
				continue
			}

			let resolvedWindowTitle = rawWindowTitle ?? appName ?? "Window"
			let resolvedName: String
			if let appName, let rawWindowTitle {
				resolvedName = "\(appName) — \(rawWindowTitle)"
			} else {
				resolvedName = resolvedWindowTitle
			}

			let matchedDisplay = displays.first(where: { display in
				display.frame.intersects(bounds) || display.frame.contains(CGPoint(x: bounds.midX, y: bounds.midY))
			})

			windowEntries.append(SourceListEntry(
				id: "window:\(windowID):0",
				name: resolvedName,
				display_id: matchedDisplay.map { String($0.displayID) } ?? "",
				sourceType: "window",
				thumbnail: skipThumbnails ? nil : windowThumbnail(windowID: CGWindowID(windowID), bounds: bounds, targetSize: thumbnailSize),
				appIcon: appIconDataURL(bundleId: bundleId),
				appName: appName,
				windowTitle: resolvedWindowTitle,
				windowId: windowID
			))
		}
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
