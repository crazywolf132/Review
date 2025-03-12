//
//  GitHubService.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import Foundation
import Cocoa
import Kingfisher

class GitHubService {
    private let token: String
    private let session = URLSession.shared
    // Simple circular image processor with 14x14 size
    private let profileImageProcessor = RoundCornerImageProcessor(cornerRadius: 7, targetSize: CGSize(width: 14, height: 14), roundingCorners: .all, backgroundColor: .clear)

    init(token: String) {
        self.token = token
        
        // Configure Kingfisher with our settings
        let config = KingfisherManager.shared.downloader.sessionConfiguration
        var defaultHeaders = config.httpAdditionalHeaders ?? [:]
        defaultHeaders["Accept"] = "application/vnd.github+json"
        defaultHeaders["Authorization"] = "Bearer \(token)"
        defaultHeaders["X-GitHub-Api-Version"] = "2022-11-28"
        config.httpAdditionalHeaders = defaultHeaders
        KingfisherManager.shared.downloader.sessionConfiguration = config
        
        // Configure Kingfisher cache with more robust settings
        _ = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!.appending("/com.review.profileCache")
        // Can't directly set directory due to protection level
        // ImageCache.default.diskStorage.config.directory = URL(fileURLWithPath: cachePath)
        ImageCache.default.diskStorage.config.expiration = .days(30) // Cache images for a month
        ImageCache.default.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024 // 50MB memory cache
        ImageCache.default.memoryStorage.config.expiration = .days(1) // Keep in memory for a day
        // Ensure cache is cleaned up occasionally but not too aggressively
        ImageCache.default.cleanExpiredDiskCache()
    }
    
    // Download author profile image from URL using Kingfisher
    func downloadProfileImage(from urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            print("DEBUG: Invalid image URL: \(urlString)")
            completion(nil)
            return
        }
        
        // Check if we can get the image directly from Kingfisher's cache first
        if let cachedImage = ImageCache.default.retrieveImageInMemoryCache(forKey: urlString) {
            print("DEBUG: Using in-memory cached profile image")
            completion(cachedImage)
            return
        }
        
        // The disk cache check is async and can throw, let's use KingfisherManager instead
        // which handles all the caching logic for us
        print("DEBUG: Downloading profile image with Kingfisher from: \(urlString)")
        
        // Options for image loading
        let options: KingfisherOptionsInfo = [
            .processor(profileImageProcessor),
            .scaleFactor(NSScreen.main?.backingScaleFactor ?? 2.0),
            .cacheOriginalImage,
            .transition(.fade(0.2)),
            .backgroundDecode, // Decode on background thread to avoid UI stuttering
            .diskCacheExpiration(.days(30)), // Override global setting for this specific image if needed
            .memoryCacheExpiration(.days(1)),
            .downloadPriority(0.9), // Higher priority for profile images
            .callbackQueue(.mainAsync) // Ensure callback on main thread
        ]
        
