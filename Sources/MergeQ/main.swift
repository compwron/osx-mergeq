import AppKit
import MergeQCore

// Set with: defaults write local.mergeq repo owner/name
let refreshInterval: TimeInterval = 60

final class GhClient {
    // GUI apps launch with a bare PATH, so look for gh in the usual install spots.
    private static let candidatePaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    func fetchQueue(repo: String) throws -> QueueSnapshot {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw QueueParseError.graphQL("Bad repo setting: \(repo)") }
        guard let gh = Self.candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw QueueParseError.graphQL("gh CLI not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = [
            "api", "graphql",
            "-f", "query=\(QueueQuery.graphQL)",
            "-F", "owner=\(parts[0])",
            "-F", "name=\(parts[1])",
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // gh exits non-zero on GraphQL errors but still prints the JSON body, so try parsing first.
        if let snapshot = try? QueueParser.parse(output) { return snapshot }
        if process.terminationStatus != 0 {
            let message = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "gh failed"
            throw QueueParseError.graphQL(message)
        }
        return try QueueParser.parse(output)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = GhClient()
    private let fetchQueue = DispatchQueue(label: "mergeq.fetch")
    private var timer: Timer?
    private var snapshot: QueueSnapshot?
    private var lastError: String?
    private var lastUpdated: Date?
    private var isFetching = false

    private var repo: String? {
        UserDefaults.standard.string(forKey: "repo")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: "Merge queue")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = " …"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func refresh() {
        guard !isFetching else { return }
        guard let repo else {
            lastError = "No repo set. Run: defaults write local.mergeq repo owner/name"
            updateTitle()
            rebuildMenu()
            return
        }
        isFetching = true
        fetchQueue.async { [weak self] in
            let result = Result { try self?.client.fetchQueue(repo: repo) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.lastError = nil
                    self.lastUpdated = Date()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
                self.updateTitle()
                self.rebuildMenu()
            }
        }
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if lastError != nil && snapshot == nil {
            button.title = " !"
            return
        }
        guard let snapshot else { return }
        let count = snapshot.entries.count
        if count == 0 {
            button.title = " 0"
        } else {
            let mark = snapshot.myFirstEntry != nil ? "★ " : ""
            button.title = " \(count) · \(mark)\(DurationFormatter.short(snapshot.headlineSeconds))"
        }
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        menu.addItem(disabled("\(repo ?? "No repo") merge queue"))
        if let lastError {
            menu.addItem(disabled("⚠︎ \(lastError)"))
        }

        if let snapshot {
            if snapshot.entries.isEmpty {
                menu.addItem(disabled("Queue is empty"))
            } else {
                let clears = DurationFormatter.short(snapshot.secondsUntilQueueClears)
                menu.addItem(disabled("\(snapshot.entries.count) queued · clears in ~\(clears)"))
                if let mine = snapshot.myFirstEntry {
                    menu.addItem(disabled("★ Your #\(mine.number) merges in ~\(DurationFormatter.short(mine.estimatedSecondsToMerge))"))
                }
                menu.addItem(.separator())
                for entry in snapshot.entries {
                    menu.addItem(item(for: entry))
                }
            }
        }

        menu.addItem(.separator())
        if let lastUpdated {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            menu.addItem(disabled("Updated \(formatter.string(from: lastUpdated))"))
        }
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let openItem = NSMenuItem(title: "Open Queue in Browser", action: #selector(openQueue), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(for entry: QueueEntry) -> NSMenuItem {
        let title = entry.title.count > 60 ? String(entry.title.prefix(59)) + "…" : entry.title
        let star = entry.isMine ? "★ " : ""
        let headline = "\(star)\(entry.position). #\(entry.number) \(title)"
        let detail = "\(entry.author) · \(StateLabel.readable(entry.state)) · ~\(DurationFormatter.short(entry.estimatedSecondsToMerge))"

        let attributed = NSMutableAttributedString(
            string: headline,
            attributes: [.font: entry.isMine ? NSFont.boldSystemFont(ofSize: 13) : NSFont.menuFont(ofSize: 13)]
        )
        attributed.append(NSAttributedString(
            string: "\n\(detail)",
            attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        ))

        let item = NSMenuItem(title: headline, action: #selector(openPullRequest(_:)), keyEquivalent: "")
        item.attributedTitle = attributed
        item.representedObject = entry.url
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openPullRequest(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openQueue() {
        guard let repo else { return }
        let string = snapshot?.queueURL ?? "https://github.com/\(repo)/queue"
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
