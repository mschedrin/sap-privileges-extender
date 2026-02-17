import AppKit
import SwiftUI
import PrivilegesExtenderCore

/// Manages the log viewer window, hosting a SwiftUI view inside an NSWindow.
final class LogViewerWindow {
    private var window: NSWindow?
    private var viewModel: LogViewerViewModel?
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    /// Opens the log viewer window, or brings it to front if already open.
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Stop previous view model's timer before creating a new one
        viewModel?.stopAutoRefresh()

        let newViewModel = LogViewerViewModel(logger: logger)
        self.viewModel = newViewModel
        let contentView = LogViewerView(viewModel: newViewModel)
        let hostingController = NSHostingController(rootView: contentView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Privileges Extender — Logs"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.setFrameAutosaveName("LogViewerWindow")

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }
}

// MARK: - ViewModel

/// Observable model that loads and manages log content.
final class LogViewerViewModel: ObservableObject {
    @Published var logContent: String = ""
    @Published var isAutoRefresh: Bool = true

    private let logger: Logger
    private var refreshTimer: Timer?

    init(logger: Logger) {
        self.logger = logger
        refresh()
        startAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        logContent = logger.readAll() ?? "(No log entries)"
    }

    func clearLog() {
        logger.clear()
        refresh()
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isAutoRefresh else { return }
            self.refresh()
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - SwiftUI View

struct LogViewerView: View {
    @ObservedObject var viewModel: LogViewerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: { viewModel.refresh() }, label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                })

                Toggle("Auto-refresh", isOn: $viewModel.isAutoRefresh)
                    .toggleStyle(.checkbox)
                    .onChange(of: viewModel.isAutoRefresh) { newValue in
                        if newValue {
                            viewModel.startAutoRefresh()
                        } else {
                            viewModel.stopAutoRefresh()
                        }
                    }

                Spacer()

                Button(role: .destructive, action: { viewModel.clearLog() }, label: {
                    Label("Clear Log", systemImage: "trash")
                })
            }
            .padding(8)

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.logContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                        .id("logBottom")
                }
                .onChange(of: viewModel.logContent) { _ in
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
