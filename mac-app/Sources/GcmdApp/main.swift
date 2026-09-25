import AppKit
import Combine
import Foundation
import GcmdCore
import SwiftUI

enum PopupMode {
    case search
    case editor
    case parameters
}

@MainActor
final class AppModel: ObservableObject {
    @Published var commands: [GcmdCommand] = []
    @Published var query = ""
    @Published var mode: PopupMode = .search
    @Published var draft = GcmdDraft()
    @Published var descriptionText = ""
    @Published var variableRows: [GcmdVariable] = []
    @Published var parameterValues: [String: String] = [:]
    @Published var pendingCommand: GcmdCommand?
    @Published var selectedID: String?
    @Published var notice = ""

    var onFinish: (() -> Void)?
    private let store: GcmdStore
    private var noticeTask: Task<Void, Never>?

    init() {
        do {
            store = try GcmdStore()
        } catch {
            fatalError("Cannot open gcmd storage: \(error.localizedDescription)")
        }
    }

    var filteredCommands: [GcmdCommand] {
        (try? store.search(query)) ?? []
    }

    func configure(arguments: [String]) {
        if arguments.contains("--save") {
            mode = .editor
            draft = GcmdDraft(
                title: argument("--title", in: arguments) ?? "",
                command: argument("--command", in: arguments) ?? "",
                description: "",
                cwd: "",
                tags: argument("--tags", in: arguments) ?? "",
                variables: []
            )
        } else {
            mode = .search
            query = argument("--query", in: arguments) ?? ""
        }
        refresh()
    }

    func refresh() {
        do {
            commands = try store.list()
            if let selectedID, !commands.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func openNewCommand() {
        mode = .editor
        draft = GcmdDraft()
        descriptionText = ""
        variableRows = []
        query = ""
    }

    func addVariable() {
        var number = 1
        let existingNames = Set(variableRows.map(\.name))
        while existingNames.contains("var\(number)") {
            number += 1
        }
        let name = "var\(number)"
        variableRows.append(GcmdVariable(name: name))
        let placeholder = "{{\(name)}}"
        if draft.command.isEmpty {
            draft.command = placeholder
        } else {
            draft.command += " \(placeholder)"
        }
    }

    func openEditor(_ command: GcmdCommand) {
        mode = .editor
        draft = GcmdDraft(command: command)
        descriptionText = command.description
        variableRows = command.variables
    }

    func saveDraft() {
        do {
            draft.description = descriptionText
            draft.variables = variableRows
            if draft.id == nil {
                _ = try store.save(draft)
                showNotice("命令已保存")
            } else {
                _ = try store.update(draft)
                showNotice("命令已更新")
            }
            refresh()
            finishSoon()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        do {
            try store.delete(id: selectedID)
            refresh()
            showNotice("命令已删除")
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func moveSelection(by offset: Int) {
        let items = filteredCommands
        guard !items.isEmpty else { return }
        guard let currentID = self.selectedID else {
            self.selectedID = items[0].id
            return
        }
        let currentIndex = items.firstIndex { $0.id == currentID } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        self.selectedID = items[nextIndex].id
    }

    func editSelected() {
        guard let selected = commands.first(where: { $0.id == selectedID }) else { return }
        openEditor(selected)
    }

    func insertSelected() {
        guard let selected = selectedID.flatMap({ id in
            commands.first { $0.id == id }
        }) ?? filteredCommands.first else {
            showNotice("请先选择一条命令")
            return
        }
        if !selected.variables.isEmpty {
            pendingCommand = selected
            parameterValues = Dictionary(
                uniqueKeysWithValues: selected.variables.map { ($0.name, $0.defaultValue) }
            )
            mode = .parameters
            return
        }
        insertCommandText(selected.command)
    }

    func insertParameters() {
        guard let pendingCommand else { return }
        for variable in pendingCommand.variables where variable.required {
            if parameterValues[variable.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showNotice("请填写 \(variable.name)")
                return
            }
        }
        var commandText = pendingCommand.command
        for variable in pendingCommand.variables {
            commandText = commandText.replacingOccurrences(
                of: "{{\(variable.name)}}",
                with: parameterValues[variable.name, default: ""]
            )
        }
        insertCommandText(commandText)
        self.pendingCommand = nil
    }

    func cancelParameters() {
        pendingCommand = nil
        mode = .search
    }

    func cancelEditor() {
        mode = .search
        refresh()
    }

    private func insertCommandText(_ commandText: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandText, forType: .string)
        if sendToGhostty(commandText) {
            showNotice("命令已插入 Ghostty")
        } else {
            showNotice("命令已复制到剪贴板，请在 Ghostty 中粘贴")
        }
        finishSoon()
    }

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            notice = ""
        }
    }

    private func finishSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.onFinish?()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: GcmdPanel?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = Array(CommandLine.arguments.dropFirst())
        model.onFinish = { NSApp.terminate(nil) }
        model.configure(arguments: arguments)
        DispatchQueue.main.async { [weak self] in
            self?.showPopup(mode: self?.model.mode ?? .search)
        }
    }

    private func showPopup(mode: PopupMode) {
        model.mode = mode
        if mode == .search {
            model.query = ""
            model.refresh()
        } else if mode == .editor && model.draft.command.isEmpty {
            model.openNewCommand()
        }
        let rootView = PopupView(model: model) { [weak self] in
            self?.handleEscape()
        }
        let hosting = NSHostingView(rootView: rootView)
        let height: CGFloat = mode == .editor ? 680 : mode == .parameters ? 500 : 540
        let popup = GcmdPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        popup.isReleasedWhenClosed = false
        popup.isOpaque = false
        popup.backgroundColor = .clear
        popup.hasShadow = true
        popup.level = .floating
        popup.becomesKeyOnlyIfNeeded = false
        popup.hidesOnDeactivate = false
        popup.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        popup.contentView = hosting
        popup.center()
        panel = popup
        NSApp.activate(ignoringOtherApps: true)
        popup.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            popup.makeKey()
            popup.makeFirstResponder(hosting)
        }
        installKeyMonitor()
    }

