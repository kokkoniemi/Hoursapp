import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hoursapp")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Phase 0 scaffold")
                    .font(.title3)
                Text("Menu bar + popover ready. Time tracking UI lands in Phase 2.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 640)
    }
}

#Preview {
    ContentView()
}
