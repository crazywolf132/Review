//
//  PullRequest.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import Foundation

struct PullRequest: Identifiable {
    enum Status: String, CaseIterable {
        case needsReview = "Needs Your Review"
        case approved = "Approved"
        case waitingReview = "Waiting for Your Review"
        case assigned = "Assigned to You"
        case mentioned = "Mentioned You"
        case yourPR = "Your Pull Requests"
        case draftPR = "Your Draft PRs"
    }

    let id = UUID()
    let number: Int
    let title: String
    let author: String
    let authorImageURL: String
    let status: Status
    let url: String
    var hasMergeConflicts: Bool = false
    var actionsStatus: ActionsStatus = .unknown
    var isInArchivedRepo: Bool = false
    var isDraft: Bool = false
    var accountName: String = "" // Account the PR belongs to

    enum ActionsStatus {
        case passing
        case failing
        case running
        case unknown
    }
}
