import AppKit
import SwiftUI

// MARK: - Titlebar New Workspace Menu Button

struct TitlebarNewWorkspaceMenuButton: View {
    let config: TitlebarControlsStyleConfig
    @ObservedObject var providerStore: WorkspaceProviderStore
    let onNewTab: () -> Void
    @State private var isHovering = false
    @State private var isMenuPresented = false
    @State private var showingInputSheet = false
    /// Retains NSMenu action targets for the lifetime of the menu.
    @State private var menuTargets: [TitlebarMenuTarget] = []
    @State private var pendingProvider: WorkspaceProviderDefinition?
    @State private var pendingItem: WorkspaceProviderItem?
    @State private var inputValues: [String: String] = [:]
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var activeCreateTask: Task<Void, Never>?
    @State private var menuAnchorView: NSView?
    @State private var lastFetchTime: Date?
    private static let fetchTTL: TimeInterval = 10

    var body: some View {
        let hasProviders = !providerStore.providers.isEmpty

        TitlebarControlButton(config: config, action: {
            if hasProviders {
                fetchThenShowMenu()
            } else {
                onNewTab()
            }
        }) {
            Image(systemName: "plus")
                .font(.system(size: config.iconSize, weight: .semibold))
                .frame(width: config.buttonSize, height: config.buttonSize)
                .background(WorkspaceProviderMenuAnchorView(anchorViewRef: $menuAnchorView))
        }
        .onHover { hovering in
            if hovering && hasProviders {
                prefetchIfStale()
            }
        }
        .onChange(of: showingInputSheet) { showing in
            if showing, let provider = pendingProvider, let item = pendingItem,
               let inputs = item.inputs, !inputs.isEmpty {
                showInputPanel(provider: provider, item: item, inputs: inputs)
            }
        }
        .onChange(of: showingError) { showing in
            if showing {
                let alert = NSAlert()
                alert.messageText = String(localized: "sidebar.newWorkspace.error.title", defaultValue: "Workspace Creation Failed")
                alert.informativeText = errorMessage
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "sidebar.newWorkspace.error.ok", defaultValue: "OK"))
                alert.runModal()
                showingError = false
            }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        var targets: [TitlebarMenuTarget] = []

        // Default new workspace
        let newItem = NSMenuItem(
            title: String(localized: "sidebar.newWorkspace.default", defaultValue: "New Workspace"),
            action: #selector(TitlebarMenuTarget.newWorkspaceAction(_:)),
            keyEquivalent: ""
        )
        let target = TitlebarMenuTarget(onNewTab: onNewTab)
        newItem.target = target
        targets.append(target)
        menu.addItem(newItem)

        // Provider items
        for provider in providerStore.providers {
            menu.addItem(NSMenuItem.separator())

            let header = NSMenuItem(title: provider.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let items = providerStore.cachedItems[provider.id] ?? []
            if items.isEmpty {
                let empty = NSMenuItem(
                    title: String(localized: "sidebar.newWorkspace.noItems", defaultValue: "No items"),
                    action: nil,
                    keyEquivalent: ""
                )
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                for item in items {
                    let menuItem = NSMenuItem(
                        title: item.name,
                        action: #selector(TitlebarMenuTarget.providerItemAction(_:)),
                        keyEquivalent: ""
                    )
                    let itemTarget = TitlebarMenuTarget(
                        onNewTab: onNewTab,
                        onSelectItem: { [provider, item] in
                            handleItemSelected(provider: provider, item: item)
                        }
                    )
                    menuItem.target = itemTarget
                    targets.append(itemTarget)
                    if let subtitle = item.subtitle {
                        menuItem.toolTip = subtitle
                    }
                    menu.addItem(menuItem)
                }
            }
        }

        // Retain targets until menu dismisses
        menuTargets = targets

        // Show menu anchored below the "+" button
        if let anchorView = menuAnchorView {
            let point = NSPoint(x: 0, y: anchorView.bounds.maxY)
            menu.popUp(positioning: nil, at: point, in: anchorView)
        } else if let event = NSApp.currentEvent, let window = event.window {
            let location = NSPoint(x: event.locationInWindow.x - 10, y: event.locationInWindow.y - 5)
            menu.popUp(positioning: nil, at: location, in: window.contentView)
        }
    }

