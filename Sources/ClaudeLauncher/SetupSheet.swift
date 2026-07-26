import SwiftUI

// MARK: - Project curation sheet
//
// Every folder found is listed. Markers only decide which boxes start ticked —
// they never decide what's visible. The previous design filtered the list by
// marker, which silently hid real projects like `exec-dashboard` with no way to
// discover they were missing.

struct SetupSheet: View {
    @EnvironmentObject private var store: LauncherStore

    @State private var selected: Set<String> = []
    @State private var filter = ""
    @State private var hasSeeded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.isScanning {
                scanningState
            } else {
                candidateList
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .onChange(of: store.candidates) { _, _ in seedSelection() }
        .onAppear { seedSelection() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose your projects")
                    .font(.system(size: 15, weight: .semibold))
                Text("Everything found in your folders is listed. Tick the ones that are real projects — you can change this later.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1)))

                Spacer()

                Button("All") { selected = Set(visibleCandidates.map(\.path)) }
                Button("None") { selected.subtract(visibleCandidates.map(\.path)) }
                Button("Likely") {
                    selected = Set(store.candidates.filter(\.isLikelyProject).map(\.path))
                }
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    // MARK: States

    private var scanningState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Looking through your folders…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var candidateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleCandidates) { candidate in
                    CandidateRow(
                        candidate: candidate,
                        isOn: Binding(
                            get: { selected.contains(candidate.path) },
                            set: { isOn in
                                if isOn { selected.insert(candidate.path) }
                                else { selected.remove(candidate.path) }
                            })
                    )
                    Divider().opacity(0.4)
                }
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if visibleCandidates.isEmpty {
                Text(store.candidates.isEmpty
                     ? "No folders found."
                     : "Nothing matches “\(filter)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("\(selected.count) of \(store.candidates.count) selected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") { store.cancelCuration() }
                .keyboardShortcut(.cancelAction)

            Button(selected.isEmpty ? "Choose Projects" : "Add \(selected.count)") {
                store.applyCuration(selectedPaths: selected)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected.isEmpty)
        }
        .padding(16)
    }

    // MARK: Helpers

    private var visibleCandidates: [ProjectCandidate] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.candidates }
        return store.candidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayPath.localizedCaseInsensitiveContains(query)
        }
    }

    /// Pre-ticks likely projects on a first run, or whatever is already in the
    /// library when re-running the picker, so an existing setup isn't lost.
    private func seedSelection() {
        guard !hasSeeded, !store.candidates.isEmpty else { return }
        hasSeeded = true

        let curated = store.curatedPaths
        selected = curated.isEmpty
            ? Set(store.candidates.filter(\.isLikelyProject).map(\.path))
            : curated
    }
}

/// One checkbox row in the setup sheet.
private struct CandidateRow: View {
    let candidate: ProjectCandidate
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 7) {
                Image(systemName: candidate.isGitRepo ? "folder.badge.gearshape" : "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(candidate.displayPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 8)

                // Says *why* a box is pre-ticked, rather than leaving the
                // pre-selection unexplained.
                Text(candidate.hint)
                    .font(.system(size: 10, design: candidate.marker == nil ? .default : .monospaced))
                    .foregroundStyle(candidate.marker == nil ? .tertiary : .secondary)
            }
            // Indent to show nesting, capped so a deep tree can't push the text
            // off the right edge.
            .padding(.leading, CGFloat(min(candidate.depth, 4)) * 14)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}
