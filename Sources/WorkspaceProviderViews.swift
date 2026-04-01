import AppKit
import SwiftUI

// MARK: - Workspace Provider Views

struct WorkspaceProviderInputSheet: View {
    let providerName: String
    let itemName: String
    let inputs: [WorkspaceProviderInput]
    @Binding var values: [String: String]
    let onCancel: () -> Void
    let onCreate: () -> Void

    @FocusState private var focusedInputId: String?
    @State private var localValues: [String: String] = [:]
    /// Tracks which derived fields the user has manually edited.
    @State private var manuallyEdited: Set<String> = []

    private var isValid: Bool {
        inputs.allSatisfy { input in
            if input.isRequired {
                let val = localValues[input.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !val.isEmpty
            }
            return true
        }
    }

    private static func slugify(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(itemName)
                .font(.headline)

            ForEach(inputs) { input in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text(input.label)
                            .font(.subheadline)
                        if input.isRequired {
                            Text("*")
                                .foregroundStyle(.red)
                        }
                    }
                    TextField(
                        input.placeholder ?? "",
                        text: bindingForInput(input)
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedInputId, equals: input.id)
                    .onSubmit {
                        if isValid {
                            values = localValues
                            onCreate()
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "sidebar.newWorkspace.input.cancel", defaultValue: "Cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "sidebar.newWorkspace.input.create", defaultValue: "Create")) {
                    values = localValues
                    onCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .onAppear {
            localValues = values
            focusedInputId = inputs.first?.id
        }
    }

    private func bindingForInput(_ input: WorkspaceProviderInput) -> Binding<String> {
        let inputId = input.id
        let hasDeriveFrom = input.deriveFrom != nil
        return Binding(
            get: { localValues[inputId] ?? "" },
            set: { newValue in
                localValues[inputId] = newValue
                if hasDeriveFrom && focusedInputId == inputId {
                    manuallyEdited.insert(inputId)
                }
                updateDerivedFields(sourceId: inputId)
            }
        )
    }

    private func updateDerivedFields(sourceId: String) {
        let sourceValue = localValues[sourceId] ?? ""
        for input in inputs {
            guard input.deriveFrom == sourceId else { continue }
            guard !manuallyEdited.contains(input.id) else { continue }
            localValues[input.id] = Self.slugify(sourceValue)
        }
    }
}


// MARK: - Pending Workspace Item

struct PendingWorkspaceItemView: View {
    @ObservedObject var pending: PendingWorkspace
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch pending.state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(pending.progress)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if pending.logLines.count > 1 {
                    PendingWorkspaceLogButton(pending: pending)
                }
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                PendingWorkspaceLogButton(pending: pending)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PendingWorkspaceLogButton: View {
    @ObservedObject var pending: PendingWorkspace

    var body: some View {
        Button {
            showLogPanel()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func showLogPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(pending.title) — Log"
        panel.isFloatingPanel = true
        panel.level = .floating

        let hostingView = NSHostingView(
            rootView: PendingWorkspaceLogView(pending: pending)
        )
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}

struct PendingWorkspaceLogView: View {
    @ObservedObject var pending: PendingWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(pending.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(lineColor(for: index))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: pending.logLines.count) { _ in
                    if let last = pending.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            if case .failed(let error) = pending.state {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 360, minHeight: 200)
    }

    private func lineColor(for index: Int) -> Color {
        index == pending.logLines.count - 1 ? .primary : .secondary
    }
}

