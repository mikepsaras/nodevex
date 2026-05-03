import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Section("Nodes") {
                NodeListView()
            }
            Section("Categories") {
                CategoryListView()
            }
        }
        .listStyle(.sidebar)
    }
}
