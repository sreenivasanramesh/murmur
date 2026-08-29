import MurmurDictionary
import AppKit
import SwiftUI

/// The dictionary: add, edit, delete, search in a modern minimalist list.
struct DictionaryPanel: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Search & Add Entry Button
            HStack(spacing: DS.Space.snug) {
                ModernSearchField(text: $query, placeholder: "Search dictionary terms...")
                    .frame(maxWidth: 340)

                Spacer()

                Button {
                    isAdding = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add Entry")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: DS.Color.accent.opacity(0.3), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, DS.Space.roomy)
            .padding(.vertical, 12)
            .background(DS.Color.header)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.Color.border).frame(height: 1)
            }

            if entries.isEmpty {
                ModernEmptyPanel(
                    icon: "character.book.closed.fill",
                    title: store.entries.isEmpty ? "Dictionary is empty" : "No matching terms",
                    message: store.entries.isEmpty
                        ? "Teach Murmur domain terminology, names, or phonetic corrections."
                        : "Try searching for a different word or phrase."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            ModernDictionaryRow(
                                entry: entry,
                                onEdit: { editing = entry },
                                onToggle: {
                                    var updated = entry
                                    updated.isEnabled.toggle()
                                    store.update(updated)
                                },
                                onDelete: { store.delete(entry) }
                            )
                        }
                    }
                    .padding(DS.Space.roomy)
                }
            }

            // Footer
            HStack(spacing: 8) {
                Text("\(store.entries.count) custom \(store.entries.count == 1 ? "entry" : "entries") active")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkMuted)

                Spacer()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text("Reveal dictionary.txt in Finder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(DS.Color.inkSecondary)
                }
                .buttonStyle(.plain)
                .help(DictionaryStore.fileURL.path)
            }
            .padding(.horizontal, DS.Space.roomy)
            .padding(.vertical, 10)
            .background(DS.Color.header)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.Color.border).frame(height: 1)
            }
        }
        .sheet(isPresented: $isAdding) {
            ModernDictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            ModernDictionaryEditor(entry: entry) { store.update($0) }
        }
    }
}

// MARK: - Modern Dictionary Row

private struct ModernDictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Enabled Toggle Checkbox
            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.isEnabled ? DS.Color.accent : DS.Color.tabBg)
                        .frame(width: 16, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(entry.isEnabled ? DS.Color.accent : DS.Color.cardBorder, lineWidth: 1))

                    if entry.isEnabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Kind Badge
            Text(entry.kind == .correction ? "Correction" : "Term")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(entry.kind == .correction ? DS.Color.success : Color.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((entry.kind == .correction ? DS.Color.success : Color.purple).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

            // Main Text Content
            HStack(spacing: 6) {
                if entry.kind == .correction {
                    Text(entry.hear)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.inkMuted)
                        .strikethrough()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DS.Color.inkMuted)
                }

                Text(entry.write)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.ink)
            }

            Spacer()

            // Actions (Edit & Delete)
            if isHovering {
                HStack(spacing: 6) {
                    Button(action: onEdit) {
                        Text("Edit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Color.inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(4)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Delete entry")
                }
            }
        }
        .opacity(entry.isEnabled ? 1 : 0.45)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isHovering ? DS.Color.cardHover : DS.Color.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovering ? DS.Color.cardBorder.opacity(1.5) : DS.Color.cardBorder, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Modern Editor

private struct ModernDictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text(entry == nil ? "New Dictionary Entry" : "Edit Dictionary Entry")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.inkMuted)
                }
                .buttonStyle(.plain)
            }

            // Segmented Kind Picker
            HStack(spacing: 4) {
                ForEach([DictionaryEntry.Kind.term, .correction], id: \.self) { candidate in
                    Button {
                        withAnimation { kind = candidate }
                    } label: {
                        Text(candidate == .term ? "Term" : "Correction")
                            .font(.system(size: 12, weight: kind == candidate ? .semibold : .medium))
                            .foregroundStyle(kind == candidate ? DS.Color.ink : DS.Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background {
                                if kind == candidate {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(DS.Color.tabActive)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 8))

            // Inputs
            VStack(alignment: .leading, spacing: 12) {
                if kind == .correction {
                    fieldView(
                        label: "When you hear (spoken text):",
                        prompt: "cloud code",
                        text: $hear
                    )
                }

                fieldView(
                    label: kind == .correction ? "Replace with (written text):" : "Word or phrase:",
                    prompt: kind == .correction ? "Claude Code" : "Kubernetes",
                    text: $write
                )
            }

            // Warnings
            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.meterAmber)
                        .padding(.top, 2)

                    Text(warning.message)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.meterAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            // Action Buttons
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 440)
        .background(DS.Color.card)
    }

    private func fieldView(label: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Color.inkSecondary)

            ZStack(alignment: .leading) {
                if text.wrappedValue.isEmpty {
                    Text(prompt)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Color.inkMuted)
                }
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.Color.tabBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Color.cardBorder, lineWidth: 1))
        }
    }
}
