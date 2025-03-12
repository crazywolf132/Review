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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Print all UserDefaults for debugging
        print("DEBUG: All UserDefaults keys: \(Array(UserDefaults.standard.dictionaryRepresentation().keys))")
        
        setupStatusBar()
        validateAndFetchPRs()
        setupAutoRefresh()
        
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
        
        print("DEBUG: Token validation passed, initializing GitHub service")
        githubService = GitHubService(token: settingsManager.githubToken!)
        
        // Pass the GitHub service to the menu manager for image downloading
        menuManager.setGitHubService(githubService!)
        
        fetchPullRequests()
    }
    
    @objc private func refreshPRs() {
        validateAndFetchPRs()
    }
    
    @objc private func refreshSinglePR(_ notification: Notification) {
        guard let prNumber = notification.userInfo?["pullRequestNumber"] as? Int,
              let token = settingsManager.githubToken,
              settingsManager.isTokenValid() else {
            return
        }
        
        print("DEBUG: Refreshing PR #\(prNumber)")
        
        // If GitHub service is not initialized, initialize it
        if githubService == nil {
            githubService = GitHubService(token: token)
            menuManager.setGitHubService(githubService!)
        }
        
        // Fetch the specific PR and update the menu
        // For now, we'll just refresh all PRs since the API doesn't support fetching a single PR easily
        // This is a reasonable compromise
        fetchPullRequests()
    }

    private func fetchPullRequests() {
        githubService?.fetchPullRequests { [weak self] prs in
            DispatchQueue.main.async {
                print("DEBUG: Fetched \(prs.count) pull requests")
                self?.menuManager.updateMenu(with: prs)
                
                // Stop the loading animation after PRs are loaded
                self?.menuManager.stopLoadingAnimation()
            }
        }
    }

    private func setupAutoRefresh() {
        setupRefreshTimer()
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
        
        refreshTimer = Timer.scheduledTimer(
            timeInterval: refreshInterval,
            target: self,
            selector: #selector(refreshPRs),
            userInfo: nil,
            repeats: true
        )
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
