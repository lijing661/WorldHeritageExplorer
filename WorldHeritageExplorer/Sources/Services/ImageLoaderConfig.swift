//  ImageLoaderConfig.swift
//  WorldHeritageExplorer
//
//  Centralized Kingfisher downloader & cache tuning for better throughput & UX.

import Foundation
import Kingfisher

enum ImageLoaderConfig {
    static func configure() {
        // Configure downloader concurrency & timeouts
        let downloader = KingfisherManager.shared.downloader
        var session = downloader.sessionConfiguration
        session.httpMaximumConnectionsPerHost = 8 // increase parallelism per host
        session.timeoutIntervalForRequest = 8     // quicker failover
        session.timeoutIntervalForResource = 15
        if #available(iOS 11.0, *) { session.waitsForConnectivity = true }
        downloader.sessionConfiguration = session
        downloader.downloadTimeout = 12

        // Cache tuning: keep reasonable memory & disk budget
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 150 * 1024 * 1024 // ~150MB
        cache.memoryStorage.config.expiration = .seconds(1800)        // 30 min in-memory
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024        // ~500MB on disk
        cache.diskStorage.config.expiration = .days(7)
    }
}
