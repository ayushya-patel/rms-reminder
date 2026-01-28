#!/bin/bash

# ============================================
# RMS Check-in/Check-out Reminder - Installer
# ============================================
# This script sets up automatic reminders for RMS attendance
# - Check-in: Notifies once when you arrive at office
# - Check-out: Reminds between 6-7 PM while at office
#
# Requirements: macOS, Google Chrome
# ============================================

# IMPORTANT: Redirect stdin from /dev/tty to allow user input when piped
exec < /dev/tty

echo "========================================"
echo "  RMS Reminder - Installation Script"
echo "========================================"
echo ""

# Get office IP
echo "First, let's find your office IP address."
echo "Make sure you're connected to your office network."
echo ""
printf "Press Enter to detect your current IP, or type an IP manually: "
read MANUAL_IP

if [ -z "$MANUAL_IP" ]; then
    OFFICE_IP=$(curl -s --max-time 10 https://api.ipify.org)
    if [ -z "$OFFICE_IP" ]; then
        echo "❌ Could not detect IP. Please enter it manually."
        printf "Enter your office IP: "
        read OFFICE_IP
    else
        echo "✓ Detected IP: $OFFICE_IP"
        printf "Is this your office IP? (y/n): "
        read CONFIRM
        if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
            printf "Enter the correct office IP: "
            read OFFICE_IP
        fi
    fi
else
    OFFICE_IP="$MANUAL_IP"
fi

echo ""
echo "Office IP set to: $OFFICE_IP"
echo ""

# Get Chrome profile
echo "Now let's find your Chrome profile."
echo ""

PROFILES_DIR="$HOME/Library/Application Support/Google/Chrome"
LOCAL_STATE="$PROFILES_DIR/Local State"

if [ -f "$LOCAL_STATE" ]; then
    echo "Available profiles:"
    echo ""

    # Get profiles into a temp file for reliable reading
    TEMP_PROFILES=$(mktemp)
    python3 -c "
import json
with open('$LOCAL_STATE', 'r') as f:
    data = json.load(f)
profiles = data.get('profile', {}).get('info_cache', {})
for key, val in profiles.items():
    if key not in ['System Profile', 'Guest Profile']:
        name = val.get('name', 'Unknown')
        email = val.get('user_name', '')
        if email:
            print(f'{key}|{name} ({email})')
        else:
            print(f'{key}|{name}')
" > "$TEMP_PROFILES" 2>/dev/null

    # Display profiles with numbers
    i=1
    while IFS='|' read -r dir name; do
        echo "  $i) $name"
        eval "PROFILE_$i=\"$dir\""
        i=$((i + 1))
    done < "$TEMP_PROFILES"

    TOTAL_PROFILES=$((i - 1))
    rm -f "$TEMP_PROFILES"

    if [ "$TOTAL_PROFILES" -eq 0 ]; then
        echo "  No profiles found. Using 'Default'."
        CHROME_PROFILE="Default"
    else
        echo ""
        printf "Enter the number of your profile (where you use RMS) [1-$TOTAL_PROFILES]: "
        read PROFILE_NUM

        # Validate input
        if [[ "$PROFILE_NUM" =~ ^[0-9]+$ ]] && [ "$PROFILE_NUM" -ge 1 ] && [ "$PROFILE_NUM" -le "$TOTAL_PROFILES" ]; then
            eval "CHROME_PROFILE=\$PROFILE_$PROFILE_NUM"
        else
            echo "Invalid selection. Using 'Default' profile."
            CHROME_PROFILE="Default"
        fi
    fi
else
    echo "Chrome profiles directory not found. Using 'Default' profile."
    CHROME_PROFILE="Default"
fi

echo ""
echo "Chrome profile set to: $CHROME_PROFILE"
echo ""

# Get checkout reminder time
printf "Checkout reminder start hour (default 18 for 6 PM): "
read CHECKOUT_START
CHECKOUT_START=${CHECKOUT_START:-18}

printf "Checkout reminder end hour (default 19 for 7 PM): "
read CHECKOUT_END
CHECKOUT_END=${CHECKOUT_END:-19}

echo ""
echo "Checkout reminders will appear between ${CHECKOUT_START}:00 and ${CHECKOUT_END}:00"
echo ""

# Create Scripts directory
mkdir -p ~/Scripts

# Create the main script
cat > ~/Scripts/rms-checkin-reminder.sh << 'SCRIPT_EOF'
#!/bin/bash

# RMS Check-in/Check-out Reminder Script
# - Check-in: Once when you arrive at office
# - Check-out: Reminds between configured hours while still at office

OFFICE_IP="__OFFICE_IP__"
RMS_URL="https://portal.devxlabs.ai/checkin"
STATE_FILE="$HOME/.rms_checkin_state"
CHROME_PROFILE="__CHROME_PROFILE__"
TODAY=$(date +%Y-%m-%d)
CURRENT_HOUR=$(date +%H)

# Checkout reminder window (24-hour format)
CHECKOUT_START_HOUR=__CHECKOUT_START__
CHECKOUT_END_HOUR=__CHECKOUT_END__

# Get current public IP
get_current_ip() {
    curl -s --max-time 5 https://api.ipify.org 2>/dev/null
}

# Send macOS notification
send_notification() {
    local title="$1"
    local message="$2"
    local action="$3"

    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\""

    # Also open the RMS portal in the configured Chrome profile
    if [ "$action" = "open" ]; then
        open -a "Google Chrome" "$RMS_URL" --args --profile-directory="$CHROME_PROFILE"
    fi
}

# Get state for a specific key (format in file: key=value, one per line)
get_state() {
    local key="$1"
    if [ -f "$STATE_FILE" ]; then
        grep "^$key=" "$STATE_FILE" 2>/dev/null | cut -d= -f2
    fi
}

# Save state for a specific key
save_state() {
    local key="$1"
    local value="$2"

    # Create file if doesn't exist
    touch "$STATE_FILE"

    # Remove old key if exists, then add new
    if grep -q "^$key=" "$STATE_FILE" 2>/dev/null; then
        sed -i '' "/^$key=/d" "$STATE_FILE"
    fi
    echo "$key=$value" >> "$STATE_FILE"
}

# Check if within checkout reminder window
is_checkout_time() {
    if [ "$CURRENT_HOUR" -ge "$CHECKOUT_START_HOUR" ] && [ "$CURRENT_HOUR" -lt "$CHECKOUT_END_HOUR" ]; then
        return 0  # true
    fi
    return 1  # false
}

# Main logic
main() {
    CURRENT_IP=$(get_current_ip)

    if [ -z "$CURRENT_IP" ]; then
        echo "Could not determine current IP"
        exit 1
    fi

    echo "Current IP: $CURRENT_IP"
    echo "Office IP: $OFFICE_IP"
    echo "Today: $TODAY"
    echo "Current hour: $CURRENT_HOUR"

    local checkin_date=$(get_state "checkin_date")
    local checkout_date=$(get_state "checkout_date")

    echo "Last check-in date: $checkin_date"
    echo "Last check-out date: $checkout_date"

    if [ "$CURRENT_IP" = "$OFFICE_IP" ]; then
        # At office

        # 1. Check-in reminder (once per day)
        if [ "$checkin_date" != "$TODAY" ]; then
            echo "Arrived at office - sending check-in reminder"
            send_notification "RMS Reminder" "You've arrived at office! Time to check in." "open"
            save_state "checkin_date" "$TODAY"
        else
            echo "Already sent check-in reminder today"
        fi

        # 2. Check-out reminder (during configured window, if checked in but not checked out)
        if is_checkout_time; then
            if [ "$checkin_date" = "$TODAY" ] && [ "$checkout_date" != "$TODAY" ]; then
                echo "Checkout window - sending check-out reminder"
                send_notification "RMS Reminder" "Don't forget to check out before leaving!" "open"
            else
                echo "In checkout window but either not checked in today or already reminded checkout"
            fi
        else
            echo "Not in checkout reminder window"
        fi
    else
        # Not at office
        echo "Not at office IP, no action needed"

        # Mark checkout as done if we leave after checking in
        if [ "$checkin_date" = "$TODAY" ] && [ "$checkout_date" != "$TODAY" ]; then
            echo "Left office after check-in, marking checkout reminder as done"
            save_state "checkout_date" "$TODAY"
        fi
    fi
}

main
SCRIPT_EOF

# Replace placeholders with actual values
sed -i '' "s|__OFFICE_IP__|$OFFICE_IP|g" ~/Scripts/rms-checkin-reminder.sh
sed -i '' "s|__CHROME_PROFILE__|$CHROME_PROFILE|g" ~/Scripts/rms-checkin-reminder.sh
sed -i '' "s|__CHECKOUT_START__|$CHECKOUT_START|g" ~/Scripts/rms-checkin-reminder.sh
sed -i '' "s|__CHECKOUT_END__|$CHECKOUT_END|g" ~/Scripts/rms-checkin-reminder.sh

# Make executable
chmod +x ~/Scripts/rms-checkin-reminder.sh

echo "✓ Created ~/Scripts/rms-checkin-reminder.sh"

# Create LaunchAgent
mkdir -p ~/Library/LaunchAgents

# Get actual home directory path for plist
ACTUAL_HOME=$(eval echo ~)

cat > ~/Library/LaunchAgents/com.rms.checkin-reminder.plist << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rms.checkin-reminder</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${ACTUAL_HOME}/Scripts/rms-checkin-reminder.sh</string>
    </array>

    <key>StartInterval</key>
    <integer>120</integer>

    <key>WatchPaths</key>
    <array>
        <string>/Library/Preferences/SystemConfiguration</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/rms-checkin-reminder.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/rms-checkin-reminder.error.log</string>
</dict>
</plist>
PLIST_EOF

echo "✓ Created LaunchAgent"

# Load the LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.rms.checkin-reminder.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.rms.checkin-reminder.plist

echo "✓ Started the reminder service"

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Configuration:"
echo "  • Office IP: $OFFICE_IP"
echo "  • Chrome Profile: $CHROME_PROFILE"
echo "  • Checkout Reminder: ${CHECKOUT_START}:00 - ${CHECKOUT_END}:00"
echo ""
echo "Useful commands:"
echo "  • Test now:    ~/Scripts/rms-checkin-reminder.sh"
echo "  • View logs:   cat /tmp/rms-checkin-reminder.log"
echo "  • Stop:        launchctl unload ~/Library/LaunchAgents/com.rms.checkin-reminder.plist"
echo "  • Start:       launchctl load ~/Library/LaunchAgents/com.rms.checkin-reminder.plist"
echo ""
echo "To uninstall, run:"
echo "  launchctl unload ~/Library/LaunchAgents/com.rms.checkin-reminder.plist"
echo "  rm ~/Scripts/rms-checkin-reminder.sh"
echo "  rm ~/Library/LaunchAgents/com.rms.checkin-reminder.plist"
echo "  rm ~/.rms_checkin_state"
echo ""
