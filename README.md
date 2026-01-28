# RMS Check-in/Check-out Reminder

A macOS utility that automatically reminds you to check in and check out on the RMS (Resource Management System) portal based on your office IP address.

## Features

- **Auto Check-in Reminder**: Notifies you once when you arrive at office (detected via IP range)
- **Auto Check-out Reminder**: Reminds you once after 9 hours of check-in (if still at office)
- **Opens RMS Portal**: Automatically opens the check-in page in your preferred Chrome profile
- **No Performance Impact**: Runs every 2 minutes with negligible CPU/memory usage
- **Privacy Friendly**: Only checks your public IP, no data sent anywhere

## Requirements

- macOS (tested on macOS 12+)
- Google Chrome
- Internet connection

## Installation

### Quick Install

```bash
bash <(curl -sL https://raw.githubusercontent.com/ayushya-patel/rms-reminder/main/install.sh)
```

### Manual Install

1. Clone this repository:
   ```bash
   git clone https://github.com/ayushya-patel/rms-reminder.git
   cd rms-reminder
   ```

2. Run the installer:
   ```bash
   ./install.sh
   ```

3. Follow the prompt to select your Chrome profile

## How It Works

1. A background service runs every 2 minutes (and on network changes)
2. It checks your current public IP address
3. **Check-in**: When your IP is within the office range (first time that day), it shows a notification and opens RMS
4. **Check-out**: 9 hours after check-in, if you're at office, it reminds you once to check out

## Configuration

The installer will prompt you for:

| Setting | Description | Default |
|---------|-------------|---------|
| Chrome Profile | Which Chrome profile to open RMS in | Default |

### Changing Configuration

Edit the script directly:
```bash
nano ~/Scripts/rms-checkin-reminder.sh
```

Then restart the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.rms.checkin-reminder.plist
launchctl load ~/Library/LaunchAgents/com.rms.checkin-reminder.plist
```

## Useful Commands

```bash
# Test the script manually
~/Scripts/rms-checkin-reminder.sh

# View logs
cat /tmp/rms-checkin-reminder.log

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.rms.checkin-reminder.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.rms.checkin-reminder.plist

# Check service status
launchctl list | grep rms
```

## Uninstallation

```bash
# Stop the service
launchctl unload ~/Library/LaunchAgents/com.rms.checkin-reminder.plist

# Remove files
rm ~/Scripts/rms-checkin-reminder.sh
rm ~/Library/LaunchAgents/com.rms.checkin-reminder.plist
rm ~/.rms_checkin_state
```

## Troubleshooting

### Notification not showing?
- Check if notifications are enabled for Terminal/Script Editor in System Preferences > Notifications

### Wrong Chrome profile opening?
- Re-run the installer or edit `~/Scripts/rms-checkin-reminder.sh` and change the `CHROME_PROFILE` variable

### Script not running?
- Check logs: `cat /tmp/rms-checkin-reminder.error.log`
- Verify service is loaded: `launchctl list | grep rms`

## Security & Privacy

This script:
- ✅ Only checks your public IP (via api.ipify.org)
- ✅ Runs with user privileges (no admin/root)
- ✅ Stores only dates locally (~/.rms_checkin_state)
- ✅ Does not access passwords or sensitive data
- ✅ Does not send any personal information anywhere

## License

MIT License - Feel free to use and modify!

## Contributing

Pull requests welcome! Feel free to improve the script or add features.
