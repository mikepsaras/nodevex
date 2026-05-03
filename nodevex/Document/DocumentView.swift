import SwiftUI
import SwiftData

struct DocumentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        } detail: {
            ZStack(alignment: .bottomLeading) {
                CanvasView()
                CanvasFooter()
                    .padding(12)
            }
            .toolbar {
                DocumentToolbar()
            }
        }
        .navigationTitle("NodeVex")
    }
}