        // Use Kingfisher to download and cache the image with built-in processing
        KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            switch result {
            case .success(let value):
                completion(value.image)
            case .failure(let error):
                print("DEBUG: Error downloading image with Kingfisher: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
    // MARK: - GraphQL Implementation
    
    func fetchPullRequestsWithGraphQL(completion: @escaping ([PullRequest]) -> Void) {
        guard !token.isEmpty else {
            print("DEBUG: No GitHub token available in GitHubService")
            completion([])
            return
        }
        
        print("DEBUG: About to create GraphQL request with token: \(String(token.prefix(4)))...")
        
        // GraphQL endpoint always stays the same
        let url = URL(string: "https://api.github.com/graphql")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Simplified query that should work correctly
        let graphQLQuery = """
        {
          viewer {
            login
            
            reviewRequested: pullRequests(first: 30, states: [OPEN], filterBy: {reviewRequested: true}) {
              nodes {
                number
                title
                url
                repository {
                  name
                  owner {
                    login
                  }
                  isArchived
                }
                author {
                  login
                  avatarUrl
                }
                mergeable
              }
            }
            
            authored: pullRequests(first: 30, states: [OPEN]) {
              nodes {
                number
                title
                url
                repository {
                  name
                  owner {
                    login
                  }
                  isArchived
                }
                author {
                  login
                  avatarUrl
                }
                mergeable
              }
            }
          }
        }
        """
        
        // Create the request body
        let requestBody: [String: Any] = ["query": graphQLQuery]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            print("DEBUG: Successfully serialized GraphQL query to JSON")
        } catch {
            print("DEBUG: Failed to serialize GraphQL query: \(error.localizedDescription)")
            completion([])
            return
        }
        
        print("DEBUG: Starting GraphQL request to GitHub API")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG: GraphQL request error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("DEBUG: Invalid response type")
                completion([])
                return
            }
            
            print("DEBUG: Received HTTP status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 401 {
                print("DEBUG: Unauthorized - Invalid token")
                completion([])
                return
            }
            
            guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                print("DEBUG: Unexpected status code: \(httpResponse.statusCode)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("DEBUG: Error response body: \(responseString)")
                }
                completion([])
                return
            }
            
            guard let data = data else {
                print("DEBUG: No data received")
                completion([])
                return
            }
            
            do {
                // Parse the GraphQL response
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    print("DEBUG: Failed to parse JSON response")
                    completion([])
                    return
                }
                
                // Check for errors in the GraphQL response
                if let errors = json["errors"] as? [[String: Any]] {
                    print("DEBUG: GraphQL returned errors:")
                    for (index, error) in errors.enumerated() {
                        if let message = error["message"] as? String {
                            print("DEBUG: Error \(index+1): \(message)")
                        }
                    }
                    completion([])
                    return
                }
                
                guard let data = json["data"] as? [String: Any] else {
                    print("DEBUG: No data field in GraphQL response")
                    completion([])
                    return
                }
                
                guard let viewer = data["viewer"] as? [String: Any] else {
                    print("DEBUG: No viewer field in data")
                    completion([])
                    return
                }
                
                // Process the results into our PullRequest model
                var allPullRequests: [PullRequest] = []
                let userLogin = viewer["login"] as? String ?? ""
                print("DEBUG: GraphQL query identified user as: \(userLogin)")
                
                // Process PRs needing review
                if let reviewRequested = viewer["reviewRequested"] as? [String: Any] {
                    print("DEBUG: Found reviewRequested field")
                    if let nodes = reviewRequested["nodes"] as? [[String: Any]] {
                        print("DEBUG: Found \(nodes.count) PRs needing review")
                        let prs = nodes.compactMap { node -> PullRequest? in
                            let pr = self.parsePullRequestFromGraphQL(node, status: .needsReview, currentUser: userLogin)
                            if pr != nil {
                                print("DEBUG: Successfully parsed PR: #\(pr!.number) - \(pr!.title)")
                            }
                            return pr
                        }
                        print("DEBUG: Successfully parsed \(prs.count) PRs needing review")
                        allPullRequests.append(contentsOf: prs)
                    } else {
                        print("DEBUG: No nodes field in reviewRequested or not an array")
                    }
                } else {
                    print("DEBUG: No reviewRequested field found in viewer or not a dictionary")
                }
                
                // Process authored PRs
                if let authored = viewer["authored"] as? [String: Any] {
                    print("DEBUG: Found authored field")
                    if let nodes = authored["nodes"] as? [[String: Any]] {
                        print("DEBUG: Found \(nodes.count) authored PRs")
                        let prs = nodes.compactMap { node -> PullRequest? in
                            let pr = self.parsePullRequestFromGraphQL(node, status: .yourPR, currentUser: userLogin)
                            if pr != nil {
                                print("DEBUG: Successfully parsed PR: #\(pr!.number) - \(pr!.title)")
                            }
                            return pr
                        }
                        print("DEBUG: Successfully parsed \(prs.count) authored PRs")
                        allPullRequests.append(contentsOf: prs)
                    } else {
                        print("DEBUG: No nodes field in authored or not an array")
                    }
                } else {
                    print("DEBUG: No authored field found in viewer or not a dictionary")
                }
                
