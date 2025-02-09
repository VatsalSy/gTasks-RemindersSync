# GTasks-RemindersSync

A Swift command-line tool that provides two-way synchronization between Google Tasks and Apple Reminders. This tool allows you to keep your tasks in sync across both platforms, including titles, due dates, and completion status.

## Features

- One-way sync from Google Tasks to Apple Reminders (initial sync)
- Two-way sync for subsequent runs
- Syncs task properties:
  - Title
  - Due dates
  - Completion status
  - Notes
- Creates reminders with alarms for tasks with due dates
- Detailed logging for troubleshooting

## Prerequisites

- macOS (required for Apple Reminders access)
- Xcode and Swift development tools
- A Google Cloud Project with the Tasks API enabled
- OAuth 2.0 credentials from Google Cloud Console

## Setup

1. **Create a Google Cloud Project**
   - Go to the [Google Cloud Console](https://console.cloud.google.com)
   - Create a new project or select an existing one
   - Enable the Tasks API
   - Create OAuth 2.0 credentials (Desktop Application type)
   - Download the client ID and client secret

2. **Set Environment Variables**
   Create a `.env` file in the project root with the following variables:
   ```
   GOOGLE_CLIENT_ID=your_client_id
   GOOGLE_CLIENT_SECRET=your_client_secret
   ```

3. **Build the Project**
   ```bash
   swift build
   ```

4. **Run the Application**
   ```bash
   swift run gTasks-RemindersSync
   ```

   On first run:
   - The application will prompt you to authorize access to your Google Tasks
   - Follow the URL provided in the console
   - After authorization, copy the code and paste it back into the console
   - The application will store the token for future use
   - You'll need to grant access to Apple Reminders when prompted

## Usage

1. **Initial Sync**
   - The first sync will create Apple Reminders for all your Google Tasks
   - Tasks will be created in a list called "GTasks"
   - Due dates and completion status will be preserved

2. **Subsequent Syncs**
   - Run the application whenever you want to sync
   - Changes from both services will be synchronized
   - New tasks, updates, and deletions will be reflected in both services

## Architecture

The application consists of three main services:

1. **GoogleTasksService**
   - Handles authentication with Google Tasks API
   - Manages task list operations
   - Converts between Google Tasks and internal Task model

2. **RemindersService**
   - Manages Apple Reminders integration
   - Handles reminder list creation and management
   - Converts between Reminders and internal Task model

3. **SyncManager**
   - Orchestrates synchronization between services
   - Handles conflict resolution
   - Manages the sync process

## Troubleshooting

If you encounter issues:

1. **Authorization Issues**
   - Delete the stored Google token and reauthorize
   - Check your OAuth credentials in Google Cloud Console
   - Ensure the Tasks API is enabled

2. **Sync Issues**
   - Check the console logs for detailed information
   - Verify Apple Reminders permissions
   - Ensure the "GTasks" list exists in Apple Reminders

3. **Due Date Issues**
   - Ensure your system timezone matches Google Tasks
   - Check the logs for date parsing information

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
