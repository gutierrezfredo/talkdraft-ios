import SwiftUI

struct BackgroundRecordingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Recording continued in background")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
    }
}
