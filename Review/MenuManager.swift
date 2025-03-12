//
//  MenuManager.swift
//  Review
//
//  Created by Brayden Moon on 28/2/2025.
//

import Cocoa
import LaunchAtLogin

class MenuManager: NSObject, NSWindowDelegate {
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
    
    // For color panel editing
    private var currentEditingUsername: String?
    
    // Constants for consistent UI sizing
    private struct UIConstants {
        static let profileImageSize = CGSize(width: 24, height: 24)
        static let accountColorIndicatorSize = CGSize(width: 14, height: 14)
    }

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
    
    override init() {
        super.init()
        
        // Register to receive window closing notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Handle window closing notifications
    @objc func windowWillClose(_ notification: Notification) {
        // If the color panel is closed, clear the username being edited
        if notification.object as? NSColorPanel != nil {
            currentEditingUsername = nil
        }
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
            
            // Add a tooltip that will show account information
            updateStatusItemTooltip()
        }
        
        updateStatusItemCount(self.pullRequests.count)
        
        // Start the loading animation
        startLoadingAnimation()
    }
    
    // Start loading animation in the status bar
    @objc func startLoadingAnimation() {
        isLoading = true
        
        // Create a timer that updates the animation frame - slowed down from 0.3 to 0.8 seconds
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateLoadingAnimation()
        }
        