                // Remove duplicates based on URL
                let uniquePRs = self.removeDuplicatePRs(allPullRequests)
                print("DEBUG: Final count after deduplication: \(uniquePRs.count) PRs")
                
                // Return the results
                DispatchQueue.main.async {
                    print("DEBUG: Returning \(uniquePRs.count) pull requests to completion handler")
                    completion(uniquePRs)
                }
                
            } catch {
                print("DEBUG: JSON parsing error: \(error.localizedDescription)")
                completion([])
            }
        }.resume()
    }
    
    // Helper method to parse a PR from GraphQL response
    private func parsePullRequestFromGraphQL(_ node: [String: Any], status: PullRequest.Status, currentUser: String) -> PullRequest? {
        // First check that we have the required fields
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = node["url"] as? String else {
            print("DEBUG: PR missing basic required fields")
            return nil
        }
        
        // Handle author - could be null if user deleted their account
        let authorLogin: String
        let authorImageURL: String
        
        if let author = node["author"] as? [String: Any] {
            authorLogin = author["login"] as? String ?? "Unknown"
            authorImageURL = author["avatarUrl"] as? String ?? ""
        } else {
            // Handle deleted user
            authorLogin = "Deleted User"
            authorImageURL = ""
        }
        
        // Extract repository info - may not exist in some cases
        let isArchived: Bool
        if let repository = node["repository"] as? [String: Any] {
            isArchived = repository["isArchived"] as? Bool ?? false
        } else {
            isArchived = false
        }
        
        // Determine merge conflicts status
        let hasMergeConflicts: Bool
        if let mergeable = node["mergeable"] as? String {
            hasMergeConflicts = mergeable == "CONFLICTING"
        } else {
            hasMergeConflicts = false
        }
        
        // Create the pull request
        return PullRequest(
            number: number,
            title: title,
            author: authorLogin, 
            authorImageURL: authorImageURL,
            status: status,
            url: url,
            hasMergeConflicts: hasMergeConflicts,
            actionsStatus: .unknown, // Simplified for first implementation
            isInArchivedRepo: isArchived
        )
    }
    
    // Helper to remove duplicate PRs (keeping the one with highest priority status)
    private func removeDuplicatePRs(_ prs: [PullRequest]) -> [PullRequest] {
        // Define the status priority (lower number = higher priority)
        let statusPriority: [PullRequest.Status: Int] = [
            .needsReview: 1,
            .yourPR: 2,
            .assigned: 3,
            .mentioned: 4,
            .waitingReview: 5,
            .approved: 6
        ]
        
        // Group PRs by URL
        var prByUrl: [String: PullRequest] = [:]
        
        for pr in prs {
            if let existingPR = prByUrl[pr.url] {
                // If we already have this PR, keep the one with higher priority status
                let existingPriority = statusPriority[existingPR.status] ?? 999
                let newPriority = statusPriority[pr.status] ?? 999
                
                if newPriority < existingPriority {
                    prByUrl[pr.url] = pr
                }
            } else {
                prByUrl[pr.url] = pr
            }
        }
        
        return Array(prByUrl.values)
    }
    
    // Update the main method to use GraphQL with REST API fallback
    func fetchPullRequests(completion: @escaping ([PullRequest]) -> Void) {
        // Try GraphQL first with a fallback
        var graphQLFailed = false
        
        fetchPullRequestsWithGraphQL { prs in
            if prs.isEmpty && !graphQLFailed {
                print("DEBUG: GraphQL returned no PRs, falling back to REST API")
                graphQLFailed = true
                self.fetchPullRequestsWithREST(completion: completion)
            } else {
                completion(prs)
            }
        }
    }
    
    // REST API implementation as fallback
    func fetchPullRequestsWithREST(completion: @escaping ([PullRequest]) -> Void) {
        print("DEBUG: Using REST API fallback")
        
        // Start with an empty array to hold all PRs
        var allPullRequests: [PullRequest] = []
        let group = DispatchGroup()
        
        // Fetch PRs that need the user's review
        group.enter()
        fetchPRsWithQuery("is:open is:pr review-requested:@me", status: .needsReview) { prs in
            allPullRequests.append(contentsOf: prs)
            group.leave()
        }
        
        // Fetch PRs waiting for the user's review
        group.enter()
        fetchPRsWithQuery("is:open is:pr involves:@me -review-requested:@me -author:@me", status: .waitingReview) { prs in
            allPullRequests.append(contentsOf: prs)
            group.leave()
        }
        
        // Fetch PRs authored by the user
        group.enter()
        fetchPRsWithQuery("is:open is:pr author:@me", status: .yourPR) { prs in
            allPullRequests.append(contentsOf: prs)
            group.leave()
        }
        
        // Fetch PRs assigned to the user
        group.enter()
        fetchPRsWithQuery("is:open is:pr assignee:@me -author:@me", status: .assigned) { prs in
            allPullRequests.append(contentsOf: prs)
            group.leave()
        }
        
        // Fetch PRs where the user is mentioned
        group.enter()
        fetchPRsWithQuery("is:open is:pr mentions:@me -author:@me -assignee:@me", status: .mentioned) { prs in
            allPullRequests.append(contentsOf: prs)
            group.leave()
        }
        
        // When all fetches complete, deliver the combined results
        group.notify(queue: .main) {
            completion(allPullRequests)
        }
    }
    
    // Helper method to fetch PRs with a specific query and assign a status
    private func fetchPRsWithQuery(_ query: String, status: PullRequest.Status, completion: @escaping ([PullRequest]) -> Void) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let urlString = "https://api.github.com/search/issues?q=\(encodedQuery)&per_page=100"

        guard let url = URL(string: urlString) else {
            print("DEBUG: Invalid URL format for query: \(query)")
            completion([])
            return
        }

        print("DEBUG: Starting REST request with query: \(query)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG: Network error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("DEBUG: Invalid response type")
                completion([])
                return
            }
            
            if httpResponse.statusCode == 401 {
                print("DEBUG: Unauthorized - Invalid token")
                completion([])
                return
            }
            
            guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                print("DEBUG: Unexpected status code: \(httpResponse.statusCode)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("DEBUG: No data received")
                completion([])
                return
            }
            
            do {
                let searchResult = try JSONDecoder().decode(GitHubSearchResult.self, from: data)
                print("DEBUG: Found \(searchResult.items.count) items for query: \(query)")
                
                if searchResult.items.isEmpty {
                    completion([])
                    return
                }
                
                // Create basic pull requests
                var pullRequests = searchResult.items.map { issue in
                    PullRequest(
                        number: issue.number,
                        title: issue.title,
                        author: issue.user.login,
                        authorImageURL: issue.user.avatar_url,
                        status: status,
                        url: issue.html_url
                    )
                }
                
                let detailGroup = DispatchGroup()
                
                // Extract repo info and set archived flag
                for (index, pr) in pullRequests.enumerated() {
                    if let repoInfo = self.extractRepoInfo(from: pr.url) {
                        detailGroup.enter()
                        self.checkIfRepoIsArchived(owner: repoInfo.owner, repo: repoInfo.repo) { isArchived in
                            pullRequests[index].isInArchivedRepo = isArchived
                            detailGroup.leave()
                        }
                    }
                }
                
                // When all status fetches are complete, return the PRs
                detailGroup.notify(queue: .main) {
                    completion(pullRequests)
                }
            } catch {
                print("DEBUG: JSON decoding error: \(error.localizedDescription)")
                completion([])
            }
        }.resume()
    }
    
    // Check if a repository is archived
    func checkIfRepoIsArchived(owner: String, repo: String, completion: @escaping (Bool) -> Void) {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)"
        
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG: Error fetching repo details: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(false)
                return
            }
            
            do {
                let repoDetails = try JSONDecoder().decode(GitHubRepoDetails.self, from: data)
                completion(repoDetails.archived)
            } catch {
                print("DEBUG: Error decoding repo details: \(error.localizedDescription)")
                completion(false)
            }
        }.resume()
    }
    
    // MARK: - PR Actions
    
    // Submit a PR review
    func submitPRReview(owner: String, repo: String, prNumber: Int, action: PRAction, comment: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(prNumber)/reviews"
        
        guard let url = URL(string: urlString) else {
            print("DEBUG: Invalid URL for PR review")
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        // Prepare the review data based on the action
        var reviewData: [String: Any] = [:]
        
        switch action {
        case .approve:
            reviewData["event"] = "APPROVE"
        case .requestChanges:
            reviewData["event"] = "REQUEST_CHANGES"
        case .comment:
            reviewData["event"] = "COMMENT"
        }
        
        // Add comment if provided
        if let comment = comment, !comment.isEmpty {
            reviewData["body"] = comment
        }
        
        // Convert data to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: reviewData)
        } catch {
            print("DEBUG: Error creating request body: \(error.localizedDescription)")
            completion(false, "Error creating request: \(error.localizedDescription)")
            return
        }
        
        // Submit the review
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG: Network error submitting review: \(error.localizedDescription)")
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, "Invalid response")
                return
            }
            
            // Check HTTP status code
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                completion(true, nil)
            } else {
                var errorMessage = "Error: HTTP \(httpResponse.statusCode)"
                
                // Try to extract error message from response
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    errorMessage = "GitHub says: \(message)"
                }
                
                completion(false, errorMessage)
            }
        }.resume()
    }
    
    // Extract repository information from PR URL
    func extractRepoInfo(from prUrl: String) -> (owner: String, repo: String, number: Int)? {
        // Format is typically: https://github.com/owner/repo/pull/number
        let urlComponents = prUrl.components(separatedBy: "/")
        
        guard urlComponents.count >= 5,
              urlComponents[urlComponents.count - 2] == "pull",
              let prNumber = Int(urlComponents[urlComponents.count - 1]) else {
            return nil
        }
        
        let owner = urlComponents[urlComponents.count - 4]
        let repo = urlComponents[urlComponents.count - 3]
        
        return (owner: owner, repo: repo, number: prNumber)
    }
}

// MARK: - Models for GitHub API JSON Response

struct GitHubSearchResult: Codable {
    let items: [GitHubIssue]
}

struct GitHubIssue: Codable {
    let number: Int
    let title: String
    let html_url: String
    let user: GitHubUser
}

struct GitHubUser: Codable {
    let login: String
    let avatar_url: String
}

// MARK: - Additional Models for GitHub API

struct GitHubPRDetail: Codable {
    let mergeable: Bool?
    let head: GitHubCommitRef
}

struct GitHubCommitRef: Codable {
    let sha: String
}

struct GitHubChecksResponse: Codable {
    let check_runs: [GitHubCheckRun]
}

struct GitHubCheckRun: Codable {
    let status: String
    let conclusion: String?
}

// MARK: - PR Actions Enum

enum PRAction {
    case approve
    case requestChanges
    case comment
    
    var displayName: String {
        switch self {
        case .approve:
            return "Approve"
        case .requestChanges:
            return "Request Changes"
        case .comment:
            return "Comment"
        }
    }
}

// Add the GitHubRepoDetails struct at the end with the other model structs
struct GitHubRepoDetails: Codable {
    let archived: Bool
    let description: String?
    let full_name: String
}