    private func closeAndExit() {
        removeKeyMonitor()
        panel?.orderOut(nil)
        NSApp.terminate(nil)
    }

    private func handleEscape() {
        if model.mode == .search {
            closeAndExit()
        } else if model.mode == .parameters {
            model.cancelParameters()
        } else {
            model.cancelEditor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.handleEscape()
                return nil
            }
            if self.model.mode == .parameters {
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.model.insertParameters()
                    return nil
                }
                return event
            }
            guard self.model.mode == .search else { return event }
            switch event.keyCode {
            case 126:
                self.model.moveSelection(by: -1)
                return nil
            case 125:
                self.model.moveSelection(by: 1)
                return nil
            case 36, 76:
                self.model.insertSelected()
                return nil
            case 14 where event.modifierFlags.contains(.command):
                self.model.editSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

final class GcmdPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PopupView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if model.mode == .search {
                    SearchView(model: model)
                } else if model.mode == .parameters {
                    ParameterView(model: model)
                } else {
                    EditorView(model: model, close: close)
                }
            }
            if !model.notice.isEmpty {
                Text(model.notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.notice, in: Capsule())
                    .padding(.bottom, 10)
            }
        }
        .frame(
            width: 680,
            height: model.mode == .editor ? 680 : model.mode == .parameters ? 500 : 540
        )
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onExitCommand(perform: close)
    }
}

