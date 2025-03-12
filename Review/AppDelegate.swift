//
//  AppDelegate.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    private let menuManager = MenuManager()
    private let settingsManager = SettingsManager.shared
    private var githubService: GitHubService?
    private var refreshTimer: Timer?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app is properly hidden from dock and app switcher
        NSApp.setActivationPolicy(.accessory)
        
        // Print all UserDefaults for debugging
        print("DEBUG: All UserDefaults keys: \(Array(UserDefaults.standard.dictionaryRepresentation().keys))")
        
        setupStatusBar()
        validateAndFetchPRs()
        
        // Set up notification to refresh PRs when requested
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPRs),
            name: Notification.Name("RefreshAllPRs"),
            object: nil
        )
        
        // Set up notification to refresh a single PR
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshSinglePR(_:)),
            name: Notification.Name("RefreshSinglePR"),
            object: nil
        )
        
        // Listen for GitHub account changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccountChange),
            name: Notification.Name("GitHubAccountChanged"),
            object: nil
        )
        
        // Set up a refresh timer using the user's preferred interval
        setupRefreshTimer()
        
        // Also listen for changes to refresh interval
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateRefreshTimer),
            name: Notification.Name("RefreshIntervalChanged"),
            object: nil
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Make sure we save any pending changes to UserDefaults
        UserDefaults.standard.synchronize()
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Review PRs")
        statusBarItem.menu = menuManager.menu
        
        // Pass the status item to the menu manager for count display
        menuManager.setStatusItem(statusBarItem)
    }

    private func validateAndFetchPRs() {
        print("DEBUG: Validating GitHub token...")
        
        if !settingsManager.isTokenValid() {
            print("DEBUG: Token validation failed, showing missing token alert")
            menuManager.showTokenMissingAlert()
            return
        }
        
        // Get all accounts (not just enabled) to check if any are available
        let allAccounts = settingsManager.getAllActiveAccounts()
        if allAccounts.isEmpty {
            print("DEBUG: No valid accounts found")
            menuManager.showTokenMissingAlert()
            return
        }
        
        // Get enabled accounts to check if any are enabled
        let enabledAccounts = settingsManager.getEnabledActiveAccounts()
        print("DEBUG: Token validation passed, \(enabledAccounts.count) of \(allAccounts.count) accounts enabled")
        
        // Initialize GitHub service for the menu manager with the first account's token
        // (this is just for image downloading functionality)
        githubService = GitHubService(token: allAccounts[0].token)
        menuManager.setGitHubService(githubService!)
        
        fetchPullRequests()
    }
    
    @objc private func refreshPRs() {
        validateAndFetchPRs()
    }
    
    @objc private func handleAccountChange() {
        print("DEBUG: GitHub account changed, refreshing")
        validateAndFetchPRs()
    }
    
    @objc private func refreshSinglePR(_ notification: Notification) {
        guard let prNumber = notification.userInfo?["pullRequestNumber"] as? Int,
              settingsManager.isTokenValid() else {
            return
        }
        
        print("DEBUG: Refreshing PR #\(prNumber)")
        
        // Get all accounts (not just enabled) to initialize the GitHub service
        let allAccounts = settingsManager.getAllActiveAccounts()
        if allAccounts.isEmpty {
            return
        }
        
        // Initialize GitHub service with the first account's token
        githubService = GitHubService(token: allAccounts[0].token)
        menuManager.setGitHubService(githubService!)
        
        // For now, we'll just refresh all PRs since refreshing a single PR across accounts is complex
        fetchPullRequests()
    }

    private func fetchPullRequests() {
        // Prevent concurrent fetches
        guard !isRefreshing else {
            print("DEBUG: Already refreshing, skipping this request")
            return
        }
        
        isRefreshing = true
        menuManager.startLoadingAnimation()
        
        // Get only enabled active accounts
        let accounts = settingsManager.getEnabledActiveAccounts()
        
        if accounts.isEmpty {
            print("DEBUG: No enabled accounts found")
            menuManager.stopLoadingAnimation()
            menuManager.updateMenu(with: [])
            isRefreshing = false
            return
        }
        
        print("DEBUG: Fetching PRs from \(accounts.count) enabled accounts")
        
        // Create a dispatch group to wait for all fetches to complete
        let group = DispatchGroup()
        var allPullRequests: [PullRequest] = []
        
        // Fetch PRs for each account
        for account in accounts {
            group.enter()
            print("DEBUG: Fetching PRs for account: \(account.username)")
            
            let service = GitHubService(token: account.token)
            service.fetchPullRequests { prs in
                // Add account name to each PR
                var accountPRs = prs
                for i in 0..<accountPRs.count {
                    accountPRs[i].accountName = account.username
                }
                
                // Add to the combined list
                allPullRequests.append(contentsOf: accountPRs)
                group.leave()
            }
        }
        
        // When all fetches are complete, update the menu
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            print("DEBUG: Fetched \(allPullRequests.count) pull requests from \(accounts.count) accounts")
            self.menuManager.updateMenu(with: allPullRequests)
            
            // Stop the loading animation after PRs are loaded
            self.menuManager.stopLoadingAnimation()
            self.isRefreshing = false
        }
    }
    
    @objc private func updateRefreshTimer() {
        // Invalidate existing timer
        refreshTimer?.invalidate()
        
        // Create a new timer with updated interval
        setupRefreshTimer()
    }
    
    private func setupRefreshTimer() {
        // Get the refresh interval from settings (in seconds)
        let refreshInterval = settingsManager.refreshIntervalSeconds
        
        print("DEBUG: Setting up refresh timer with interval: \(refreshInterval) seconds")
        
        // Make sure to create the timer on the main run loop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Use a common run loop mode that works even when menu is open
            self.refreshTimer = Timer(
                timeInterval: refreshInterval,
                target: self,
                selector: #selector(self.timerFired),
                userInfo: nil,
                repeats: true
            )
            
            if let refreshTimer = self.refreshTimer {
                RunLoop.main.add(refreshTimer, forMode: .common)
            }
        }
    }
    
    @objc private func timerFired() {
        print("DEBUG: Timer fired for auto-refresh")
        if !isRefreshing {
            refreshPRs()
        } else {
            print("DEBUG: Skipping auto-refresh because manual refresh is in progress")
        }
    }

    @objc private func refreshAll() {
        print("DEBUG: Menu requesting PR refresh")
        NotificationCenter.default.post(
            name: Notification.Name("RefreshAllPRs"),
            object: nil,
            userInfo: nil
        )
    }
}
