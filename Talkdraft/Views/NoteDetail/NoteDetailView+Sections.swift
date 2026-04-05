import SwiftUI
import UIKit

struct TitleTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    var isEditable: Bool = true
    var placeholder: String = "Untitled"
    var onReturn: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = TitleEntryTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.clipsToBounds = false
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.contentInsetAdjustmentBehavior = .never
        tv.textAlignment = .center
        tv.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.heightTracksTextView = false
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.maximumNumberOfLines = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.font = Self.titleFont
        tv.textColor = .label
        tv.tintColor = ExpandingTextView.brandColor
        tv.keyboardAppearance = colorScheme == .dark ? .dark : .light
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self

        let normalized = Self.normalized(text)
        if normalized != text {
            DispatchQueue.main.async { self.text = normalized }
        }
        if tv.text != normalized {
            tv.text = normalized
        }

        tv.keyboardAppearance = colorScheme == .dark ? .dark : .light
        tv.isEditable = isEditable
        tv.isSelectable = isEditable
        context.coordinator.updateMeasuredHeight(for: tv)

        if context.coordinator.lastRequestedFocus != isFocused {
            context.coordinator.lastRequestedFocus = isFocused
            if isEditable && isFocused && !tv.isFirstResponder {
                DispatchQueue.main.async {
                    guard !tv.isFirstResponder else { return }
                    _ = tv.becomeFirstResponder()
                }
            } else if !isFocused && tv.isFirstResponder {
                DispatchQueue.main.async {
                    guard tv.isFirstResponder else { return }
                    tv.resignFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(Self.titleFont.lineHeight + 6), ceil(fitting.height)))
    }

    static let titleDisplayFont = Font.custom("Bricolage Grotesque", size: 28, relativeTo: .title).weight(.bold)

    static let titleFont: UIFont = {
        let size: CGFloat = 28
        let weightAxis = fourCharTag("wght")
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "Bricolage Grotesque",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [weightAxis: 600]
        ])
        let weighted = UIFont(descriptor: descriptor, size: size)
        if weighted.familyName != ".SFUI" {
            return weighted
        }
        return UIFont(name: "Bricolage Grotesque", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }()

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "")
    }

    static let minimumHeight = ceil(titleFont.lineHeight + 6)

    static func fourCharTag(_ string: String) -> NSNumber {
        let value = string.utf8.reduce(UInt32(0)) { partial, byte in
            (partial << 8) + UInt32(byte)
        }
        return NSNumber(value: value)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TitleTextView
        var lastRequestedFocus = false

        init(_ parent: TitleTextView) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            parent.onReturn()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            let normalized = TitleTextView.normalized(textView.text)
            if textView.text != normalized {
                textView.text = normalized
            }
            parent.text = normalized
            textView.invalidateIntrinsicContentSize()
            textView.setNeedsLayout()
            updateMeasuredHeight(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
            updateMeasuredHeight(for: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
            updateMeasuredHeight(for: textView)
        }

        func updateMeasuredHeight(for textView: UITextView) {
            let width = textView.bounds.width > 0
                ? textView.bounds.width
                : max((textView.window?.windowScene?.screen.bounds.width ?? textView.superview?.bounds.width ?? 320) - 48, 0)
            let fitting = textView.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            let nextHeight = max(TitleTextView.minimumHeight, ceil(fitting.height))
            guard abs(parent.measuredHeight - nextHeight) > 0.5 else { return }
            DispatchQueue.main.async {
                self.parent.measuredHeight = nextHeight
            }
        }
    }

    final class TitleEntryTextView: UITextView {
        override var contentSize: CGSize {
            didSet {
                guard oldValue != contentSize else { return }
                invalidateIntrinsicContentSize()
            }
        }

        override var intrinsicContentSize: CGSize {
            let fallbackWidth = window?.windowScene?.screen.bounds.width ?? superview?.bounds.width ?? 320
            let fitting = sizeThatFits(
                CGSize(
                    width: bounds.width > 0 ? bounds.width : fallbackWidth,
                    height: .greatestFiniteMagnitude
                )
            )
            return CGSize(width: UIView.noIntrinsicMetric, height: fitting.height)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let topOffset = CGPoint(x: 0, y: -adjustedContentInset.top)
            guard abs(contentOffset.x - topOffset.x) > 0.5 || abs(contentOffset.y - topOffset.y) > 0.5 else { return }
            UIView.performWithoutAnimation {
                setContentOffset(topOffset, animated: false)
            }
        }
    }
}