struct SearchView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.muted)
                TextField("搜索命令、标签或标题", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.text)
                    .focused($searchFocused)
                    .onSubmit { model.insertSelected() }
                Spacer(minLength: 8)
                KeyHint("esc")
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(Palette.searchField, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.borderStrong, lineWidth: 1)
            )
            .padding(12)

            HStack(spacing: 8) {
                Text("COMMANDS")
                    .paletteLabel()
                Text("\(model.filteredCommands.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Button {
                    model.openNewCommand()
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(PaletteButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if model.filteredCommands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 21))
                        .foregroundStyle(Palette.muted)
                    Text("没有匹配命令")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text("尝试搜索标题、标签或命令内容")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(model.filteredCommands) { command in
                                CommandRow(
                                    command: command,
                                    selected: command.id == model.selectedID,
                                    onInsert: {
                                        model.selectedID = command.id
                                        model.insertSelected()
                                    },
                                    onSelect: {
                                        model.selectedID = command.id
                                    },
                                    onEdit: {
                                        model.openEditor(command)
                                    },
                                    onDelete: {
                                        model.selectedID = command.id
                                        model.deleteSelected()
                                    }
                                )
                                .id(command.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: model.selectedID) { selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 5) {
                KeyHint("return")
                Text("插入")
                KeyHint("⌘E")
                Text("编辑")
                Spacer()
                Button("删除", role: .destructive, action: model.deleteSelected)
                    .buttonStyle(PaletteButtonStyle(destructive: true))
                    .disabled(model.selectedID == nil)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.footer)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
        .onChange(of: model.query) { _ in
            if !model.filteredCommands.contains(where: { $0.id == model.selectedID }) {
                model.selectedID = nil
            }
        }
    }
}

struct CommandRow: View {
    let command: GcmdCommand
    let selected: Bool
    let onInsert: () -> Void
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            if selected {
                onInsert()
            } else {
                onSelect()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? Palette.accent : Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(
                        selected ? Palette.accentSoft : Palette.iconBackground,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(command.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                    }
                    Text(command.command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.command)
                        .lineLimit(1)
                    if !command.description.isEmpty {
                        Text(command.description)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    if !command.tags.isEmpty {
                        Text(command.tags.map { "#\($0)" }.joined(separator: "  "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.accentMuted)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                selected ? Palette.selected : isHovered ? Palette.hovered : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        selected
                            ? Palette.accent.opacity(0.32)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("编辑", action: onEdit)
            Button("插入", action: onInsert)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

struct EditorView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: model.draft.id == nil ? "plus.circle" : "pencil")
                    .foregroundStyle(Palette.accent)
                Text(model.draft.id == nil ? "保存命令" : "编辑命令")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                KeyHint("esc")
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COMMAND")
                            .paletteLabel()
                        TextEditor(text: $model.draft.command)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Palette.text)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 142)
                            .background(Palette.searchField, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Palette.border, lineWidth: 1)
                            )
                    }

                    PaletteField(
                        label: "DESCRIPTION",
                        placeholder: "说明这条命令的用途",
                        text: $model.descriptionText
                    )

                    PaletteField(label: "TITLE", placeholder: "给这条命令一个容易搜索的名字", text: $model.draft.title)
                    PaletteField(label: "TAGS", placeholder: "git, daily", text: $model.draft.tags)

                    HStack {
                        Text("VARIABLES")
                            .paletteLabel()
                        Spacer()
                        Button {
                            model.addVariable()
                        } label: {
                            Label("添加变量", systemImage: "plus")
                        }
                        .buttonStyle(PaletteButtonStyle())
                    }

