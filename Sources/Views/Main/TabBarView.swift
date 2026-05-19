import SwiftUI

struct TabBarView: View {
    var tabs: TabCollection
    var onNewTab: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.tabs, id: \.id) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tabs.activeTabID == tab.id,
                            onSelect: {
                                tabs.selectTab(id: tab.id)
                            },
                            onClose: {
                                Task {
                                    await tabs.closeTab(id: tab.id)
                                }
                            }
                        )

                        Divider()
                            .frame(height: 16)
                    }
                }
            }
            
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("새 탭")
            
            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }
}
