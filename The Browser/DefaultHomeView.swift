import SwiftUI

struct DefaultHomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Hello")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(Color.browserAccent)

            Text("Set a custom home page in Settings to start browsing.")
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DefaultHomeView()
        .background(Color.browserBackground)
}
