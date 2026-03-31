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

@main
struct TalkdraftWidget: Widget {
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
