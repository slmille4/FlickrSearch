//
//  AsyncSearchableViewModel.swift
//  FlickrSearch
//
//  Created by Steve on 1/15/25.
//

import SwiftUI
import Combine

public class AsyncSearchableViewModel<Item>: ObservableObject {
    /// The async function that will load data based on a search string
    public let loadData: (String) async throws -> [Item]

    /// The array of items that the view will display
    @Published public private(set) var items: [Item] = []

    /// The text we are searching for; changes to this trigger the load pipeline
    @Published public var searchText: String = ""

    /// Indicates whether a load operation is currently in progress
    @Published public private(set) var isLoading = false

    /// Stores any error caught while loading
    @Published public private(set) var error: Error?

    /// A function used to sort the final list
    let sortFunction: (Item, Item) -> Bool

    private var cancellables = Set<AnyCancellable>()

    /// Initialize the ViewModel with a load function and an optional sort function.
    /// If `Item` is `Comparable`, you could rely on the `<` operator by default.
    public init(
        loadData: @escaping (String) async throws -> [Item],
        sortFunction: @escaping (Item, Item) -> Bool
    ) {
        self.loadData = loadData
        self.sortFunction = sortFunction
        setupSearchPipeline()
    }

    /// Convenience initializer for items that are `Comparable`.
    public convenience init(loadData: @escaping (String) async throws -> [Item]) where Item: Comparable {
        self.init(loadData: loadData, sortFunction: { $0 < $1 })
    }

    // MARK: - Private Helpers
    
    private func setupSearchPipeline() {
        $searchText
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self = self else { return }
                Task {
                    await self.performSearch(with: newValue)
                }
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func performSearch(with text: String) async {
        guard !text.isEmpty else { return }
        self.isLoading = true
        self.error = nil
        
        do {
            let results = try await loadData(text)
            self.items = results.sorted(by: sortFunction)
        } catch {
            print(error)
            self.error = error
        }
        
        // If not cancelled, end loading
        self.isLoading = false
    }
}
