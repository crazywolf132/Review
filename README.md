# PR Review

A macOS menu bar application that helps you keep track of GitHub pull requests that need your review.

## Features

- Sits in your macOS menu bar with a count of pending pull requests
- Shows "9+" when there are more than 9 pull requests
- Displays "No pull requests" when you're all caught up
- Lists all pull requests requiring your review when clicked
- Opens pull requests in your browser when selected
- Automatically polls GitHub for updates
- Push notifications for new pull requests
- Configurable for GitHub Enterprise
- Secure storage of GitHub tokens
- Efficient GraphQL-based PR fetching with REST API fallback
- Smart categorization of PRs by status (needs review, your PRs, etc.)
- Filter PRs from archived repositories
- Shows merge conflict status for pull requests

## Requirements

- macOS 11.0+
- GitHub account with access to repositories
- GitHub Personal Access Token

## Installation

1. Download the latest version from the Releases page
2. Move the application to your Applications folder
3. Launch the application
4. Configure your GitHub settings (base URL and token)

## Setting up your GitHub Token

1. Visit GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
2. Generate a new token with the following scopes:
   - `repo` (for access to repositories)
   - `read:user` (to read your assigned PRs)
   - `notifications` (for PR notifications)
3. Copy the token and paste it into the app's settings

## Usage

- The app will show a count of pull requests in the menu bar
- Click the icon to see a list of pull requests
- Click on a pull request to open it in your default browser
- Filter pull requests with the settings menu:
  - Toggle visibility of different PR categories
  - Show/hide PRs from archived repositories
- Pull requests are automatically removed from the list once they're approved or merged
- The list automatically refreshes (every 5 minutes by default)

## Technical Details

- Primary implementation uses GitHub's GraphQL API for efficient data fetching
- Automatic fallback to REST API if GraphQL fails
- Caches profile images using Kingfisher for improved performance
- Intelligent deduplication of pull requests across categories
- Smart prioritization of PR status types

## Privacy & Security

- Your GitHub token is stored securely in the app's settings
- All communication with GitHub is done using HTTPS
- No data is sent to any third-party services

## Support

If you encounter any issues or have feature requests, please submit them through the GitHub Issues page.

## License

MIT 