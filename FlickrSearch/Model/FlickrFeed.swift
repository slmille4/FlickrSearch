//
//  FlickrFeed.swift
//  FlickrSearch
//
//  Created by Steve on 1/15/25.
//
import Foundation

struct FlickrFeed: Decodable {
    let title: String
    let link: String
    let description: String
    let modified: Date
    let generator: String
    let items: [FlickrItem]
}

struct FlickrItem: Decodable, Identifiable {
    let title: String
    let link: URL
    let media: FlickrMedia
    let dateTaken: Date
    let description: String
    let published: Date
    let author: String
    let authorId: String
    let tags: String
    
    var id: String { link.absoluteString }
    
    // Custom coding keys to match JSON structure
    enum CodingKeys: String, CodingKey {
        case title
        case link
        case media
        case dateTaken = "date_taken"
        case description
        case published
        case author
        case authorId = "author_id"
        case tags
    }
}

struct FlickrMedia: Decodable {
    let m: URL
}