        // Ensure the animation starts immediately
        updateLoadingAnimation()
    }
    
    // Stop loading animation
    func stopLoadingAnimation() {
        // Set isLoading to false first to prevent race conditions
        isLoading = false
        
        // Invalidate and clear the timer
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
        guard isLoading, let button = statusItem?.button else { return }
        
        // Create a spinning arrow image
        if let image = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise", accessibilityDescription: "Loading") {
            image.isTemplate = true  // Use template mode for proper tinting
            
            // Set the loading image and title
            button.image = image
            button.title = " Loading..."
            
            // Rotate the image - simplified rotation approach that's less CPU intensive
            // and slowed down from 0.05 to 0.1 seconds
            if loadingTimer?.timeInterval != 0.8 {
                loadingTimer?.invalidate()
                loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak button] _ in
                    guard let button = button, let originalImage = button.image else { return }
                    
                    // Create a rotated copy of the image - slowed down rotation speed
                    let rotationAngle = CACurrentMediaTime() * 2.0
                    let rotatedImage = originalImage.rotated(byRadians: CGFloat(rotationAngle))
                    button.image = rotatedImage
                }
                
                if let timer = loadingTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        }
    }
    
    // Update the tooltip for the status item to show account information
    private func updateStatusItemTooltip() {
        guard let button = statusItem?.button else { return }
        
        let accounts = SettingsManager.shared.githubAccounts
        let enabledAccounts = SettingsManager.shared.enabledGitHubAccounts
        
        if accounts.isEmpty {
            button.toolTip = "Review - No GitHub accounts configured"
            return
        }
        
        if accounts.count == 1 {
            button.toolTip = "Review - Showing PRs for \(accounts[0].username)"
            return
        }
        
        // Multiple accounts
        var tooltipLines = ["Review - GitHub Pull Requests"]
        
        if enabledAccounts.count == accounts.count {
            tooltipLines.append("Showing PRs from all \(accounts.count) accounts")
        } else {
            tooltipLines.append("Showing PRs from \(enabledAccounts.count) of \(accounts.count) accounts")
            tooltipLines.append("")
            tooltipLines.append("Enabled accounts:")
            
            // List all enabled accounts
            for accountName in enabledAccounts {
                tooltipLines.append("• \(accountName)")
            }
        }
        
        button.toolTip = tooltipLines.joined(separator: "\n")
    }
    
    // Update the status bar count display
    func updateStatusItemCount(_ count: Int) {
        guard let statusItem = self.statusItem else { return }
        
        // If still loading, don't update the count
        if isLoading {
            return
        }
        
        // Update the tooltip with current account information
        updateStatusItemTooltip()
        
        // Reset any animation state
        if let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Review PRs") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        
        // Get enabled account count information
        let accounts = SettingsManager.shared.githubAccounts
        let enabledAccounts = SettingsManager.shared.enabledGitHubAccounts
        
        // Create the status bar text
        let countText = count > 99 ? "99+" : "\(count)"
        var statusText = " \(countText) PRs"
        
        // Add account indicator if multiple accounts exist and not all are enabled
        if accounts.count > 1 && enabledAccounts.count != accounts.count && enabledAccounts.count > 0 {
            statusText += " [\(enabledAccounts.count)/\(accounts.count)]"
        }
        
        // Only show count if there are PRs
        if count > 0 {
            statusItem.button?.title = statusText
            
            // Ensure proper spacing between the image and text
            statusItem.button?.imagePosition = .imageLeft
            statusItem.button?.imageHugsTitle = true
        } else {
            // Show only icon when no PRs, unless we're showing filtered accounts
            if accounts.count > 1 && enabledAccounts.count != accounts.count && enabledAccounts.count > 0 {
                statusItem.button?.title = " [filtered]"
            } else {
                statusItem.button?.title = ""
            }
        }
    }

    func updateMenu(with prs: [PullRequest]) {
        self.pullRequests = prs
        menu.removeAllItems()
        
        // Filter PRs based on archived repo setting
        let filteredPRs = SettingsManager.shared.showArchivedRepos 
            ? prs 
            : prs.filter { !$0.isInArchivedRepo }
        
        // Make sure to stop the loading animation before updating the status
        if isLoading {
            stopLoadingAnimation()
        }
        
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
            .draftPR,        // User's draft PRs
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
                // Create a simple base title that will be styled by applyConsistentFormatting
                let prItem = NSMenuItem(
                    title: pr.title,  // This will be replaced by our formatted version
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
                    
                    // If it's a draft PR, add option to mark as ready for review
                    if pr.isDraft && (pr.status == .yourPR || pr.status == .draftPR) {
                        let markReadyItem = NSMenuItem(title: "Mark as Ready for Review", action: #selector(markPRReady(_:)), keyEquivalent: "")
                        markReadyItem.representedObject = pr
                        markReadyItem.target = self
                        actionsMenu.addItem(markReadyItem)
                    }
                    
                    // Add option to close PR if it's the user's own PR
                    if pr.status == .yourPR || pr.status == .draftPR {
                        let closeItem = NSMenuItem(title: "Close Pull Request", action: #selector(closePR(_:)), keyEquivalent: "")
                        closeItem.representedObject = pr
                        closeItem.target = self
                        actionsMenu.addItem(closeItem)
                    }
                    
                    prItem.submenu = actionsMenu
                } else {
                    // For user's own PRs, provide a submenu with appropriate actions
                    let actionsMenu = NSMenu()
                    
                    // If it's a draft PR, add option to mark as ready for review
                    if pr.isDraft && (pr.status == .yourPR || pr.status == .draftPR) {
                        let markReadyItem = NSMenuItem(title: "Mark as Ready for Review", action: #selector(markPRReady(_:)), keyEquivalent: "")
                        markReadyItem.representedObject = pr
                        markReadyItem.target = self
                        actionsMenu.addItem(markReadyItem)
                    }
                    
                    // Add option to close PR if it's the user's own PR
                    if pr.status == .yourPR || pr.status == .draftPR {
                        let closeItem = NSMenuItem(title: "Close Pull Request", action: #selector(closePR(_:)), keyEquivalent: "")
                        closeItem.representedObject = pr
                        closeItem.target = self
                        actionsMenu.addItem(closeItem)
                    }
                    
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
        // Skip loading if the URL is empty
        guard !imageURL.isEmpty else { return }
        
        // Add this item to our tracking set before initiating the download
        imageLoadingMenuItems.insert(menuItem)
        
        // Set a proper placeholder with correct sizing
        if menuItem.image == nil {
            let placeholderImage = NSImage(systemSymbolName: "person.circle", accessibilityDescription: "Author")
            
            // Resize placeholder to match our desired dimensions
            let resizedPlaceholder = placeholderImage?.resizedForMenuItemHeight(UIConstants.profileImageSize.height)
            menuItem.image = resizedPlaceholder
            
            // Fix image alignment to ensure consistent spacing
            adjustMenuItemImageAlignment(menuItem)
        }
        
        // Let the GitHubService handle the download with Kingfisher's built-in caching
        githubService?.downloadProfileImage(from: imageURL) { [weak self] image in
            DispatchQueue.main.async {
                // Verify the menuItem is still being tracked for image loading
                guard let self = self, self.imageLoadingMenuItems.contains(menuItem) else { return }
                
                if let image = image {
                    // Set the author image and ensure proper sizing for menu item
                    // The image from Kingfisher already has proper sizing from the processor
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
        
        // Build the PR line item according to format: {ICON} [{Account username}] [{org}/{repo}] #{number} - {title}
        // Components will be built based on user's display preferences
        var titleComponents = [String]()
        
        // Account name - if enabled and available
        let hasMultipleAccounts = SettingsManager.shared.githubAccounts.count > 1
        if SettingsManager.shared.displayAccountName && 
           !pr.accountName.isEmpty && 
           pr.accountName != "Legacy Account" &&
           hasMultipleAccounts {
            titleComponents.append("[\(pr.accountName)]")
        }
        
        // Repository name - if enabled and available
        if SettingsManager.shared.displayRepoName, let repo = repoName {
            titleComponents.append("[\(repo)]")
        }
        
        // PR number - if enabled
        if SettingsManager.shared.displayPRNumber {
            titleComponents.append("#\(pr.number)")
        }
        
        // PR title - if enabled
        if SettingsManager.shared.displayPRTitle {
            titleComponents.append(pr.title)
        }
        
        // Combine all components with proper spacing
        let displayTitle = titleComponents.joined(separator: " ")
        
        // Base attributes for the title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .paragraphStyle: paragraphStyle
        ]
        
        // Create an attributed string with colored account name if applicable
        if SettingsManager.shared.displayAccountName && 
           !pr.accountName.isEmpty && 
           pr.accountName != "Legacy Account" &&
           hasMultipleAccounts {
            let attributedTitle = NSMutableAttributedString(string: displayTitle)
            
            // Color the account name portion
            if let accountRange = displayTitle.range(of: "[\(pr.accountName)]") {
                let nsRange = NSRange(accountRange, in: displayTitle)
                let accountColor = colorForAccountName(username: pr.accountName)
                attributedTitle.addAttribute(.foregroundColor, value: accountColor, range: nsRange)
            }
            
            // Apply base attributes to the entire string
            attributedTitle.addAttributes(titleAttributes, range: NSRange(location: 0, length: displayTitle.count))
            
            menuItem.attributedTitle = attributedTitle
        } else {
            // Simple attributed string without account coloring
            menuItem.attributedTitle = NSAttributedString(
                string: displayTitle,
                attributes: titleAttributes
            )
        }
        
        // Remove default indentation (helps with padding)
        menuItem.indentationLevel = 0
        
        // Only add profile picture if enabled in settings
        if SettingsManager.shared.displayUserIcon {
            // Make sure we're using a consistent image size
            // We don't set the placeholder here as loadProfileImage handles it
            // to avoid duplicate image assignments
            
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
    
    // Generate a consistent color for an account name
    private func colorForAccountName(username: String) -> NSColor {
        // First check if user has set a custom color for this account
        if let hexColor = SettingsManager.shared.getAccountColor(username: username), let color = NSColor.fromHexString(hexColor) {
            return color
        }
        
        // Fall back to auto-generated color if no custom color is set
        let hash = username.hash
        
        // Use the hash to generate color components
        let hue = CGFloat(abs(hash % 100)) / 100.0
        let saturation: CGFloat = 0.6  // Medium saturation for visibility without being too bright
        let brightness: CGFloat = 0.8  // Fairly bright but not full brightness
        
        // Create a color from HSB components
        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
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
        
        // Add all display toggle items
        let userIconItem = menuToggleItem(title: "Show User Icons", key: \SettingsManager.displayUserIcon)
        settingsMenu.addItem(userIconItem)
        
        let prNumberItem = menuToggleItem(title: "Show PR Number", key: \SettingsManager.displayPRNumber)
        settingsMenu.addItem(prNumberItem)
        
        let prTitleItem = menuToggleItem(title: "Show PR Title", key: \SettingsManager.displayPRTitle)
        settingsMenu.addItem(prTitleItem)
        
        let repoNameItem = menuToggleItem(title: "Show Repository Name", key: \SettingsManager.displayRepoName)
        settingsMenu.addItem(repoNameItem)
        
        // This is the item that keeps disappearing - add it differently
        let accountNameItem = menuToggleItem(title: "Show Account Name", key: \SettingsManager.displayAccountName)
        settingsMenu.addItem(accountNameItem)
        
        let archivedReposItem = menuToggleItem(title: "Show PRs from Archived Repos", key: \SettingsManager.showArchivedRepos)
        settingsMenu.addItem(archivedReposItem)
        
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
        
        // Add GitHub account management section
        settingsMenu.addItem(NSMenuItem.separator())
        
        // Accounts submenu
        let accountsItem = NSMenuItem(title: "GitHub Accounts", action: nil, keyEquivalent: "")
        let accountsMenu = NSMenu()
        accountsItem.submenu = accountsMenu
        
        // Add account
        let addAccountItem = NSMenuItem(title: "Add GitHub Account...", action: #selector(addGitHubAccount), keyEquivalent: "")
        addAccountItem.target = self
        accountsMenu.addItem(addAccountItem)
        
        // Only show management options if we have accounts
        let accounts = SettingsManager.shared.githubAccounts
        if !accounts.isEmpty {
            accountsMenu.addItem(NSMenuItem.separator())
            
            // Show all accounts with management options
            for account in accounts {
                // Create the account menu item
                let accountItem = NSMenuItem(title: account.username, action: nil, keyEquivalent: "")
                
                // Use the accountActionSubmenu method to create account submenu
                accountItem.submenu = accountActionSubmenu(for: account.username)
                
                // Show a color indicator next to the menu item
                let accountColor = colorForAccountName(username: account.username)
                let colorImage = NSImage.coloredSquare(color: accountColor, size: UIConstants.accountColorIndicatorSize)
                accountItem.image = colorImage
                
                // All accounts are active now (no selected account concept)
                accountItem.state = .on
                
                accountsMenu.addItem(accountItem)
            }
        }
        
        settingsMenu.addItem(accountsItem)
        
        // Add "Visible Accounts" submenu to control which accounts to show PRs from
        if accounts.count > 1 {
            let visibleAccountsItem = NSMenuItem(title: "Visible Accounts", action: nil, keyEquivalent: "")
            settingsMenu.addItem(visibleAccountsItem)
            settingsMenu.setSubmenu(visibleAccountsSubMenu(), for: visibleAccountsItem)
        }
        
        // Legacy token items - keep for backward compatibility
        if !SettingsManager.shared.isTokenValid() {
            let setTokenItem = NSMenuItem(title: "Set GitHub Token", action: #selector(setToken), keyEquivalent: "")
            setTokenItem.target = self
            settingsMenu.addItem(setTokenItem)
            
            let resetTokenItem = NSMenuItem(title: "Reset GitHub Token", action: #selector(resetToken), keyEquivalent: "")
            resetTokenItem.target = self
            settingsMenu.addItem(resetTokenItem)
        }
        
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
           key == \SettingsManager.displayAccountName ||
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
        alert.alertStyle = .informational
        alert.messageText = "Enter GitHub Token"
        alert.informativeText = "Please enter a valid GitHub personal access token to access your pull requests."
        
        // Update to suggest using the accounts system
        let infoLabel = NSTextField(frame: NSRect(x: 0, y: 40, width: 300, height: 40))
        infoLabel.stringValue = "Note: You can manage multiple accounts by using the GitHub Accounts option in the settings menu."
        infoLabel.isEditable = false
        infoLabel.isBezeled = false
        infoLabel.drawsBackground = false
        infoLabel.textColor = NSColor.secondaryLabelColor
        infoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = SettingsManager.shared.githubToken ?? ""
        
        let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.addArrangedSubview(infoLabel)
        stackView.addArrangedSubview(input)
        
        alert.accessoryView = stackView
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let newToken = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Instead of directly setting the token, try to detect the username and add as account
            if !newToken.isEmpty {
                let service = GitHubService(token: newToken)
                service.fetchCurrentUsername { username in
                    DispatchQueue.main.async {
                        if let username = username {
                            // Add as an account
                            SettingsManager.shared.addGitHubAccount(username: username, token: newToken)
                            
                            // Refresh the menu
                            self.rebuildMenu()
                            
                            // Refresh PRs
                            NotificationCenter.default.post(name: Notification.Name("GitHubAccountChanged"), object: nil)
                        } else {
                            // Fall back to the legacy method if username can't be determined
                            SettingsManager.shared.githubToken = newToken
                            NotificationCenter.default.post(name: Notification.Name("RefreshAllPRs"), object: nil)
                            self.rebuildMenu()
                        }
                    }
                }
            } else {
                // Handle empty token
                SettingsManager.shared.githubToken = newToken
                NotificationCenter.default.post(name: Notification.Name("RefreshAllPRs"), object: nil)
                self.rebuildMenu()
            }
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
        
        // Add title line
        tooltipLines.append("PR #\(pr.number): \(pr.title)")
        
        // Add account info if available and multiple accounts exist
        if !pr.accountName.isEmpty && SettingsManager.shared.githubAccounts.count > 1 && pr.accountName != "Legacy Account" {
            tooltipLines.append("Account: \(pr.accountName)")
        }
        
        // Add repository name if available
        if let repoName = extractRepoNameFromURL(pr.url) {
            tooltipLines.append("Repository: \(repoName)")
        }
        
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
        
        // Don't show action menu for user's own PRs or draft PRs
        let isOwnPR = pr.status == .yourPR || pr.status == .draftPR
        
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

    // Add these methods for GitHub account management
    @objc private func addGitHubAccount() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Add GitHub Account"
        alert.informativeText = "Please enter your GitHub personal access token. The username will be automatically detected."
        
        let tokenField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tokenField.placeholderString = "GitHub Personal Access Token"
        
        alert.accessoryView = tokenField
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !token.isEmpty {
                // Show loading state while detecting username
                startLoadingAnimation()
                
                // Verify token by trying to fetch the user's profile
                let service = GitHubService(token: token)
                service.fetchCurrentUsername { [weak self] fetchedUsername in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        // Stop loading animation
                        self.stopLoadingAnimation()
                        
                        if let username = fetchedUsername {
                            // Add the account
                            SettingsManager.shared.addGitHubAccount(username: username, token: token)
                            self.rebuildMenu()
                            
                            // Refresh PRs with all accounts
                            NotificationCenter.default.post(name: Notification.Name("GitHubAccountChanged"), object: nil)
                            
                            // Show success message
                            let successAlert = NSAlert()
                            successAlert.alertStyle = .informational
                            successAlert.messageText = "Account Added"
                            successAlert.informativeText = "GitHub account '\(username)' has been added successfully."
                            successAlert.runModal()
                        } else {
                            // Show error if token is invalid
                            let errorAlert = NSAlert()
                            errorAlert.alertStyle = .critical
                            errorAlert.messageText = "Invalid Token"
                            errorAlert.informativeText = "The provided token is invalid or doesn't have the required permissions."
                            errorAlert.runModal()
                        }
                    }
                }
            } else {
                // Show error for empty token
                let errorAlert = NSAlert()
                errorAlert.alertStyle = .critical
                errorAlert.messageText = "Invalid Input"
                errorAlert.informativeText = "A valid GitHub token is required."
                errorAlert.runModal()
            }
        }
    }

    @objc private func updateGitHubAccountToken(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String else { return }
        
        // Find the account with this username
        let accounts = SettingsManager.shared.githubAccounts
        if let account = accounts.first(where: { $0.username == username }) {
            // Show update token dialog
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Update GitHub Token"
            alert.informativeText = "Please enter the new GitHub personal access token for the account '\(username)'."
            
            let tokenField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            tokenField.stringValue = account.token
            
            alert.accessoryView = tokenField
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                let newToken = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !newToken.isEmpty {
                    // Update the account token
                    SettingsManager.shared.updateGitHubAccountToken(username: username, newToken: newToken)
                    
                    // Refresh the menu
                    rebuildMenu()
                    
                    // Refresh PRs from the updated account
                    NotificationCenter.default.post(name: Notification.Name("GitHubAccountChanged"), object: nil)
                } else {
                    // Show error for empty token
                    let errorAlert = NSAlert()
                    errorAlert.alertStyle = .critical
                    errorAlert.messageText = "Invalid Token"
                    errorAlert.informativeText = "A valid token is required to update the account."
                    errorAlert.runModal()
                }
            }
        }
    }

    // Helper method to rebuild the menu with current pull requests
    private func rebuildMenu() {
        updateMenu(with: pullRequests)
    }

    // MARK: - PR Actions for Owner
    
    @objc private func markPRReady(_ sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PullRequest else {
            print("ERROR: No pull request found")
            return
        }
        
        // Extract repo information from PR URL
        guard let repoInfo = githubService?.extractRepoInfo(from: pr.url) else {
            displayErrorAlert(title: "Invalid PR URL", message: "Could not determine repository information")
            return
        }
        
        // Show loading state
        startLoadingAnimation()
        
        // Call the GitHub API
        githubService?.markPRReadyForReview(
            owner: repoInfo.owner,
            repo: repoInfo.repo,
            prNumber: repoInfo.number
        ) { [weak self] success, errorMessage in
            DispatchQueue.main.async {
                self?.stopLoadingAnimation()
                
                if success {
                    // Show success alert
                    let alert = NSAlert()
                    alert.messageText = "Success!"
                    alert.informativeText = "Your pull request is now marked as ready for review."
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
    
    @objc private func closePR(_ sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PullRequest else {
            print("ERROR: No pull request found")
            return
        }
        
        // Extract repo information from PR URL
        guard let repoInfo = githubService?.extractRepoInfo(from: pr.url) else {
            displayErrorAlert(title: "Invalid PR URL", message: "Could not determine repository information")
            return
        }
        
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Close Pull Request"
        alert.informativeText = "Are you sure you want to close PR #\(pr.number): \(pr.title)? This action cannot be undone from this app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close PR")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // User confirmed, proceed with closing the PR
            
            // Show loading state
            startLoadingAnimation()
            
            // Call the GitHub API
            githubService?.closePR(
                owner: repoInfo.owner,
                repo: repoInfo.repo,
                prNumber: repoInfo.number
            ) { [weak self] success, errorMessage in
                DispatchQueue.main.async {
                    self?.stopLoadingAnimation()
                    
                    if success {
                        // Show success alert
                        let alert = NSAlert()
                        alert.messageText = "Success!"
                        alert.informativeText = "Pull request has been closed."
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
    }

    @objc private func removeGitHubAccount(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String else { return }
        
        // Confirm removal
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove GitHub Account"
        alert.informativeText = "Are you sure you want to remove the GitHub account '\(username)'?"
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Remove the account
            SettingsManager.shared.removeGitHubAccount(username: username)
            
            // Refresh the menu
            rebuildMenu()
            
            // Refresh PRs with remaining accounts
            if !SettingsManager.shared.githubAccounts.isEmpty {
                NotificationCenter.default.post(name: Notification.Name("GitHubAccountChanged"), object: nil)
            } else {
                // Show token missing alert if no accounts left
                showTokenMissingAlert()
            }
        }
    }

    // Method to set a custom color for an account
    @objc private func setAccountColor(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String else { return }
        
        // Store the username being edited
        currentEditingUsername = username
        
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelDidChoose(_:)))
        colorPanel.isContinuous = true // Make the panel respond continuously to color changes
        colorPanel.delegate = self
        
        // Set current color if one exists
        if let hexColor = SettingsManager.shared.getAccountColor(username: username),
           let color = NSColor.fromHexString(hexColor) {
            colorPanel.color = color
        } else {
            // Otherwise use the auto-generated color
            colorPanel.color = colorForAccountName(username: username)
        }
        
        colorPanel.makeKeyAndOrderFront(nil)
    }
    
    // Handle color selection from the color panel
    @objc private func colorPanelDidChoose(_ sender: NSColorPanel) {
        // Use the stored username property instead of the accessory view
        guard let username = currentEditingUsername else { return }
        
        // Convert the selected color to hex and store it
        let color = sender.color
        let hexString = color.hexString
        SettingsManager.shared.setAccountColor(username: username, hexColor: hexString)
        
        // Refresh the menu to show the new color
        rebuildMenu()
    }
    
    // Method to reset account color to default
    @objc private func resetAccountColor(_ sender: NSMenuItem) {
        if let username = sender.representedObject as? String {
            SettingsManager.shared.removeAccountColor(username: username)
            rebuildMenu()
        }
    }

    // Create a submenu to toggle visibility of accounts
    private func visibleAccountsSubMenu() -> NSMenu {
        let accountsMenu = NSMenu()
        
        // Add "Show All" option
        let showAllItem = NSMenuItem(title: "Show All Accounts", action: #selector(showAllAccounts), keyEquivalent: "")
        showAllItem.target = self
        accountsMenu.addItem(showAllItem)
        
        accountsMenu.addItem(NSMenuItem.separator())
        
        // Add toggle items for each account
        for account in SettingsManager.shared.githubAccounts {
            let isEnabled = SettingsManager.shared.isAccountEnabled(account.username)
            let accountItem = NSMenuItem(title: account.username, action: #selector(toggleAccountVisibility(_:)), keyEquivalent: "")
            accountItem.state = isEnabled ? .on : .off
            accountItem.representedObject = account.username
            accountItem.target = self
            
            // Add color indicator
            let accountColor = colorForAccountName(username: account.username)
            let colorImage = NSImage.coloredSquare(color: accountColor, size: UIConstants.accountColorIndicatorSize)
            accountItem.image = colorImage
            
            accountsMenu.addItem(accountItem)
        }
        
        return accountsMenu
    }
    
    @objc private func showAllAccounts() {
        // Enable all accounts
        let allAccounts = SettingsManager.shared.githubAccounts
        let allUsernames = allAccounts.map { $0.username }
        SettingsManager.shared.enabledGitHubAccounts = allUsernames
        refreshAll()
    }
    
    @objc private func toggleAccountVisibility(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String else { return }
        
        // Toggle visibility for this account
        SettingsManager.shared.toggleAccountEnabled(username)
        
        // Update the menu item state
        sender.state = SettingsManager.shared.isAccountEnabled(username) ? .on : .off
        
        // Refresh the menu to reflect changes
        refreshAll()
    }

    // Create a submenu with actions for each account
    private func accountActionSubmenu(for username: String) -> NSMenu {
        let accountMenu = NSMenu()
        
        // Update token option
        let updateTokenItem = NSMenuItem(title: "Update Token", action: #selector(updateGitHubAccountToken(_:)), keyEquivalent: "")
        updateTokenItem.target = self
        updateTokenItem.representedObject = username
        accountMenu.addItem(updateTokenItem)
        
        // Add color customization options
        accountMenu.addItem(NSMenuItem.separator())
        
        // Set custom color option
        let setColorItem = NSMenuItem(title: "Set Custom Color", action: #selector(setAccountColor(_:)), keyEquivalent: "")
        setColorItem.target = self
        setColorItem.representedObject = username
        accountMenu.addItem(setColorItem)
        
        // Reset color option (only enable if a custom color is set)
        let resetColorItem = NSMenuItem(title: "Reset to Default Color", action: #selector(resetAccountColor(_:)), keyEquivalent: "")
        resetColorItem.target = self
        resetColorItem.representedObject = username
        resetColorItem.isEnabled = SettingsManager.shared.getAccountColor(username: username) != nil
        accountMenu.addItem(resetColorItem)
        
        accountMenu.addItem(NSMenuItem.separator())
        
        // Remove account option
        let removeItem = NSMenuItem(title: "Remove Account", action: #selector(removeGitHubAccount(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = username
        accountMenu.addItem(removeItem)
        
        return accountMenu
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

// Extension to create a color square image
extension NSImage {
    static func coloredSquare(color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Use clear background for better appearance
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // Draw the colored circle with a slight border
        color.setFill()
        let circlePath = NSBezierPath(ovalIn: NSRect(origin: NSPoint(x: 1, y: 1), 
                                                    size: NSSize(width: size.width - 2, height: size.height - 2)))
        circlePath.fill()
        
        // Add subtle border
        NSColor.darkGray.withAlphaComponent(0.5).setStroke()
        circlePath.lineWidth = 0.5
        circlePath.stroke()
        
        image.unlockFocus()
        
        // Disable template mode for better color display
        image.isTemplate = false
        
        return image
    }
    
    // Method to consistently resize images for menu items
    func resizedForMenuItemHeight(_ height: CGFloat) -> NSImage {
        let newSize: NSSize
        
        // Calculate proportional width if we're not starting with a square
        if self.size.width != self.size.height {
            let ratio = self.size.width / self.size.height
            newSize = NSSize(width: height * ratio, height: height)
        } else {
            newSize = NSSize(width: height, height: height)
        }
        
        // Create new image with the proper size
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        
        // Draw with proper interpolation for crisp images
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Use NSImage's built-in drawing to handle proper scaling
        self.draw(in: NSRect(origin: .zero, size: newSize),
                 from: NSRect(origin: .zero, size: self.size),
                 operation: .copy,
                 fraction: 1.0)
        
        resizedImage.unlockFocus()
        
        // Preserve template status
        resizedImage.isTemplate = self.isTemplate
        
        return resizedImage
    }
}

// Extension to convert between NSColor and hex strings
extension NSColor {
    var hexString: String {
        guard let rgbColor = self.usingColorSpace(.sRGB) else {
            return "#000000"
        }
        
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
    
    static func fromHexString(_ hex: String) -> NSColor? {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if hexString.hasPrefix("#") {
            hexString.remove(at: hexString.startIndex)
        }
        
        if hexString.count != 6 {
            return nil
        }
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