extension NoteDetailView {
    static func normalizedTitleInput(_ newValue: String) -> (title: String, moveFocusToBody: Bool) {
        guard newValue.contains(where: \.isNewline) else {
            return (newValue, false)
        }

        let normalized = newValue
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return (normalized, true)
    }

    func moveFocusFromTitleToBody() {
        let transition = Self.normalizedTitleInput(editedTitle)
        editedTitle = transition.title

        var noAnimation = Transaction()
        noAnimation.animation = nil
        withTransaction(noAnimation) {
            isTitleFocusHandoff = true
            titleFocused = false
        }
        DispatchQueue.main.async {
            withTransaction(noAnimation) {
                contentFocused = true
                moveCursorToEnd = true
                isTitleFocusHandoff = false
            }
        }
    }

    @ViewBuilder
    func deadZone(height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
            .onTapGesture {}
    }

    var metadataRow: some View {
        HStack(spacing: 12) {
            if let duration = note.durationSeconds, note.audioUrl != nil {
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        audioExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                        Text(formattedDuration(Int(duration)))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.darkSurface : Color(hex: "#EDE5E2"))
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                Text(note.createdAt, format: .dateTime.month(.wide).day().year())
                Text(" · ")
                    .foregroundStyle(.tertiary)
                Text(note.createdAt, format: .dateTime.hour().minute())
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    var audioPlayerView: some View {
        HStack(spacing: 12) {
            Button {
                guard let url = audioURL else { return }
                player.togglePlayback(url: url)
            } label: {
                ZStack {
                    if player.isBuffering {
                        ProgressView()
                            .tint(Color.brand)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.body)
                            .foregroundStyle(Color.brand)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(player.isBuffering)

            GeometryReader { geo in
                let progress = player.duration > 0
                    ? player.currentTime / player.duration
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme == .dark ? Color(hex: "#2a2a2a") : Color(hex: "#EDE5E2"))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.brand)
                        .frame(width: max(4, geo.size.width * progress), height: 4)

                    Circle()
                        .fill(Color.brand)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, geo.size.width * progress - 7))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            player.seek(to: fraction * player.duration)
                        }
                )
            }
            .frame(height: 14)

