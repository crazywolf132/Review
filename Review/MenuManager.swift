//
//  MenuManager.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import Cocoa
import LaunchAtLogin

class MenuManager: NSObject {
    let menu = NSMenu()
    private var pullRequests: [PullRequest] = []
    private var githubService: GitHubService?
    
    // Track the menu items with images being loaded
    private var imageLoadingMenuItems = Set<NSMenuItem>()
    
    // We'll rely on Kingfisher's built-in caching instead of our own
    // Image cache to prevent repeated downloads
    // private var imageCache = NSCache<NSString, NSImage>()
    
    // Status bar item to display PR counts
    private var statusItem: NSStatusItem?
    
    // For showing loading animation
    private var isLoading = true
    private var loadingTimer: Timer?

    // Add these properties near the top of the class (after other property declarations)
    private var refreshMenuItem: NSMenuItem {
        let item = NSMenuItem(title: "Refresh All", action: #selector(refreshAll), keyEquivalent: "r")
        item.target = self
        return item
    }

    private var settingsMenuItem: NSMenuItem {
        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: ",")
        return item
    }

    // Set the GitHub service for downloading images
    func setGitHubService(_ service: GitHubService) {
        self.githubService = service
    }
    
    // Set the status bar item
    func setStatusItem(_ item: NSStatusItem) {
        self.statusItem = item
        
        // Make sure the button is layer-backed for animations
        if let button = item.button {
            button.wantsLayer = true
        }
        
        updateStatusItemCount(self.pullRequests.count)
        
        // Start the loading animation
        startLoadingAnimation()
    }
    
    // Start loading animation in the status bar
    private func startLoadingAnimation() {
        isLoading = true
        
        // Create a timer that updates the animation frame every 0.3 seconds
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateLoadingAnimation()
        }
        
