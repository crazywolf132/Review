//
//  SettingsManager.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import Foundation
import LaunchAtLogin

class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let tokenKey = "githubToken"
    
    init() {
        // Set default values if not already set
        if defaults.object(forKey: "displayUserIcon") == nil {
            defaults.set(true, forKey: "displayUserIcon")
        }
        if defaults.object(forKey: "displayPRNumber") == nil {
            defaults.set(true, forKey: "displayPRNumber")
        }
        if defaults.object(forKey: "displayPRTitle") == nil {
            defaults.set(true, forKey: "displayPRTitle")
        }
        if defaults.object(forKey: "displayRepoName") == nil {
            defaults.set(true, forKey: "displayRepoName")
        }
        if defaults.object(forKey: "displayPRStatus") == nil {
            defaults.set(true, forKey: "displayPRStatus")
        }
        if defaults.object(forKey: "displayStatusIcon") == nil {
            defaults.set(true, forKey: "displayStatusIcon")
        }
        
        // Initialize refresh interval if not set (default to 5 minutes = 300 seconds)
        if defaults.object(forKey: "refreshIntervalSeconds") == nil {
            defaults.set(300, forKey: "refreshIntervalSeconds")
        }
        
        // Initialize visible status groups if not set
        if defaults.object(forKey: "visibleStatusGroups") == nil {
            // Default to all statuses visible
            let allStatuses = PullRequest.Status.allCases.map { $0.rawValue }
            defaults.set(allStatuses, forKey: "visibleStatusGroups")
        }
        
        // Initialize showArchivedRepos if not set
        if defaults.object(forKey: "showArchivedRepos") == nil {
            defaults.set(false, forKey: "showArchivedRepos")
        }
    }

    var githubToken: String? {
        get { 
            let token = defaults.string(forKey: tokenKey)
            print("DEBUG: Retrieved token from UserDefaults: \(token != nil ? "exists" : "nil")")
            return token
        }
        set { 
            print("DEBUG: Setting new token to UserDefaults: \(newValue != nil ? "not nil" : "nil")")
            // Force synchronize to ensure the token is saved immediately
            defaults.setValue(newValue, forKey: tokenKey)
            defaults.synchronize()
        }
    }
    
    // Method to verify if the token is actually valid
    func isTokenValid() -> Bool {
        guard let token = githubToken else {
            print("DEBUG: Token is nil")
            return false
        }
        
        if token.isEmpty {
            print("DEBUG: Token is empty")
            return false
        }
        
        print("DEBUG: Token appears valid")
        return true
    }

    // Reset token (for debugging)
    func resetToken() {
        defaults.removeObject(forKey: tokenKey)
        defaults.synchronize()
        print("DEBUG: Token has been reset")
    }

    var selectedStatuses: [PullRequest.Status] {
        get {
            guard let rawStatuses = defaults.array(forKey: "selectedStatuses") as? [String] else {
                return PullRequest.Status.allCases
            }
            return rawStatuses.compactMap { PullRequest.Status(rawValue: $0) }
        }
        set {
            let rawStatuses = newValue.map { $0.rawValue }
            defaults.setValue(rawStatuses, forKey: "selectedStatuses")
        }
    }
    
    // Manage which status groups are visible
    var visibleStatusGroups: [PullRequest.Status] {
        get {
            guard let rawStatuses = defaults.array(forKey: "visibleStatusGroups") as? [String] else {
                return PullRequest.Status.allCases
            }
            return rawStatuses.compactMap { PullRequest.Status(rawValue: $0) }
        }
        set {
            let rawStatuses = newValue.map { $0.rawValue }
            defaults.setValue(rawStatuses, forKey: "visibleStatusGroups")
            defaults.synchronize()
        }
    }
    
    // Check if a specific status group is visible
    func isStatusGroupVisible(_ status: PullRequest.Status) -> Bool {
        return visibleStatusGroups.contains(status)
    }
    
    // Toggle visibility of a status group
    func toggleStatusGroupVisibility(_ status: PullRequest.Status) {
        var currentVisible = visibleStatusGroups
        
        if currentVisible.contains(status) {
            currentVisible.removeAll { $0 == status }
        } else {
            currentVisible.append(status)
        }
        
        visibleStatusGroups = currentVisible
    }

    var displayUserIcon: Bool {
        get { defaults.bool(forKey: "displayUserIcon") }
        set { defaults.set(newValue, forKey: "displayUserIcon") }
    }

    var displayPRNumber: Bool {
        get { defaults.bool(forKey: "displayPRNumber") }
        set { defaults.set(newValue, forKey: "displayPRNumber") }
    }

    var displayPRTitle: Bool {
        get { defaults.bool(forKey: "displayPRTitle") }
        set { defaults.set(newValue, forKey: "displayPRTitle") }
    }

    var displayRepoName: Bool {
        get { defaults.bool(forKey: "displayRepoName") }
        set { defaults.set(newValue, forKey: "displayRepoName") }
    }

    var displayPRStatus: Bool {
        get { defaults.bool(forKey: "displayPRStatus") }
        set { defaults.set(newValue, forKey: "displayPRStatus") }
    }
    
    var displayStatusIcon: Bool {
        get { defaults.bool(forKey: "displayStatusIcon") }
        set { defaults.set(newValue, forKey: "displayStatusIcon") }
    }
    
    // Refresh interval in seconds
    var refreshIntervalSeconds: TimeInterval {
        get { 
            let interval = defaults.double(forKey: "refreshIntervalSeconds")
            // Ensure we have a valid interval (at least 60 seconds, default to 300 if broken)
            return interval >= 60 ? interval : 300
        }
        set { 
            // Enforce minimum refresh interval of 60 seconds
            let validInterval = max(60, newValue)
            defaults.set(validInterval, forKey: "refreshIntervalSeconds") 
        }
    }
    
    // Helper method to convert seconds to a human-readable format
    func refreshIntervalDescription() -> String {
        let seconds = refreshIntervalSeconds
        
        if seconds == 60 {
            return "1 minute"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) minutes"
        } else if seconds == 3600 {
            return "1 hour"
        } else {
            let hours = Int(seconds / 3600)
            return "\(hours) hours"
        }
    }

    // Add the property for showing archived repositories
    var showArchivedRepos: Bool {
        get { defaults.bool(forKey: "showArchivedRepos") }
        set { defaults.set(newValue, forKey: "showArchivedRepos") }
    }
    
    // Property for launch at login setting using LaunchAtLogin
    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }
}
