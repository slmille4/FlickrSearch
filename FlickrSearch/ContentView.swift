//
//  ContentView.swift
//  FlickrSearch
//
//  Created by Steve on 1/15/25.
//

import SwiftUI
import Combine

// MARK: - Main View
struct ContentView: View {
    // We hold a single instance of the ViewModel
    @StateObject private var viewModel: AsyncSearchableViewModel<FlickrItem>
    
    init() {
        // Provide async logic to load Flickr items by search text
        let vm = AsyncSearchableViewModel<FlickrItem>(
            loadData: { searchText in
                // Build Flickr feed URL
                let encodedSearch = searchText
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let urlString = "https://api.flickr.com/services/feeds/photos_public.gne?format=json&nojsoncallback=1&tags=\(encodedSearch)"
                guard let url = URL(string: urlString) else { return [] }
                
                // Fetch + decode
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let feed = try decoder.decode(FlickrFeed.self, from: data)
                return feed.items
            },
            // Sort so newest published are first
            sortFunction: { $0.published > $1.published }
        )
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        NavigationStack {
            if let error = viewModel.error {
                VStack(spacing: 10) {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(5)
                }
                .padding()
                .background(.red)
                .cornerRadius(8)
                .padding()
                .transition(.opacity)
            } else {
                // We pass the ViewModel to SearchedView
                SearchedGridView(viewModel: viewModel)
                // 1) The search field is declared here
                    .searchable(text: $viewModel.searchText)
                    .navigationTitle("Flickr Search")
            }
        }
    }
}

struct SearchedGridView: View {
    @ObservedObject var viewModel: AsyncSearchableViewModel<FlickrItem>
    
    // This environment is valid here because .searchable is in ContentView
    @Environment(\.dismissSearch) private var dismissSearch
    
    // Track which item is currently selected
    @State private var selectedItem: FlickrItem?
    @State private var showDetail = false
    
    var body: some View {
        ZStack {
            // 1) Grid of items
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 2)
                ], spacing: 2) {
                    ForEach(viewModel.items) { item in
                        GridItemView(item: item)
                            .onTapGesture {
                                // Dismiss the search bar
                                //dismissSearch()
                                UIApplication.shared.endEditing()
                                self.selectedItem = item
                                // Show the detail as full screen
                                
                                self.showDetail = true
                            }
                    }
                }
                .padding(2)
            }
            
            // 2) Optional loading overlay
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .scaleEffect(1.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        // 3) Full-screen cover for the detail
        .fullScreenCover(isPresented: $showDetail) {
            if let selectedItem {
                DetailView(item: selectedItem)
            }
        }
    }
}

/// A simple cell that displays the FlickrItem image
struct GridItemView: View {
    let item: FlickrItem
    
    var body: some View {
        AsyncImage(url: item.media.m) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
            @unknown default:
                EmptyView()
            }
        }
        .frame(height: 150)
        .clipped()
    }
}

extension UIApplication {
    /// Forces any active text field (including a .searchable) to resign first responder.
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
    // MARK: - Detail View
struct DetailView: View {
    let item: FlickrItem
    
    @Environment(\.dismiss) private var dismiss
    @State private var imageSize: CGSize?
    @State private var imageLoadError: Error?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Async image for the main photo
                    AsyncImage(url: item.media.m) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Image(systemName: "photo")
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding()
                    
                    // Title
                    Text(item.title)
                        .font(.title2)
                        .bold()
                    
                    // HTML description
                    HTMLText(htmlString: item.description)
                        .font(.body)
                    
                    // Additional metadata
                    Text("By: \(item.author)")
                        .font(.subheadline)
                    
                    Text("Published: \(item.published.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    // Show image dimension if loaded
                    if let size = imageSize {
                        Text("Image Size: \(Int(size.width)) x \(Int(size.height))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else if let error = imageLoadError {
                        Text("Error loading size: \(error.localizedDescription)")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A close button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()       // closes fullScreenCover
                    }
                }
            }
            // Load the raw bytes to get actual image size
            .task {
                await loadImageSize()
            }
        }
    }
    
    private func loadImageSize() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: item.media.m)
            if let uiImage = UIImage(data: data) {
                imageSize = uiImage.size
            }
        } catch {
            imageLoadError = error
        }
    }
}


extension AttributedString {
    init?(html: String) {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        do {
            let attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            self.init(attributed)
        } catch {
            return nil
        }
    }
}

// A simple SwiftUI view that displays HTML as formatted text.
struct HTMLText: View {
    let htmlString: String
    
    var body: some View {
        if let attributed = AttributedString(html: htmlString) {
            Text(attributed)
        } else {
            // fallback if we can't parse the HTML
            Text(htmlString)
        }
    }
}

#Preview {
    ContentView()
}