        // Ensure the animation starts immediately
        updateLoadingAnimation()
    }
    
    // Stop loading animation
    func stopLoadingAnimation() {
        isLoading = false
        loadingTimer?.invalidate()
        loadingTimer = nil
        
        // Reset the status item image
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Normal")
            
            // Update with count and 'PRs' text to match updateStatusItemCount style
            if !pullRequests.isEmpty {
                let count = pullRequests.count
                let countText = count > 99 ? "99+" : "\(count)"
                button.title = " \(countText) PRs"
            } else {
                button.title = ""
            }
        }
        
        // Also call updateStatusItemCount to ensure consistency
        updateStatusItemCount(pullRequests.count)
    }
    
    // Update the loading animation frame
    private func updateLoadingAnimation() {
        guard let button = statusItem?.button else { return }
        
        // Create a spinning arrow image
        if let image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise", accessibilityDescription: "Loading") {
            image.isTemplate = true  // Use template mode for proper tinting
            
            // Set the loading image and title
            button.image = image
            button.title = " Loading..."
            
            // Use Timer to animate the image with rotation
            if loadingTimer == nil {
                loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak button] _ in
                    guard let button = button else { return }
                    
                    // Create a rotated copy of the image
                    if let originalImage = button.image {
                        let rotationAngle = CACurrentMediaTime() * 5.0
                        let rotatedImage = originalImage.rotated(byRadians: CGFloat(rotationAngle))
                        button.image = rotatedImage
                    }
                }
            }
        }
    }
    
    // Update the status bar count display
    func updateStatusItemCount(_ count: Int) {
        guard let statusItem = self.statusItem else { return }
        
        // If still loading, don't update the count
        if isLoading {
            return
        }
        
        // Reset any animation state
        if let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Review PRs") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        
        // Only show count if there are PRs
        if count > 0 {
            let countText = count > 99 ? "99+" : "\(count)"
            statusItem.button?.title = " \(countText) PRs"
            
            // Ensure proper spacing between the image and text
            statusItem.button?.imagePosition = .imageLeft
            statusItem.button?.imageHugsTitle = true
        } else {
            // Show only icon when no PRs
            statusItem.button?.title = ""
        }
    }

    func updateMenu(with prs: [PullRequest]) {
        self.pullRequests = prs
        menu.removeAllItems()
        
        // Filter PRs based on archived repo setting
        let filteredPRs = SettingsManager.shared.showArchivedRepos 
            ? prs 
            : prs.filter { !$0.isInArchivedRepo }
        
        // Update status bar count
        updateStatusItemCount(filteredPRs.count)
        
        // Clear image loading tracking
        imageLoadingMenuItems.removeAll()
        
        if !SettingsManager.shared.isTokenValid() {
            let setTokenItem = NSMenuItem(title: "Set GitHub Token", action: #selector(setToken), keyEquivalent: "")
            setTokenItem.target = self
            menu.addItem(setTokenItem)
            
            let resetTokenItem = NSMenuItem(title: "Reset GitHub Token", action: #selector(resetToken), keyEquivalent: "")
            resetTokenItem.target = self
            menu.addItem(resetTokenItem)
            return
        }
        
        // If no PRs, show a message
        if filteredPRs.isEmpty {
            let noPRsItem = NSMenuItem(title: "No pull requests available", action: nil, keyEquivalent: "")
            noPRsItem.isEnabled = false
            menu.addItem(noPRsItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(refreshMenuItem)
            
            let settingsItem = settingsMenuItem
            menu.addItem(settingsItem)
            menu.setSubmenu(settingsSubMenu(), for: settingsItem)
            return
        }
        
        // Add groups submenu first
        let groupsItem = NSMenuItem(title: "Groups", action: nil, keyEquivalent: "")
        menu.addItem(groupsItem)
        menu.setSubmenu(groupsSubMenu(), for: groupsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Only display status groups that are visible
        let visibleStatuses = SettingsManager.shared.visibleStatusGroups
        
        // Prioritize categories in a more logical order
        let prioritizedStatuses: [PullRequest.Status] = [
            .needsReview,    // Highest priority - PRs that need the user's attention
            .waitingReview,  // PRs that are waiting for review
            .assigned,       // PRs assigned to the user
            .mentioned,      // PRs where the user is mentioned
            .yourPR,         // User's own PRs - clearly separated
            .approved        // Approved PRs - lowest priority
        ]
        
        // Filter statuses by visibility and ensure they exist in the prioritized list
        let displayOrder = prioritizedStatuses.filter { visibleStatuses.contains($0) }
        
        // Group PRs by status and display in order of priority
        for status in displayOrder {
            // Skip status groups that are hidden
            if !visibleStatuses.contains(status) {
                continue
            }
            
            let prsForStatus = filteredPRs.filter { $0.status == status }
            
            // Skip completely empty sections
            if prsForStatus.isEmpty {
                continue
            }
            
            // Create a visually distinct header for the status group
            let sectionTitle = NSMenuItem(title: "\(status.rawValue) (\(prsForStatus.count))", action: nil, keyEquivalent: "")
            sectionTitle.isEnabled = false
            sectionTitle.attributedTitle = attributedStatusTitle(status.rawValue, count: prsForStatus.count)
            menu.addItem(sectionTitle)

            // Add menu items for PRs in this status group
            for pr in prsForStatus {
                let titleComponents = [
                    SettingsManager.shared.displayPRNumber ? "#\(pr.number)" : nil,
                    SettingsManager.shared.displayPRTitle ? pr.title : nil,
                ].compactMap { $0 }.joined(separator: " - ")

                let prItem = NSMenuItem(
                    title: titleComponents,
                    action: #selector(openPR(_:)),
                    keyEquivalent: ""
                )
                // Ensure we're setting an individual PullRequest and not accidentally passing the array
                if let individualPR = prsForStatus.first(where: { $0.id == pr.id }) {
                    prItem.representedObject = individualPR
                } else {
                    prItem.representedObject = pr  // Fallback, should never happen
                }
                prItem.target = self
                
                // Apply consistent formatting to all menu items
                applyConsistentFormatting(to: prItem, with: pr)
                
                // Add PR actions submenu only when user can take actions
                // Don't add PR actions for user's own PRs
                if canTakeActionsOn(pr) {
                    let actionsMenu = NSMenu()
                    
                    // Add action items to the submenu
                    let approveItem = NSMenuItem(title: "Approve", action: #selector(approvePR(_:)), keyEquivalent: "")
                    approveItem.representedObject = pr
                    approveItem.target = self
                    actionsMenu.addItem(approveItem)
                    
                    let requestChangesItem = NSMenuItem(title: "Request Changes", action: #selector(requestChangesPR(_:)), keyEquivalent: "")
                    requestChangesItem.representedObject = pr
                    requestChangesItem.target = self
                    actionsMenu.addItem(requestChangesItem)
                    
                    let commentItem = NSMenuItem(title: "Comment", action: #selector(commentOnPR(_:)), keyEquivalent: "")
                    commentItem.representedObject = pr
                    commentItem.target = self
                    actionsMenu.addItem(commentItem)
                    
                    // Set the submenu
                    prItem.submenu = actionsMenu
                } else {
                    // For user's own PRs, still provide a submenu with copy options
                    let actionsMenu = NSMenu()
                    prItem.submenu = actionsMenu
                }
                
                // Add copy options to all PR items (regardless of whether they can take actions)
                if let submenu = prItem.submenu {
                    // Add separator if there are already items in the submenu
                    if submenu.items.count > 0 {
                        submenu.addItem(NSMenuItem.separator())
                    }
                    
                    // Add copy PR number option
                    let copyNumberItem = NSMenuItem(title: "Copy PR Number", action: #selector(copyPRNumber(_:)), keyEquivalent: "")
                    copyNumberItem.representedObject = pr
                    copyNumberItem.target = self
                    submenu.addItem(copyNumberItem)
                    
                    // Add copy PR URL option
                    let copyURLItem = NSMenuItem(title: "Copy PR URL", action: #selector(copyPRURL(_:)), keyEquivalent: "")
                    copyURLItem.representedObject = pr
                    copyURLItem.target = self
                    submenu.addItem(copyURLItem)
                }
                
                // Add a tooltip with status information
                prItem.toolTip = createStatusTooltip(for: pr)
                
                menu.addItem(prItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(refreshMenuItem)
        
        // Settings submenu
        let settingsItem = settingsMenuItem
        menu.addItem(settingsItem)
        menu.setSubmenu(settingsSubMenu(), for: settingsItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Add version at the bottom
        menu.addItem(NSMenuItem.separator())
        
        // Get app version information
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let versionItem = NSMenuItem(title: "Version \(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
    }
    
    // Create attributed string for status title to make it visually distinct
    private func attributedStatusTitle(_ title: String, count: Int) -> NSAttributedString {
        let titleText = "\(title) (\(count))"
        let attributedString = NSMutableAttributedString(string: titleText)
        
        let titleRange = NSRange(location: 0, length: titleText.count)
        let fontManager = NSFontManager.shared
        
        // Use a bold system font with slightly larger size for better visibility
        if let boldFont = fontManager.font(withFamily: NSFont.systemFont(ofSize: 14).familyName ?? "Helvetica", 
                                         traits: NSFontTraitMask.boldFontMask, 
                                         weight: 9, 
                                         size: 13) {
            attributedString.addAttribute(.font, value: boldFont, range: titleRange)
        }
        
        // Add a subtle background color to make the header stand out
        let backgroundColor: NSColor
        
        // Use colors based on the status title to help with visual categorization
        if title.contains("Needs Your Review") {
            backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1)
        } else if title.contains("Your Pull Requests") {
            backgroundColor = NSColor.systemPurple.withAlphaComponent(0.1)
        } else if title.contains("Approved") {
            backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1)
        } else {
            backgroundColor = NSColor.systemGray.withAlphaComponent(0.1)
        }
        
        attributedString.addAttribute(.backgroundColor, value: backgroundColor, range: titleRange)
        
        // Add padding with paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail
        // Reduce spacing to minimum
        paragraphStyle.headIndent = 5
        paragraphStyle.firstLineHeadIndent = 5
        paragraphStyle.tailIndent = -5
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.paragraphSpacingBefore = 4
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: titleRange)
        
        return attributedString
    }
    
    // Create a submenu to toggle visibility of status groups
    private func groupsSubMenu() -> NSMenu {
        let groupsMenu = NSMenu()
        
        // Add "Show All" option
        let showAllItem = NSMenuItem(title: "Show All Groups", action: #selector(showAllGroups), keyEquivalent: "")
        showAllItem.target = self
        groupsMenu.addItem(showAllItem)
        
        groupsMenu.addItem(NSMenuItem.separator())
        
        // Add toggle items for each status
        for status in PullRequest.Status.allCases {
            let isVisible = SettingsManager.shared.isStatusGroupVisible(status)
            let statusItem = NSMenuItem(title: status.rawValue, action: #selector(toggleStatusGroup(_:)), keyEquivalent: "")
            statusItem.state = isVisible ? .on : .off
            statusItem.representedObject = status
            statusItem.target = self
            groupsMenu.addItem(statusItem)
        }
        
        return groupsMenu
    }
    
    @objc private func showAllGroups() {
        // Make all status groups visible
        SettingsManager.shared.visibleStatusGroups = PullRequest.Status.allCases
        refreshAll()
    }
    
    @objc private func toggleStatusGroup(_ sender: NSMenuItem) {
        guard let status = sender.representedObject as? PullRequest.Status else { return }
        
        // Toggle visibility for this status group
        SettingsManager.shared.toggleStatusGroupVisibility(status)
        
        // Update the menu item state
        sender.state = SettingsManager.shared.isStatusGroupVisible(status) ? .on : .off
        
        // Refresh the menu to reflect changes
        refreshAll()
    }
    
    private func loadProfileImage(for menuItem: NSMenuItem, from imageURL: String) {
        // We'll rely on Kingfisher's caching entirely now
        // No need to check our own cache first, just request the image

        // Add this item to our tracking set before initiating the download
        imageLoadingMenuItems.insert(menuItem)
        
        // Let the GitHubService handle the download with Kingfisher's built-in caching
        githubService?.downloadProfileImage(from: imageURL) { [weak self] image in
            DispatchQueue.main.async {
                // Verify the menuItem is still being tracked for image loading
                guard let self = self, self.imageLoadingMenuItems.contains(menuItem) else { return }
                
                if let image = image {
                    // Set the author image
                    menuItem.image = image
                    
                    // Fix image alignment again after setting the real image
                    self.adjustMenuItemImageAlignment(menuItem)
                }
                
                // Remove from tracking set once loaded (success or failure)
                self.imageLoadingMenuItems.remove(menuItem)
            }
        }
    }
    
    // New method to apply consistent formatting to all menu items
    private func applyConsistentFormatting(to menuItem: NSMenuItem, with pr: PullRequest) {
        // First create a consistent attributed string for the title
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail
        // Reduce spacing to minimum
        paragraphStyle.headIndent = 0
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.tailIndent = 0
        paragraphStyle.paragraphSpacing = 0
        
        // Get repository name from URL for display
        let repoName = extractRepoNameFromURL(pr.url)
        
        // Create a more informative title that includes repository name
        var displayTitle = menuItem.title
        if SettingsManager.shared.displayRepoName, let repo = repoName, !menuItem.title.contains(repo) {
            // Add repository name in brackets if not already present
            displayTitle = "[\(repo)] \(menuItem.title)"
        }
        
        // Create clean, minimal attributed title without intrusive indicators
        let attributedTitle = NSMutableAttributedString(
            string: displayTitle,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .paragraphStyle: paragraphStyle
            ]
        )
        
        menuItem.attributedTitle = attributedTitle
        
        // Remove default indentation (helps with padding)
        menuItem.indentationLevel = 0
        
        // Only add profile picture if enabled in settings
        if SettingsManager.shared.displayUserIcon {
            // Add a placeholder image initially, but only if we haven't loaded this user's profile image before
            menuItem.image = NSImage(systemSymbolName: "person.circle", accessibilityDescription: "Author")
            
            // Load the profile image
            loadProfileImage(for: menuItem, from: pr.authorImageURL)
        }
        
        // Set a simple state indicator based on PR status - much more subtle
        if pr.hasMergeConflicts {
            menuItem.state = .mixed // Yellow dash for merge conflicts
        } else if pr.actionsStatus == .passing {
            menuItem.state = .on // Checkmark for passing
        } else if pr.actionsStatus == .failing {
            menuItem.state = .off // No symbol for failing (or use mixed)
        } else {
            menuItem.state = .off // Default off state
        }
    }
    
    // Extract repository name from PR URL
    private func extractRepoNameFromURL(_ url: String) -> String? {
        // Format is typically: https://github.com/owner/repo/pull/number
        let urlComponents = url.components(separatedBy: "/")
        
        guard urlComponents.count >= 5,
              urlComponents[urlComponents.count - 2] == "pull" else {
            return nil
        }
        
        if urlComponents.count >= 4 {
            let owner = urlComponents[urlComponents.count - 4]
            let repo = urlComponents[urlComponents.count - 3]
            return "\(owner)/\(repo)"
        }
        
        return nil
    }
    
    // Adjust menu item image alignment to remove excess left padding
    private func adjustMenuItemImageAlignment(_ menuItem: NSMenuItem) {
        // Use attributed title to control spacing if one doesn't exist yet
        if menuItem.attributedTitle == nil {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byTruncatingTail
            // Reduce spacing to minimum
            paragraphStyle.headIndent = 0
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.tailIndent = 0
            paragraphStyle.paragraphSpacing = 0
            
            let attributedTitle = NSAttributedString(
                string: menuItem.title,
                attributes: [
                    .paragraphStyle: paragraphStyle,
                    .font: NSFont.menuFont(ofSize: 0)
                ]
            )
            
            menuItem.attributedTitle = attributedTitle
        }
        
        // Remove default indentation (helps with padding)
        menuItem.indentationLevel = 0
    }

    private func settingsSubMenu() -> NSMenu {
        let settingsMenu = NSMenu()
        
        // Display options
        let displayHeader = NSMenuItem(title: "Display Options", action: nil, keyEquivalent: "")
        displayHeader.isEnabled = false
        settingsMenu.addItem(displayHeader)
        
        settingsMenu.addItem(menuToggleItem(title: "Show User Icons", key: \SettingsManager.displayUserIcon))
        settingsMenu.addItem(menuToggleItem(title: "Show PR Number", key: \SettingsManager.displayPRNumber))
        settingsMenu.addItem(menuToggleItem(title: "Show PR Title", key: \SettingsManager.displayPRTitle))
        settingsMenu.addItem(menuToggleItem(title: "Show Repository Name", key: \SettingsManager.displayRepoName))
        settingsMenu.addItem(menuToggleItem(title: "Show PRs from Archived Repos", key: \SettingsManager.showArchivedRepos))
        
        settingsMenu.addItem(NSMenuItem.separator())
        
        // General app settings
        let generalHeader = NSMenuItem(title: "General Settings", action: nil, keyEquivalent: "")
        generalHeader.isEnabled = false
        settingsMenu.addItem(generalHeader)
        
        // Add refresh interval submenu
        let refreshIntervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        settingsMenu.addItem(refreshIntervalItem)
        settingsMenu.setSubmenu(refreshIntervalSubMenu(), for: refreshIntervalItem)
        
        // Add launch at login toggle
        settingsMenu.addItem(menuToggleItem(title: "Launch at Login", key: \SettingsManager.launchAtLogin))
        
        return settingsMenu
    }

    private func menuToggleItem(title: String, key: ReferenceWritableKeyPath<SettingsManager, Bool>) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
        item.state = SettingsManager.shared[keyPath: key] ? .on : .off
        item.representedObject = key
        item.target = self
        return item
    }

    @objc private func toggleSetting(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? ReferenceWritableKeyPath<SettingsManager, Bool> else { return }
        SettingsManager.shared[keyPath: key].toggle()
        sender.state = SettingsManager.shared[keyPath: key] ? .on : .off
        
        // If toggling display settings that affect menu presentation, refresh
        if key == \SettingsManager.displayUserIcon || 
           key == \SettingsManager.displayPRNumber || 
           key == \SettingsManager.displayPRTitle || 
           key == \SettingsManager.displayRepoName ||
           key == \SettingsManager.showArchivedRepos {
            refreshAll()
        }
    }

    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        
        // Update the setting
        SettingsManager.shared.refreshIntervalSeconds = seconds
        
        // Notify that the refresh interval has changed
        NotificationCenter.default.post(name: Notification.Name("RefreshIntervalChanged"), object: nil)
        
        // Update menu states (this will rebuild the entire menu)
        refreshAll()
    }

    @objc private func setToken() {
        let alert = NSAlert()
        alert.messageText = "Enter GitHub Token"
        alert.informativeText = "Please enter a valid GitHub personal access token to access your pull requests."
        
        let input = NSTextField(string: SettingsManager.shared.githubToken ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        input.placeholderString = "ghp_xxxxxxxxxxxxxxxxxxxx"
        alert.accessoryView = input
        
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let newToken = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            SettingsManager.shared.githubToken = newToken
            
            // Force a refresh
            refreshAll()
        }
    }
    
    @objc private func resetToken() {
        SettingsManager.shared.resetToken()
        refreshAll()
    }

    @objc private func openPR(_ sender: NSMenuItem) {
        // Add extra type checking to prevent crashes
        let representedObj = sender.representedObject
        
        // Check for array type which would cause a crash
        if representedObj is [Any] {
            print("ERROR: Received an array instead of a PullRequest object")
            return
        }
        
        if let pr = representedObj as? PullRequest {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            } else {
                print("ERROR: Invalid URL in PullRequest: \(pr.url)")
            }
        } else {
            print("ERROR: Unexpected object type for representedObject: \(type(of: representedObj))")
        }
    }

    @objc private func refreshAll() {
        NotificationCenter.default.post(
            name: Notification.Name("RefreshAllPRs"),
            object: nil,
            userInfo: nil
        )
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // Called when token is missing
    func showTokenMissingAlert() {
        // Show alert
        let alert = NSAlert()
        alert.messageText = "GitHub Token Required"
        alert.informativeText = "A valid GitHub personal access token is required to see your pull requests."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Set Token")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            self.setToken()
        }
        
        // Update menu
        menu.removeAllItems()
        
        let missingTokenItem = NSMenuItem(title: "GitHub Token Missing!", action: #selector(setToken), keyEquivalent: "")
        missingTokenItem.target = self
        menu.addItem(missingTokenItem)
        
        let explanation = NSMenuItem(title: "Click to set up your GitHub token", action: nil, keyEquivalent: "")
        explanation.isEnabled = false
        menu.addItem(explanation)
        
        menu.addItem(NSMenuItem.separator())
        
        let resetTokenItem = NSMenuItem(title: "Reset Token", action: #selector(resetToken), keyEquivalent: "")
        resetTokenItem.target = self
        menu.addItem(resetTokenItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - PR Actions
    
    @objc private func approvePR(_ sender: NSMenuItem) {
        performPRAction(sender, action: .approve)
    }
    
    @objc private func requestChangesPR(_ sender: NSMenuItem) {
        performPRAction(sender, action: .requestChanges, requiresComment: true)
    }
    
    @objc private func commentOnPR(_ sender: NSMenuItem) {
        performPRAction(sender, action: .comment, requiresComment: true)
    }
    
    private func performPRAction(_ sender: NSMenuItem, action: PRAction, requiresComment: Bool = false) {
        guard let pr = sender.representedObject as? PullRequest else {
            print("ERROR: No pull request found")
            return
        }
        
        // Extract repo information from PR URL
        guard let repoInfo = githubService?.extractRepoInfo(from: pr.url) else {
            displayErrorAlert(title: "Invalid PR URL", message: "Could not determine repository information")
            return
        }
        
        var comment: String? = nil
        
        // If we require a comment, show a comment input dialog
        if requiresComment {
            let alert = NSAlert()
            alert.messageText = "\(action.displayName) PR #\(pr.number)"
            alert.informativeText = "Enter your comment:"
            
            let commentField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            commentField.isEditable = true
            commentField.placeholderString = "Your comment here..."
            commentField.textColor = NSColor.textColor
            
            // Make it a multi-line text field
            commentField.cell?.isScrollable = true
            commentField.cell?.wraps = true
            
            alert.accessoryView = commentField
            alert.addButton(withTitle: "Submit")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                comment = commentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Validate that a comment is provided if required
                if comment?.isEmpty == true {
                    displayErrorAlert(title: "Comment Required", message: "A comment is required for this action")
                    return
                }
            } else {
                // User canceled
                return
            }
        }
        
        // Show loading state
        startLoadingAnimation()
        
        // Call the GitHub API
        githubService?.submitPRReview(
            owner: repoInfo.owner,
            repo: repoInfo.repo,
            prNumber: repoInfo.number,
            action: action,
            comment: comment
        ) { [weak self] success, errorMessage in
            DispatchQueue.main.async {
                self?.stopLoadingAnimation()
                
                if success {
                    // Show success alert
                    let alert = NSAlert()
                    alert.messageText = "Success!"
                    alert.informativeText = "Your \(action.displayName.lowercased()) has been submitted."
                    alert.alertStyle = .informational
                    alert.runModal()
                    
                    // Refresh the PR list
                    self?.refreshAll()
                } else {
                    // Show error alert
                    self?.displayErrorAlert(
                        title: "Action Failed",
                        message: errorMessage ?? "An unknown error occurred"
                    )
                }
            }
        }
    }
    
    private func displayErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }

    // Create a submenu for refresh interval options
    private func refreshIntervalSubMenu() -> NSMenu {
        let refreshMenu = NSMenu()
        
        // Current interval (informational item)
        let currentInterval = NSMenuItem(title: "Current: \(SettingsManager.shared.refreshIntervalDescription())", action: nil, keyEquivalent: "")
        currentInterval.isEnabled = false
        refreshMenu.addItem(currentInterval)
        
        refreshMenu.addItem(NSMenuItem.separator())
        
        // Add common interval options
        let intervalOptions: [(String, TimeInterval)] = [
            ("1 minute", 60),
            ("5 minutes", 300),
            ("10 minutes", 600),
            ("15 minutes", 900),
            ("30 minutes", 1800),
            ("1 hour", 3600)
        ]
        
        for (title, seconds) in intervalOptions {
            let item = NSMenuItem(title: title, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.representedObject = seconds
            item.target = self
            
            // Mark the current interval
            if abs(SettingsManager.shared.refreshIntervalSeconds - seconds) < 1 {
                item.state = .on
            }
            
            refreshMenu.addItem(item)
        }
        
        return refreshMenu
    }

    // Create a tooltip with status information
    private func createStatusTooltip(for pr: PullRequest) -> String {
        var tooltipLines = [String]()
        
        // Add repository name if available
        if let repoName = extractRepoNameFromURL(pr.url) {
            tooltipLines.append("Repository: \(repoName)")
        }
        
        // Add title line
        tooltipLines.append("PR #\(pr.number): \(pr.title)")
        tooltipLines.append("Author: \(pr.author)")
        
        // Add PR status
        tooltipLines.append("Status: \(pr.status.rawValue)")
        
        // Add CI status
        switch pr.actionsStatus {
        case .passing:
            tooltipLines.append("✅ CI Checks: Passing")
        case .failing:
            tooltipLines.append("❌ CI Checks: Failing")
        case .running:
            tooltipLines.append("🔄 CI Checks: Running")
        case .unknown:
            tooltipLines.append("ℹ️ CI Checks: Unknown")
        }
        
        // Add merge status
        if pr.hasMergeConflicts {
            tooltipLines.append("⚠️ Merge Conflicts: Yes")
        } else {
            tooltipLines.append("✓ Merge Conflicts: None")
        }
        
        return tooltipLines.joined(separator: "\n")
    }

    // Helper method to determine if user can take actions on a PR
    private func canTakeActionsOn(_ pr: PullRequest) -> Bool {
        // User can only take actions on PRs that need review
        // Based on the available Status enum values
        let isActionable = pr.status == .needsReview || pr.status == .waitingReview
        
        // Don't show action menu for user's own PRs
        let isOwnPR = pr.status == .yourPR
        
        // Return true only if actionable and not own PR
        return isActionable && !isOwnPR
    }

    // Add this function near the other menu-related functions
    private func statusVisibilityMenuItem(for status: PullRequest.Status) -> NSMenuItem {
        let isVisible = SettingsManager.shared.isStatusGroupVisible(status)
        let statusItem = NSMenuItem(title: status.rawValue, action: #selector(toggleStatusGroup(_:)), keyEquivalent: "")
        statusItem.state = isVisible ? .on : .off
        statusItem.representedObject = status
        statusItem.target = self
        return statusItem
    }
    
    @objc private func copyPRNumber(_ sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PullRequest else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(pr.number)", forType: .string)
    }
    
    @objc private func copyPRURL(_ sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PullRequest else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url, forType: .string)
    }
}

// Add an extension to NSImage for rotation
extension NSImage {
    func rotated(byRadians radians: CGFloat) -> NSImage {
        let size = self.size
        let newImage = NSImage(size: size)
        
        newImage.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byRadians: radians)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()
        
        self.draw(in: NSRect(origin: .zero, size: size))
        
        newImage.unlockFocus()
        newImage.isTemplate = self.isTemplate
        return newImage
    }
}
