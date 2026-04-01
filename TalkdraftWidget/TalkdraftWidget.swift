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
    private let brandViolet = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    private let deepViolet = Color(red: 0x5B / 255, green: 0x21 / 255, blue: 0xB6 / 255)

    var body: some View {
        Link(destination: URL(string: "talkdraft://record")!) {
            ZStack {
                // Radial glow behind mic
                RadialGradient(
                    colors: [brandViolet.opacity(0.6), .clear],
                    center: .init(x: 0.5, y: 0.3),
                    startRadius: 10,
                    endRadius: 90
                )

                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 100, height: 100)
                    .background(Circle().fill(.black.opacity(0.2)))
                    .offset(y: -10)

                // Luna at bottom-left
                VStack {
                    Spacer()
                    HStack {
                        Image("luna-widget")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 130)
                            .offset(x: -20, y: 18)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [brandViolet, deepViolet],
                startPoint: .top,
                endPoint: .bottom
            )
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