            Text(formattedDuration(Int(player.currentTime)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    func shimmerLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.medium)
            .hidden()
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.primary.opacity(0.35)
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.95), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(
                            x: rewriteSweep * (geo.size.width + geo.size.width * 0.55)
                                - geo.size.width * 0.55
                        )
                    }
                }
                .mask(
                    Text(text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                )
            }
            .onAppear {
                rewriteSweep = 0
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    rewriteSweep = 1
                }
            }
            .onDisappear { rewriteSweep = 0 }
    }

    var bottomFade: some View {
        let bg = colorScheme == .dark ? Color.darkBackground : Color.warmBackground
        return VStack {
            Spacer()
            LinearGradient(colors: [.clear, bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    var bottomBarContainer: some View {
        let bg = colorScheme == .dark ? Color.darkBackground : Color.warmBackground
        return VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, bg.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)

            bottomBar
                .padding(.vertical, keyboardVisible ? 4 : 0)
                .padding(.bottom, keyboardVisible ? 0 : 12)
                .frame(maxWidth: .infinity)
                .background(bg.opacity(0.5))
        }
    }

    var rewriteToolbarState: RewriteToolbarState {
        RewriteToolbarState(
            isRewriting: isRewriting,
            activeRewriteId: activeRewriteId,
            originalContent: note.originalContent,
            persistedContent: persistedEditedContent,
            rewrites: rewrites,
            fallbackLabel: rewriteLabelFallback
        )
    }

    var showsRewriteToolbarLabel: Bool {
        rewriteToolbarState.showsLabel
    }

    var inferredVisibleRewrite: NoteRewrite? {
        rewriteToolbarState.inferredVisibleRewrite
    }

    var effectiveRewriteSelectionId: UUID? {
        rewriteToolbarState.effectiveSelectionId
    }

    var rewriteToolbarLabelText: String {
        rewriteToolbarState.labelText
    }

    var canChooseRewriteSource: Bool {
        note.originalContent != nil && effectiveRewriteSelectionId != nil
    }

    var currentRewriteSourceName: String {
        inferredVisibleRewrite?.displayLabel ?? "Current Version"
    }

    func repairMissingActiveRewriteSelection() {
        guard activeRewriteId == nil,
              note.activeRewriteId == nil,
              let inferredVisibleRewrite else {
            return
        }

        activeRewriteId = inferredVisibleRewrite.id
        rewriteLabelFallback = nil

        var updated = note
        updated.activeRewriteId = inferredVisibleRewrite.id
        noteStore.updateNote(updated)
    }

    @ViewBuilder
    func rewriteToolbarLabelView(_ label: String, showsChevron: Bool) -> some View {
        let chevron = Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9))
            .fontWeight(.regular)
            .foregroundStyle(.tertiary)

        HStack(spacing: 2) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)

            if showsChevron {
                chevron
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: 240, alignment: .center)
        .layoutPriority(1)
        .transaction { transaction in
            transaction.animation = nil
        }
        .foregroundStyle(Color.primary)
    }

    @ToolbarContentBuilder
    func toolbarContent() -> some ToolbarContent {
        if showsRewriteToolbarLabel {
            ToolbarItem(placement: .principal) {
                let selectionId = effectiveRewriteSelectionId
                let label = rewriteToolbarLabelText
                ZStack {
                    if isRewriting {
                        shimmerLabel(rewritingLabel.isEmpty ? label : rewritingLabel)
                    } else {
                        Menu {
                            Section {
                                Button {
                                    switchToOriginal()
                                } label: {
                                    if selectionId == nil {
                                        Label("Original", systemImage: "checkmark")
                                    } else {
                                        Text("Original")
                                    }
                                }
                            }

                            if rewrites.isEmpty {
                                Section {
                                    Button {
                                    } label: {
                                        Label("Loading rewrites…", systemImage: "ellipsis")
                                    }
                                    .disabled(true)
                                }
                            } else {
                                Section {
                                    ForEach(rewrites) { rewrite in
                                        Button {
                                            switchToRewrite(rewrite)
                                        } label: {
                                            if rewrite.id == selectionId {
                                                Label(rewrite.displayLabel, systemImage: "checkmark")
                                            } else {
                                                Text(rewrite.displayLabel)
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            rewriteToolbarLabelView(label, showsChevron: true)
                        }
                        .menuIndicator(.hidden)
                    }
                }
                .opacity(rewriteLabelOpacity)
            }
        }

        if !isTranscribing {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        startAppendRecording(scrollToBottom: true)
                    } label: {
                        Label(note.source == .voice ? "Record More" : "Record", systemImage: "mic")
                    }
                    .disabled(isAppendRecording || isAppendTranscribing || isRewriting)

                    if note.audioUrl != nil {
                        Button {
                            downloadAudio()
                        } label: {
                            if isDownloadingAudio {
                                Label { Text("Downloading…") } icon: { ProgressView() }
                            } else {
                                Label("Export Audio", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isDownloadingAudio)
                    }

                    Divider()

                    if let rewriteId = activeRewriteId,
                       let rewrite = rewrites.first(where: { $0.id == rewriteId }) {
                        Button(role: .destructive) {
                            pendingDeleteRewrite = rewrite
                        } label: {
                            Label("Delete This Rewrite", systemImage: "wand.and.sparkles")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .fontWeight(.medium)
                        .frame(width: 36, height: 36)
                }
            }
        }
    }

    var scrollContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).id("scrollTop")

            if !(isTranscribing && transcribingIsLong) {
                deadZone(height: 12)
                metadataRow

                if audioExpanded, audioURL != nil {
                    deadZone(height: 12)
                    audioPlayerView
                        .padding(.horizontal, 24)
                }

                deadZone(height: 20)
                titleField
            }

            if isTranscribing && transcribingIsLong {
                transcribingIndicator
            } else if isTranscribing {
                Text("Transcribing…")
                    .font(.body.italic())
                    .fontDesign(nil)
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .phaseAnimator([false, true]) { content, pulse in
                        content.opacity(pulse ? 0.4 : 1.0)
                    } animation: { _ in
                        .easeInOut(duration: 1.5)
                    }
            } else if isWaitingForConnection {
                waitingForConnectionView
                    .padding(.top, 40)
            } else if isTranscriptionFailed {
                transcriptionFailedView
                    .padding(.top, 40)
            } else {
                if !detectedSpeakers.isEmpty {
                    speakerChipsRow
                        .padding(.top, 28)
                        .padding(.horizontal, 24)
                }
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                contentField
            }
        }
    }

    var titleField: some View {
        let containerHeight = max(titleHeight, TitleTextView.minimumHeight)

        return ZStack {
            if isGeneratingTitle {
                Text(titlePhrases[titlePhraseIndex])
                    .font(TitleTextView.titleDisplayFont)
                    .fontDesign(nil)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if editedTitle.isEmpty && !isGeneratingTitle {
                Text("Untitled")
                    .font(TitleTextView.titleDisplayFont)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
                    .opacity(titleRevealOpacity)
            }

            TitleTextView(
                text: editedTitleBinding,
                isFocused: Binding(
                    get: { titleFocused },
                    set: { focused in
                        titleFocused = focused
                        if focused {
                            contentFocused = false
                            moveCursorToEnd = false
                        }
                    }
                ),
                measuredHeight: $titleHeight,
                isEditable: !isRewriting && !isGeneratingTitle,
                placeholder: "",
                onReturn: moveFocusFromTitleToBody
            )
            .frame(height: titleHeight)
            .opacity(isGeneratingTitle ? 0 : titleRevealOpacity)
            .allowsHitTesting(!isGeneratingTitle)
        }
        .frame(maxWidth: .infinity, minHeight: containerHeight, alignment: .center)
        .padding(.horizontal, 24)
    }

    var speakerChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(detectedSpeakers, id: \.self) { key in
                    let color = speakerColor(for: key)
                    Button {
                        presentSpeakerRename(key)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                            Text(key)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(color)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(color.opacity(selectedSpeaker == key
                                    ? (colorScheme == .dark ? 0.24 : 0.18)
                                    : (colorScheme == .dark ? 0.15 : 0.1)))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    color.opacity(selectedSpeaker == key ? 0.5 : 0.25),
                                    lineWidth: selectedSpeaker == key ? 1.5 : 1
                                )
                        )
                        .opacity(selectedSpeaker != nil && selectedSpeaker != key ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var contentField: some View {
        ExpandingTextView(
            text: editedContentBinding,
            isFocused: $contentFocused,
            cursorPosition: $cursorPosition,
            highlightRange: $highlightRange,
            preserveScroll: $preserveScroll,
            isEditable: !isAppendRecording && !isAppendTranscribing && !isRewriting,
            font: .roundedBody(),
            lineSpacing: 6,
            placeholder: "Start typing...",
            speakerColors: speakerColorMap,
            selectedSpeaker: selectedSpeaker,
            horizontalPadding: 24,
            moveCursorToEnd: $moveCursorToEnd,
            onSpeakerTap: { toggleSpeakerSelection($0) },
            onSpeakerLongPress: { presentSpeakerRename($0) }
        )
        .opacity(contentOpacity)
    }

    var keyboardVisible: Bool { contentFocused }

    var bottomBar: some View {
        Group {
            if isAppendRecording {
                NoteDetailAppendRecordingControls(
                    isTranscribing: isAppendTranscribing,
                    isPaused: appendRecorder.isPaused,
                    remainingSeconds: max(0, 900 - Int(appendRecorder.elapsedSeconds)),
                    onCancel: cancelAppendRecording,
                    onRestart: restartAppendRecording,
                    onStop: stopAppendRecording,
                    onTogglePause: toggleAppendPause
                )
            } else {
                NoteDetailNormalBottomBar(
                    keyboardVisible: keyboardVisible,
                    categoryColor: category.map { Color.categoryColor(hex: $0.color) },
                    isAppendTranscribing: isAppendTranscribing,
                    onShowCategoryPicker: presentCategoryPicker,
                    onShowRewriteSheet: presentRewriteSheet,
                    onShowRewriteSourceOptions: presentRewriteSourceOptions,
                    onShare: presentTextShareSheet,
                    onStartAppendRecording: { startAppendRecording() },
                    onDismissKeyboard: { contentFocused = false }
                )
            }
        }
    }
}
