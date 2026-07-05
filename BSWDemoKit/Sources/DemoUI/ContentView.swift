#if canImport(SwiftUI)
import SwiftUI
import DemoCore
import BSWFoundation

public struct ContentView: View {
    @State private var viewModel: ViewModel?
    @State private var randomNumber: Int = 0

    public init() {}

    public var body: some View {
        if let viewModel {
            List {
                LabeledContent {
                    Text(viewModel.ipAddress)
                } label: {
                    Text("IP Address:")
                }

                LabeledContent {
                    Text("\(viewModel.counter)")
                } label: {
                    Text("Counter:")
                }

                LabeledContent {
                    Text("\(randomNumber)")
                } label: {
                    Text("Random number:")
                }
            }
            .task {
                for await value in viewModel.stream(for: \.randomNumber) {
                    randomNumber = value
                }
            }
            .safeAreaBar(edge: .bottom) {
                Button {
                    viewModel.bump()
                } label: {
                    Text("Bump Counter")
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Content View")
        } else {
            ProgressView()
                .task {
                    viewModel = try! await ViewModel()
                }
        }
    }
}

#Preview {
    ContentView()
}
#endif
