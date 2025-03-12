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
    private let tokensKey = "githubTokens"
    private let accountColorsKey = "accountColors"
    
    // Struct to represent a GitHub account
    struct GitHubAccount: Codable, Equatable {
        let username: String
        let token: String
        
        static func == (lhs: GitHubAccount, rhs: GitHubAccount) -> Bool {
            return lhs.username == rhs.username
        }
    }
    
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
        if defaults.object(forKey: "displayAccountName") == nil {
            defaults.set(true, forKey: "displayAccountName")
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
        
        // Initialize account colors if not set
        if defaults.object(forKey: accountColorsKey) == nil {
            defaults.set(Data(), forKey: accountColorsKey)
        }
        
        // Migrate single token to tokens array if needed
        migrateTokenToTokensIfNeeded()
    }
    
    // Migrate the single token to the tokens array if needed
    private func migrateTokenToTokensIfNeeded() {
        if let legacyToken = defaults.string(forKey: tokenKey), !legacyToken.isEmpty {
            // Check if we already have tokens array
            if githubAccounts.isEmpty {
                // Fetch the username associated with this token
                let service = GitHubService(token: legacyToken)
                service.fetchCurrentUsername { [weak self] username in
                    guard let self = self, let username = username else { return }
                    
                    // Create a new account with the legacy token
                    let account = GitHubAccount(username: username, token: legacyToken)
                    var accounts = self.githubAccounts
                    accounts.append(account)
                    
                    // Save the accounts and set it as selected
                    self.githubAccounts = accounts
                    
                    // Clear the legacy token
                    self.defaults.removeObject(forKey: self.tokenKey)
                    self.defaults.synchronize()
                }
            } else {
                // Just clear the legacy token since we already have tokens array
                defaults.removeObject(forKey: tokenKey)
                defaults.synchronize()
            }
        }
    }

    // Legacy support for single token (will be migrated to accounts)
    var githubToken: String? {
        get { 
            // First try to get the selected account's token
            if let account = selectedGitHubAccount {
                return account.token
            }
            
            // Fall back to legacy token
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
    
    // New methods for handling multiple accounts
    var githubAccounts: [GitHubAccount] {
        get {
            if let data = defaults.data(forKey: tokensKey),
               let accounts = try? JSONDecoder().decode([GitHubAccount].self, from: data) {
                return accounts
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: tokensKey)
                defaults.synchronize()
            }
        }
    }
    
    // Helper method to add a new GitHub account
    func addGitHubAccount(username: String, token: String) {
        let newAccount = GitHubAccount(username: username, token: token)
        var accounts = githubAccounts
        
        // Replace if username already exists, otherwise add
        if let index = accounts.firstIndex(where: { $0.username == username }) {
            accounts[index] = newAccount
        } else {
            accounts.append(newAccount)
        }
        
        githubAccounts = accounts
        
        // If this is the first account, set it as selected
        if accounts.count == 1 {
            selectedGitHubAccount = newAccount
        }
    }
    
    // Helper method to remove a GitHub account
    func removeGitHubAccount(username: String) {
        var accounts = githubAccounts
        accounts.removeAll { $0.username == username }
        githubAccounts = accounts
        
        // If the selected account was removed, reset selection
        if selectedGitHubAccount?.username == username {
            selectedGitHubAccount = accounts.first
        }
    }
    
    // Currently selected GitHub account
    var selectedGitHubAccount: GitHubAccount? {
        get {
            if let data = defaults.data(forKey: "selectedGitHubAccount"),
               let account = try? JSONDecoder().decode(GitHubAccount.self, from: data) {
                return account
            }
            
            // Default to first account if nothing is selected
            return githubAccounts.first
        }
        set {
            if let account = newValue, let data = try? JSONEncoder().encode(account) {
                defaults.set(data, forKey: "selectedGitHubAccount")
            } else {
                defaults.removeObject(forKey: "selectedGitHubAccount")
            }
            defaults.synchronize()
            
            // Post notification about account change
            NotificationCenter.default.post(name: Notification.Name("GitHubAccountChanged"), object: nil)
        }
    }
    
    // Method to verify if the token is actually valid
    func isTokenValid() -> Bool {
        // Check if we have any valid accounts
        if !githubAccounts.isEmpty {
            return true
        }
        
        // Fall back to legacy token check if no accounts are set up
        if let token = githubToken, !token.isEmpty {
            return true
        }
        
        return false
    }

    // Reset token (for debugging)
    func resetToken() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: tokensKey)
        defaults.removeObject(forKey: "selectedGitHubAccount")
        defaults.synchronize()
        print("DEBUG: All tokens have been reset")
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
    
    // Track which GitHub accounts are enabled for PR fetching
    var enabledGitHubAccounts: [String] {
        get {
            // By default, all accounts are enabled
            if let accountNames = defaults.array(forKey: "enabledGitHubAccounts") as? [String] {
                return accountNames
            } else {
                // If not yet set, return all account usernames
                return githubAccounts.map { $0.username }
            }
        }
        set {
            defaults.setValue(newValue, forKey: "enabledGitHubAccounts")
            defaults.synchronize()
        }
    }
    
    // Check if a specific account is enabled
    func isAccountEnabled(_ username: String) -> Bool {
        return enabledGitHubAccounts.contains(username)
    }
    
    // Toggle account visibility
    func toggleAccountEnabled(_ username: String) {
        var currentEnabled = enabledGitHubAccounts
        
        if currentEnabled.contains(username) {
            currentEnabled.removeAll { $0 == username }
        } else {
            currentEnabled.append(username)
        }
        
        enabledGitHubAccounts = currentEnabled
    }

    // Get active accounts that are currently enabled for PR fetching
    func getEnabledActiveAccounts() -> [GitHubAccount] {
        let accounts = githubAccounts
        let enabledNames = enabledGitHubAccounts
        
        // If we have accounts, return only the enabled ones
        if !accounts.isEmpty {
            // If no accounts are explicitly enabled, show all accounts (default behavior)
            if enabledNames.isEmpty {
                return accounts
            }
            return accounts.filter { enabledNames.contains($0.username) }
        }
        
        // Legacy token handling
        if let legacyToken = githubToken, !legacyToken.isEmpty {
            return [GitHubAccount(username: "Legacy Account", token: legacyToken)]
        }
        
        return []
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

    var displayAccountName: Bool {
        get { defaults.bool(forKey: "displayAccountName") }
        set { defaults.set(newValue, forKey: "displayAccountName") }
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

    // Helper method to update token for an existing GitHub account
    func updateGitHubAccountToken(username: String, newToken: String) -> Bool {
        var accounts = githubAccounts
        
        // Find the account with the specified username
        if let index = accounts.firstIndex(where: { $0.username == username }) {
            // Create a new account with the updated token
            let updatedAccount = GitHubAccount(username: username, token: newToken)
            accounts[index] = updatedAccount
            
            // Save the updated accounts list
            githubAccounts = accounts
            
            // Update the selected account if it was this one
            if selectedGitHubAccount?.username == username {
                selectedGitHubAccount = updatedAccount
            }
            
            return true
        }
        
        return false
    }

    // Get all active GitHub accounts (for fetching PRs from all accounts)
    func getAllActiveAccounts() -> [GitHubAccount] {
        let accounts = githubAccounts
        
        // If we have accounts, return all of them
        if !accounts.isEmpty {
            return accounts
        }
        
        // If we have a legacy token but no accounts, create a temporary account
        if let legacyToken = githubToken, !legacyToken.isEmpty {
            return [GitHubAccount(username: "Legacy Account", token: legacyToken)]
        }
        
        return []
    }

    // MARK: - Account Color Management
    
    // Store custom colors for accounts
    // Structure: [username: hexColorString]
    var accountColors: [String: String] {
        get {
            if let data = defaults.data(forKey: accountColorsKey),
               let colors = try? JSONDecoder().decode([String: String].self, from: data) {
                return colors
            }
            return [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: accountColorsKey)
                defaults.synchronize()
            }
        }
    }
    
    // Set a custom color for an account
    func setAccountColor(username: String, hexColor: String) {
        var colors = accountColors
        colors[username] = hexColor
        accountColors = colors
    }
    
    // Get a custom color for an account (if set)
    func getAccountColor(username: String) -> String? {
        return accountColors[username]
    }
    
    // Remove a custom color for an account
    func removeAccountColor(username: String) {
        var colors = accountColors
        colors.removeValue(forKey: username)
        accountColors = colors
    }
}
