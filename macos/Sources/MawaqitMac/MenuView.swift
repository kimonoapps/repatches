import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: MawaqitStore
    var openSettings: () -> Void
    var onSizeChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            schedulePage
        }
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .controlSize(.regular)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
        })
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard height > 0 else { return }
            onSizeChange?(ceil(height))
        }
    }

    @ViewBuilder
    private var schedulePage: some View {
            search
            if let reason = store.locationUnavailable {
                // Disabled buttons show no tooltip on macOS, so say why the arrow is grayed out.
                Label(reason, systemImage: "location.slash")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.results.isEmpty || store.calculatedSuggestion != nil {
                // Search results have their own bounded area; the schedule never scrolls.
                ScrollView {
                    VStack(spacing: 8) {
                        if !store.results.isEmpty { results }
                        if store.calculatedSuggestion != nil { calculatedOption }
                    }
                }
                .frame(height: 180)
            } else if let view = store.schedule {
                schedule(view)
            }
            if !store.status.isEmpty {
                Text(store.status)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(store.status)
            }
            controls
    }

    private var search: some View {
        GlassRow { HStack(spacing: 10) {
            NativeSearchField(text: $store.query, onSubmit: store.submitSearch)
                .disabled(store.isLocating)
                .accessibilityLabel("Search mosques or locations")
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { store.useCurrentLocation() } label: {
                Group {
                    if store.isLocating { ProgressView().controlSize(.small) }
                    else { Image(systemName: "location") }
                }
                .glassLabel(in: .circle)
            }
            .modifier(GlassButton(round: true))
            .disabled(store.isLocating || store.isLoading || store.locationUnavailable != nil)
            .help(store.locationUnavailable ?? "Use current location")
            .accessibilityLabel("Use current location")
        } }
    }

    private var results: some View {
        VStack(spacing: 10) {
            ForEach(store.results) { mosque in
                Button { store.choose(slug: mosque.slug, name: mosque.name) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mosque.name).fontWeight(.medium)
                            if let location = mosque.location {
                                Text(location).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(10).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var calculatedOption: some View {
        Button { store.useCalculatedTimes() } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.circle").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use calculated prayer times").fontWeight(.medium)
                    Text("AlAdhan · City, country or coordinates")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("May differ from your local mosque.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func schedule(_ view: ScheduleView) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.state.name ?? store.state.slug ?? store.state.calculationQuery ?? "Mawaqit")
                .font(.headline).lineLimit(1)
            Text(view.dateText).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Text("\(view.timezone)\(isCached ? " · cached" : "")")
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button(action: openSettings) {
                    Text(store.isCalculated ? "AlAdhan ⓘ" : "Mawaqit ⓘ")
                }
                .buttonStyle(.plain)
                .help("Prayer time source and calculation details")

            }
            .font(.caption).foregroundStyle(.secondary)
            let summary = Presentation.nextSummary(view)
            if !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Prayer times").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Presentation.displayPrayers(view)) { prayer in
                    prayerRow(prayer, view: view)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Night & sunrise").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 7) {
                milestoneRow("Islamic midnight", date: view.milestones.midnight, phase: .midnight, view: view)
                milestoneRow("Last third", date: view.milestones.lastThird, phase: .lastThird, view: view)
                milestoneRow("Sunrise", date: view.milestones.sunrise, phase: .sunrise, view: view)
            }.padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Divider()
            GlassRow { HStack {
                Button { store.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .glassLabel(in: .capsule)
                }
                .modifier(GlassButton(round: false))
                .keyboardShortcut("r")
                .disabled(!store.hasLocation || store.isLoading)
                Spacer()
                Button(action: openSettings) {
                    Label("Settings…", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                        .glassLabel(in: .circle)
                }
                .modifier(GlassButton(round: true))
                .help("Settings… (⌘,)")
                .keyboardShortcut(",")
                .popover(isPresented: $store.showingSettings, arrowEdge: .top) {
                    SettingsPage(store: store)
                }
            } }
        }
    }

    private func prayerRow(_ prayer: Prayer, view: ScheduleView) -> some View {
        let current = prayer.id == view.current?.id
        let next = prayer.id == view.next?.id
        let past = (prayer.end ?? .distantFuture) <= view.now
        return HStack(spacing: 8) {
            Image(systemName: icon(for: prayer.name))
                .font(.body).frame(width: 18)
                .foregroundStyle(current ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(prayer.name).font(.body.weight(current || next ? .semibold : .regular))
                if current, let end = prayer.end {
                    Text("Ends at \(time(end, view))\(prayer.name == "Isha" ? " · Islamic midnight" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if next {
                Text(Presentation.prayerDetail(prayer, view: view))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            } else if !current {
                Text(Presentation.prayerDetail(prayer, view: view))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(prayer.time).font(.body.weight(.medium)).monospacedDigit()
        }
        .foregroundStyle(past ? .secondary : .primary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(current ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func milestoneRow(_ title: String, date: Date, phase: NightPhase, view: ScheduleView) -> some View {
        let selected = view.milestones.phase == phase
        return HStack {
            Text(title)
            Spacer()
            if selected { Text("in \(store.remaining(until: date))").font(.caption).foregroundStyle(.tint) }
            else if view.milestones.active && date <= view.now { Text("Passed").font(.caption).foregroundStyle(.secondary) }
            Text(time(date, view)).monospacedDigit()
        }
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .foregroundStyle(selected ? .primary : .secondary)
    }

    private func time(_ date: Date, _ view: ScheduleView) -> String { ScheduleBuilder.time(date, timezone: view.timezone) }
    private var isCached: Bool { store.state.fetched.map { Date().timeIntervalSince($0) > 3600 } ?? true }
    private func icon(for prayer: String) -> String {
        switch prayer {
        case "Fajr", "Isha": "moon.stars.fill"
        case "Dhuhr": "sun.max.fill"
        case "Asr": "sun.haze.fill"
        case "Maghrib": "sunset.fill"
        default: "circle.fill"
        }
    }
}

/// NSSearchField supplies the system bezel, clear button, and editing behavior.
private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.placeholderString = "Mosque, city or coordinates"
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.sendsWholeSearchString = true
        field.setAccessibilityLabel("Mosque, city or coordinates")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        init(parent: NativeSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        @objc func submit(_ field: NSSearchField) {
            parent.text = field.stringValue
            if !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parent.onSubmit()
            }
        }
    }
}

/// Settings shown in a popover anchored to the gear button.
struct SettingsPage: View {
    @ObservedObject var store: MawaqitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        section("General") {
            toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: store.setLaunchAtLogin))
            Divider()
            toggle("Icon only in menu bar", isOn: Binding(get: { store.iconOnlyMenuBar }, set: store.setIconOnlyMenuBar))
        }
        section("Prayer reminders") {
            toggle("Notifications", isOn: Binding(get: { store.state.notificationsEnabled }, set: store.setNotifications))
            if store.state.notificationsEnabled && store.notificationsBlocked {
                Label("Notifications are turned off for Mawaqit in System Settings.", systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Notification Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.akramb.mawaqit")!)
                }
            } else {
                Text("Alerts at each prayer and the last third of the night.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if store.hasLocation {
            section("Prayer time source") {
                Text(store.isCalculated ? "Calculated by AlAdhan" : "Mosque schedule from Mawaqit")
                if store.isCalculated {
                    Text(store.state.calculationMethod ?? "Automatic local method")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Calculated times may differ from your local mosque or religious authority.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !store.status.isEmpty {
            Text(store.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 440
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum GlassLabelShape { case circle, capsule }

extension View {
    /// Interactive Liquid Glass as part of a button's label, so the whole glass shape is
    /// the click target (Apple: apply glassEffect to the custom view itself).
    @ViewBuilder func glassLabel(in shape: GlassLabelShape) -> some View {
        if #available(macOS 26.0, *) {
            switch shape {
            case .circle:
                frame(width: 30, height: 30)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            case .capsule:
                padding(.horizontal, 14).frame(height: 30)
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            self
        }
    }
}

/// The glass label replaces the bezel on macOS 26+; older systems keep the standard button.
private struct GlassButton: ViewModifier {
    var round: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.plain)
        } else if round, #available(macOS 14.0, *) {
            content.buttonBorderShape(.circle)
        } else {
            content
        }
    }
}

/// Glass elements in one row share a container so they render and blend together.
private struct GlassRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { content() }
        } else {
            content()
        }
    }
}

