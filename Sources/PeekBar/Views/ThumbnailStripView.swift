import SwiftUI

struct ThumbnailStripView: View {
    @Bindable var store: WindowStore
    let screen: NSScreen
    let isVertical: Bool
    var settings = PeekBarSettings.shared

    private let activationService = WindowActivationService()

    var filteredWindows: [WindowInfo] {
        store.windows(for: screen)
    }

    var body: some View {
        Group {
            if isVertical {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: settings.thumbnailSpacing) {
                        ForEach(filteredWindows) { window in
                            ThumbnailItemView(windowInfo: window, store: store) {
                                activationService.activate(window)
                            }
                        }
                    }
                    .padding(4)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: settings.thumbnailSpacing) {
                        ForEach(filteredWindows) { window in
                            ThumbnailItemView(windowInfo: window, store: store) {
                                activationService.activate(window)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
