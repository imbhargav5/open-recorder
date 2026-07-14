import Foundation

enum ProjectLibrarySortField: String, CaseIterable, Identifiable, Sendable {
    case title
    case source
    case lastOpened
    case path

    var id: String { rawValue }
}

struct ProjectLibraryComparator: SortComparator, Equatable, Sendable {
    typealias Compared = ProjectSummary

    var field: ProjectLibrarySortField
    var order: SortOrder = .forward

    func compare(_ lhs: ProjectSummary, _ rhs: ProjectSummary) -> ComparisonResult {
        if field == .lastOpened {
            return compareDates(lhs.lastOpenedAt, rhs.lastOpenedAt)
        }

        let result: ComparisonResult

        switch field {
        case .title:
            result = compareText(lhs.title, rhs.title)
        case .source:
            result = compareText(projectSourceDisplayName(lhs), projectSourceDisplayName(rhs))
        case .lastOpened:
            result = .orderedSame
        case .path:
            result = compareText(lhs.path, rhs.path)
        }

        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending:
            return .orderedDescending
        case .orderedDescending:
            return .orderedAscending
        case .orderedSame:
            return .orderedSame
        }
    }

    private func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private func compareDates(_ lhs: String, _ rhs: String) -> ComparisonResult {
        switch (projectDate(lhs), projectDate(rhs)) {
        case let (left?, right?):
            let result: ComparisonResult
            if left < right {
                result = .orderedAscending
            } else if left > right {
                result = .orderedDescending
            } else {
                result = .orderedSame
            }
            guard order == .reverse else { return result }
            if result == .orderedAscending { return .orderedDescending }
            if result == .orderedDescending { return .orderedAscending }
            return .orderedSame
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }
}

enum ProjectLibraryQuery {
    static func projects(
        from projects: [ProjectSummary],
        tab: ProjectLibraryTab,
        searchText: String,
        sortOrder: [ProjectLibraryComparator]
    ) -> [ProjectSummary] {
        let terms = normalizedTerms(searchText)
        let filtered = projects.filter { project in
            guard project.mediaKind == tab.mediaKind else { return false }
            guard !terms.isEmpty else { return true }

            let haystack = normalizedText([
                project.title,
                projectSourceDisplayName(project),
                project.path,
                project.mediaPath ?? "",
            ].joined(separator: " "))
            return terms.allSatisfy(haystack.contains)
        }

        let comparators = sortOrder.isEmpty
            ? [ProjectLibraryComparator(field: .lastOpened, order: .reverse)]
            : sortOrder
        return filtered.sorted(using: comparators)
    }

    private static func normalizedTerms(_ query: String) -> [String] {
        normalizedText(query)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

enum SettingsServicePresentationState: Equatable, Sendable {
    case notChecked
    case checking(previousValue: String?)
    case available(String)
    case unavailable(String?)

    var value: String {
        switch self {
        case .notChecked:
            return "Not checked"
        case .checking(let previousValue):
            return previousValue ?? "Checking…"
        case .available(let value):
            return value
        case .unavailable:
            return "Unavailable"
        }
    }

    var detail: String? {
        switch self {
        case .notChecked:
            return "Check the local service when you need to diagnose a connection problem."
        case .checking:
            return "Checking the local service…"
        case .available:
            return nil
        case .unavailable(let message):
            return message
        }
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

func settingsServicePresentationState(
    health: HealthPayload?,
    isRefreshing: Bool,
    statusMessage: String
) -> SettingsServicePresentationState {
    let availableValue = health.map { "\($0.service) \($0.version)" }
    if isRefreshing {
        return .checking(previousValue: availableValue)
    }

    let trimmedMessage = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    if let availableValue, trimmedMessage.isEmpty || trimmedMessage == "Rust service ready" {
        return .available(availableValue)
    }
    if trimmedMessage.isEmpty {
        return .notChecked
    }
    return .unavailable(trimmedMessage)
}

func projectDate(_ value: String) -> Date? {
    if let seconds = TimeInterval(value), seconds.isFinite {
        return Date(timeIntervalSince1970: seconds)
    }
    return ISO8601DateFormatter().date(from: value)
}

func projectSourceDisplayName(_ project: ProjectSummary) -> String {
    if let sourceName = project.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceName.isEmpty {
        return sourceName
    }
    return URL(fileURLWithPath: project.mediaPath ?? project.path).lastPathComponent
}

extension ProjectSummary {
    var isOpenableFromLibrary: Bool {
        !missing && availability.isAvailable
    }

    var libraryAvailabilityLabel: String? {
        switch availability {
        case .available:
            return missing ? "Unavailable" : nil
        case .missingProject:
            return "Project missing"
        case .missingMedia:
            return "Media missing"
        case .missingProjectAndMedia:
            return "Project and media missing"
        case .unavailable:
            return "Unavailable"
        }
    }
}
