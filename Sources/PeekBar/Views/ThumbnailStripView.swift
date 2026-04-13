import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailStripView: View {
    @Bindable var store: WindowStore
    let screen: NSScreen
    let isVertical: Bool
    var settings = PeekBarSettings.shared

    @State private var draggingID: CGWindowID?

    private let activationService = WindowActivationService()

    var filteredWindows: [WindowInfo] {
        store.windows(for: screen)
    }

    var body: some View {
        Group {
            if isVertical {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: settings.thumbnailSpacing) {
                        ForEach(filteredWindows) { window in
                            thumbnailView(for: window)
                        }
                    }
                    .padding(4)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: settings.thumbnailSpacing) {
                        ForEach(filteredWindows) { window in
                            thumbnailView(for: window)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func thumbnailView(for window: WindowInfo) -> some View {
        ThumbnailItemView(windowInfo: window, store: store) {
            activationService.activate(window)
        }
        .opacity(draggingID == window.id ? 0.4 : 1.0)
        .onDrag {
            draggingID = window.id
            return NSItemProvider(object: "\(window.id)" as NSString)
        }
        .onDrop(of: [.plainText], delegate: ThumbnailDropDelegate(
            targetID: window.id,
            store: store,
            screen: screen,
            draggingID: $draggingID
        ))
    }
}

struct ThumbnailDropDelegate: DropDelegate {
    let targetID: CGWindowID
    let store: WindowStore
    let screen: NSScreen
    @Binding var draggingID: CGWindowID?

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingID, sourceID != targetID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            store.moveWindow(sourceID, before: targetID, on: screen)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
