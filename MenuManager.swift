// Track image loading across menu refreshes
private var imageLoadingMenuItems = Set<NSMenuItem>()

// Constants for consistent UI sizing
private struct UIConstants {
    static let profileImageSize = CGSize(width: 24, height: 24)
    static let accountColorIndicatorSize = CGSize(width: 14, height: 14)
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

    // Show a color indicator next to the menu item
    let accountColor = colorForAccountName(username: account.username)
    let colorImage = NSImage.coloredSquare(color: accountColor, size: UIConstants.accountColorIndicatorSize)
    accountItem.image = colorImage

    // Add color indicator
    let accountColor = colorForAccountName(username: account.username)
    let colorImage = NSImage.coloredSquare(color: accountColor, size: UIConstants.accountColorIndicatorSize)
    accountItem.image = colorImage
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
        
        // Enable template mode for better Dark Mode support
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