                    if model.variableRows.isEmpty {
                        Text("在命令中使用 {{name}}，保存后插入时填写实际值。")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    } else {
                        ForEach(model.variableRows.indices, id: \.self) { index in
                            VariableEditorRow(
                                variable: $model.variableRows[index],
                                onDelete: {
                                    model.variableRows.remove(at: index)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            HStack {
                Text("保存后不会自动执行命令")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button("取消", action: close)
                    .buttonStyle(PaletteButtonStyle())
                Button(model.draft.id == nil ? "保存" : "更新") {
                    model.saveDraft()
                }
                .buttonStyle(PaletteButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Palette.footer)
        }
    }
}

struct VariableEditorRow: View {
    @Binding var variable: GcmdVariable
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("变量名", text: $variable.name)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
            TextField("默认值", text: $variable.defaultValue)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
            Toggle("必填", isOn: $variable.required)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(PaletteButtonStyle(destructive: true))
        }
        .padding(8)
        .background(Palette.searchField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
    }
}

struct ParameterView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focusedVariable: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Palette.accent)
                Text("填写命令参数")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                KeyHint("esc")
            }
            .padding(18)

            if let command = model.pendingCommand {
                Text(previewText(for: command))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.command)
                    .lineLimit(3)
                    .padding(.horizontal, 18)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(commandVariables, id: \.name) { variable in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(variable.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Palette.accent)
                                if variable.required {
                                    Text("必填")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            TextField(
                                variable.defaultValue.isEmpty ? "输入值" : variable.defaultValue,
                                text: Binding(
                                    get: { model.parameterValues[variable.name, default: ""] },
                                    set: { model.parameterValues[variable.name] = $0 }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Palette.text)
                            .focused($focusedVariable, equals: variable.name)
                            .padding(9)
                            .background(Palette.searchField, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Palette.border, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(18)
            }

            HStack {
                Spacer()
                Button("取消") { model.cancelParameters() }
                    .buttonStyle(PaletteButtonStyle())
                Button("插入") { model.insertParameters() }
                    .buttonStyle(PaletteButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
            .background(Palette.footer)
        }
        .onAppear {
            let firstVariable = commandVariables.first?.name
            DispatchQueue.main.async {
                focusedVariable = firstVariable
            }
        }
    }

    private var commandVariables: [GcmdVariable] {
        model.pendingCommand?.variables ?? []
    }

    private func previewText(for command: GcmdCommand) -> String {
        command.variables.reduce(command.command) { result, variable in
            let value = model.parameterValues[variable.name, default: ""]
            return result.replacingOccurrences(
                of: "{{\(variable.name)}}",
                with: value.isEmpty ? variable.name : value
            )
        }
    }
}

private enum Palette {
    static let panel = Color(red: 0.105, green: 0.118, blue: 0.145)
    static let searchField = Color(red: 0.055, green: 0.064, blue: 0.082)
    static let footer = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let selected = Color(red: 0.14, green: 0.23, blue: 0.18)
    static let hovered = Color(red: 0.095, green: 0.12, blue: 0.105)
    static let iconBackground = Color(red: 0.15, green: 0.17, blue: 0.20)
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.16)
    static let text = Color(red: 0.92, green: 0.94, blue: 0.96)
    static let muted = Color(red: 0.54, green: 0.59, blue: 0.66)
    static let command = Color(red: 0.72, green: 0.82, blue: 0.75)
    static let accent = Color(red: 0.52, green: 0.83, blue: 0.60)
    static let accentMuted = Color(red: 0.48, green: 0.68, blue: 0.53)
    static let accentSoft = Color(red: 0.16, green: 0.31, blue: 0.20)
    static let notice = Color(red: 0.16, green: 0.30, blue: 0.20)
}

struct KeyHint: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Palette.iconBackground, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Palette.border, lineWidth: 1)
            )
    }
}

struct PaletteButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                primary ? Palette.panel :
                    destructive ? Color(red: 0.95, green: 0.56, blue: 0.56) : Palette.text
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                primary ? Palette.accent :
                    destructive ? Color.red.opacity(0.10) : Palette.iconBackground,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(primary ? Palette.accent.opacity(0.7) : Palette.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct PaletteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .paletteLabel()
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(Palette.searchField, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Palette.border, lineWidth: 1)
                )
        }
    }
}

private extension View {
    func paletteLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Palette.muted)
    }
}

@main
struct GcmdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private func argument(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), args.index(after: index) < args.endIndex else {
        return nil
    }
    return args[args.index(after: index)]
}

private func sendToGhostty(_ command: String) -> Bool {
    let escaped = command
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    let script = """
    tell application "Ghostty"
        activate
        set term to focused terminal of selected tab of front window
        input text "\(escaped)" to term
    end tell
    """
    guard let appleScript = NSAppleScript(source: script) else { return false }
    var error: NSDictionary?
    appleScript.executeAndReturnError(&error)
    return error == nil
}
