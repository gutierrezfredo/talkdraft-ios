import SwiftUI
import WidgetKit

struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        let entry = QuickRecordEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct QuickRecordWidgetView: View {
    var body: some View {
        Link(destination: URL(string: "talkdraft://record")!) {
            VStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
                Text("Record")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
        }
    }
}

struct QuickRecordLockScreenView: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        Link(destination: URL(string: "talkdraft://record")!) {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .medium))
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                    Text("Record")
                        .font(.system(.headline, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Image(systemName: "mic.fill")
            }
        }
    }
}

@main
struct TalkdraftWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickRecordHomeWidget()
        QuickRecordLockScreenWidget()
    }
}

struct QuickRecordHomeWidget: Widget {
    let kind = "QuickRecord"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView()
        }
        .configurationDisplayName("Quick Record")
        .description("Tap to start recording a voice note.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickRecordLockScreenWidget: Widget {
    let kind = "QuickRecordLockScreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { _ in
            QuickRecordLockScreenView()
        }
        .configurationDisplayName("Quick Record")
        .description("Tap to start recording a voice note.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