    private var isFetchStale: Bool {
        guard let lastFetch = lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) > Self.fetchTTL
    }

    private func prefetchIfStale() {
        guard isFetchStale else { return }
        Task { @MainActor in
            await fetchAllProviders()
        }
    }

    private func fetchAllProviders() async {
        for provider in providerStore.providers {
            _ = await providerStore.fetchItems(for: provider)
        }
        lastFetchTime = Date()
    }

    private func fetchThenShowMenu() {
        if isFetchStale {
            Task { @MainActor in
                await fetchAllProviders()
                showMenu()
            }
        } else {
            showMenu()
        }
    }

    private func showInputPanel(provider: WorkspaceProviderDefinition, item: WorkspaceProviderItem, inputs: [WorkspaceProviderInput]) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 0),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(provider.name) — \(item.name)"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false

        var capturedValues: [String: String] = [:]

        let hostingView = NSHostingView(
            rootView: WorkspaceProviderInputSheet(
                providerName: provider.name,
                itemName: item.name,
                inputs: inputs,
                values: Binding(
                    get: { capturedValues },
                    set: { capturedValues = $0 }
                ),
                onCancel: { [weak panel] in
                    panel?.close()
                    self.showingInputSheet = false
                    self.pendingProvider = nil
                    self.pendingItem = nil
                    self.inputValues = [:]
                },
                onCreate: { [weak panel] in
                    panel?.close()
                    self.showingInputSheet = false
                    self.startCreate(provider: provider, item: item, inputs: capturedValues)
                    self.inputValues = [:]
                }
            )
            .frame(minWidth: 340)
        )

        panel.contentView = hostingView
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(NSSize(width: max(360, fittingSize.width), height: fittingSize.height))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    private func handleItemSelected(provider: WorkspaceProviderDefinition, item: WorkspaceProviderItem) {
        if let inputs = item.inputs, !inputs.isEmpty {
            pendingProvider = provider
            pendingItem = item
            inputValues = [:]
            showingInputSheet = true
        } else {
            startCreate(provider: provider, item: item, inputs: [:])
        }
    }

    private func startCreate(provider: WorkspaceProviderDefinition, item: WorkspaceProviderItem, inputs: [String: String]) {
        guard let tabManager = AppDelegate.shared?.tabManager else { return }

        // Generate temp file for provider output
        let outputPath = NSTemporaryDirectory() + "cmux-provider-\(UUID().uuidString).json"

        // Build the create command with args
        var command = "\(provider.create) --id \(Self.shellEscape(item.id))"
        for (key, value) in inputs {
            command += " --input \(Self.shellEscape("\(key)=\(value)"))"
        }

        // Create workspace with a setup terminal
        let ws = tabManager.addWorkspace(
            title: "Setting up: \(item.name)",
            initialTerminalEnvironment: ["CMUX_PROVIDER_OUTPUT": outputPath]
        )
        ws.setCustomTitle("Setting up: \(item.name)")

        // Track provider origin for cleanup on close
        ws.providerOrigin = WorkspaceProviderOrigin(
            providerId: provider.id,
            destroyCommand: provider.destroy,
            itemId: item.id,
            inputs: inputs,
            cwd: nil,
            isolateBrowser: provider.isolate_browser == true
        )

        // Send the create command to the terminal
        ws.sendCommandToFirstTerminal(command + "\n")

        // Watch for the output file
        watchForProviderOutput(
            outputPath: outputPath,
            workspace: ws,
            provider: provider,
            item: item,
            inputs: inputs
        )
    }

    private func watchForProviderOutput(
        outputPath: String,
        workspace: Workspace,
        provider: WorkspaceProviderDefinition,
        item: WorkspaceProviderItem,
        inputs: [String: String]
    ) {
        // Watch the directory for the output file using DispatchSource (no polling)
        let directoryPath = (outputPath as NSString).deletingLastPathComponent
        let fd = open(directoryPath, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[WorkspaceProvider] failed to open directory for watching: %@", directoryPath)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        var didHandle = false

        source.setEventHandler {
            guard !didHandle else { return }
            guard FileManager.default.fileExists(atPath: outputPath) else { return }
            didHandle = true
            source.cancel()

            self.handleProviderOutputFile(
                outputPath: outputPath,
                workspace: workspace,
                provider: provider,
                item: item,
                inputs: inputs
            )
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()

        // Safety: stop watching after 30 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800) {
            guard !didHandle else { return }
            didHandle = true
            source.cancel()
            try? FileManager.default.removeItem(atPath: outputPath)
        }
    }

    private func handleProviderOutputFile(
        outputPath: String,
        workspace: Workspace,
        provider: WorkspaceProviderDefinition,
        item: WorkspaceProviderItem,
        inputs: [String: String]
    ) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
            let result = try JSONDecoder().decode(WorkspaceProviderCreateResult.self, from: data)
            try? FileManager.default.removeItem(atPath: outputPath)

            if let error = result.error {
                NSLog("[WorkspaceProvider] create returned error: %@", error)
                return
            }

            applyProviderResult(result, to: workspace, provider: provider, item: item, inputs: inputs)
        } catch {
            NSLog("[WorkspaceProvider] failed to parse output file: %@", error.localizedDescription)
            try? FileManager.default.removeItem(atPath: outputPath)
        }
    }

    private func applyProviderResult(
        _ result: WorkspaceProviderCreateResult,
        to workspace: Workspace,
        provider: WorkspaceProviderDefinition,
        item: WorkspaceProviderItem,
        inputs: [String: String]
    ) {
        // Update origin with cwd
        workspace.providerOrigin = WorkspaceProviderOrigin(
            providerId: provider.id,
            destroyCommand: provider.destroy,
            itemId: item.id,
            inputs: inputs,
            cwd: result.cwd,
            isolateBrowser: provider.isolate_browser == true
        )

        if let color = result.color {
            workspace.setCustomColor(color)
        }
        if let title = result.title {
            workspace.setCustomTitle(title)
        }

        // Close the setup terminal and apply the configured layout
        if var layout = result.layout, let cwd = result.cwd {
            // Merge workspace-level env into every surface in the layout
            if let env = result.env, !env.isEmpty {
                Self.injectEnvIntoLayout(&layout, env: env)
            }

            // Store layout for session restore (suspended workspace re-activation)
            workspace.suspendedLayout = layout

            // Close existing setup panel(s)
            for panelId in Array(workspace.panels.keys) {
                _ = workspace.closePanel(panelId, force: true)
            }
            // Apply full layout at the workspace cwd
            workspace.applyCustomLayout(layout, baseCwd: cwd)
        }
    }

    /// Recursively merge workspace-level env vars into every surface in the layout.
    private static func injectEnvIntoLayout(_ node: inout CmuxLayoutNode, env: [String: String]) {
        switch node {
        case .pane(var pane):
            for i in pane.surfaces.indices {
                var merged = env
                if let surfaceEnv = pane.surfaces[i].env {
                    merged.merge(surfaceEnv) { _, surface in surface } // surface env wins
                }
                pane.surfaces[i].env = merged
            }
            node = .pane(pane)
        case .split(var split):
            for i in split.children.indices {
                injectEnvIntoLayout(&split.children[i], env: env)
            }
            node = .split(split)
        }
    }

    private static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Captures an NSView reference for menu anchoring.
struct WorkspaceProviderMenuAnchorView: NSViewRepresentable {
    @Binding var anchorViewRef: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { anchorViewRef = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if anchorViewRef !== nsView {
            DispatchQueue.main.async { anchorViewRef = nsView }
        }
    }
}

/// NSMenu action target for titlebar workspace menu.
@objc final class TitlebarMenuTarget: NSObject {
    let onNewTab: () -> Void
    var onSelectItem: (() -> Void)?

    init(onNewTab: @escaping () -> Void, onSelectItem: (() -> Void)? = nil) {
        self.onNewTab = onNewTab
        self.onSelectItem = onSelectItem
    }

    @objc func newWorkspaceAction(_ sender: Any?) {
        onNewTab()
    }

    @objc func providerItemAction(_ sender: Any?) {
        onSelectItem?()
    }
}
