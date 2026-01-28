#!/bin/bash

# ============================================
# RMS Check-in/Check-out Reminder - Installer
# ============================================
# This script sets up automatic reminders for RMS attendance
# - Check-in: Notifies once when you arrive at office (IP range based)
# - Check-out: Reminds once after 8 hours of check-in
#
# Office IP Range: 202.71.24.226 to 202.71.24.237
#
# Requirements: macOS, Google Chrome
#
# INSTALL: bash <(curl -sL https://raw.githubusercontent.com/ayushya-patel/rms-reminder/main/install.sh)
# ============================================

echo "========================================"
echo "  RMS Reminder - Installation Script"
echo "========================================"
echo ""
echo "Office IP Range: 202.71.24.226 - 202.71.24.237"
echo ""

# Get Chrome profile
echo "Let's find your Chrome profile."
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
        read PROFILE_NUM </dev/tty

        # Validate input
        if [[ "$PROFILE_NUM" =~ ^[0-9]+$ ]] && [ "$PROFILE_NUM" -ge 1 ] && [ "$PROFILE_NUM" -le "$TOTAL_PROFILES" ]; then
            eval "CHROME_PROFILE=\$PROFILE_$PROFILE_NUM"
            echo "✓ Selected profile: $CHROME_PROFILE"
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

# Create Scripts directory
mkdir -p ~/Scripts

# Create the main script
cat > ~/Scripts/rms-checkin-reminder.sh << 'SCRIPT_EOF'
#!/bin/bash

# RMS Check-in/Check-out Reminder Script
# - Check-in: Once when IP is within office range
# - Check-out: Once, 8 hours after check-in (if at office when 8h complete)

# Office IP Range: 202.71.24.226 to 202.71.24.237
IP_RANGE_START="202.71.24.226"
IP_RANGE_END="202.71.24.237"

RMS_URL="https://portal.devxlabs.ai/checkin"
STATE_FILE="$HOME/.rms_checkin_state"
CHROME_PROFILE="__CHROME_PROFILE__"
TODAY=$(date +%Y-%m-%d)
CURRENT_TIMESTAMP=$(date +%s)

# Hours before checkout reminder
HOURS_BEFORE_CHECKOUT=8

# Get current public IP
get_current_ip() {
    curl -s --max-time 5 https://api.ipify.org 2>/dev/null
}

# Convert IP to number for comparison
ip_to_number() {
    local ip="$1"
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo $((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))
}

# Check if IP is within office range
is_office_ip() {
    local ip="$1"
    local ip_num=$(ip_to_number "$ip")
    local start_num=$(ip_to_number "$IP_RANGE_START")
    local end_num=$(ip_to_number "$IP_RANGE_END")

    if [ "$ip_num" -ge "$start_num" ] && [ "$ip_num" -le "$end_num" ]; then
        return 0  # true - in range
    fi
    return 1  # false - not in range
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

# Get state for a specific key
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

    touch "$STATE_FILE"

    if grep -q "^$key=" "$STATE_FILE" 2>/dev/null; then
        sed -i '' "/^$key=/d" "$STATE_FILE"
    fi
    echo "$key=$value" >> "$STATE_FILE"
}

# Main logic
main() {
    CURRENT_IP=$(get_current_ip)

    if [ -z "$CURRENT_IP" ]; then
        echo "Could not determine current IP"
        exit 1
    fi

    echo "Current IP: $CURRENT_IP"
    echo "Office IP Range: $IP_RANGE_START - $IP_RANGE_END"
    echo "Today: $TODAY"
    echo "Current timestamp: $CURRENT_TIMESTAMP"

    local checkin_date=$(get_state "checkin_date")
    local checkin_timestamp=$(get_state "checkin_timestamp")
    local checkout_done=$(get_state "checkout_done")

    echo "Last check-in date: $checkin_date"
    echo "Check-in timestamp: $checkin_timestamp"
    echo "Checkout done: $checkout_done"

    # Check if it's a new day - reset state
    if [ "$checkin_date" != "$TODAY" ]; then
        echo "New day detected, resetting state"
        save_state "checkout_done" ""
        checkout_done=""
    fi

    if is_office_ip "$CURRENT_IP"; then
        echo "IP is within office range"

        # 1. Check-in reminder (once per day)
        if [ "$checkin_date" != "$TODAY" ]; then
            echo "Arrived at office - sending check-in reminder"
            send_notification "RMS Reminder" "You've arrived at office! Time to check in." "open"
            save_state "checkin_date" "$TODAY"
            save_state "checkin_timestamp" "$CURRENT_TIMESTAMP"
            save_state "checkout_done" ""
        else
            echo "Already sent check-in reminder today"

            # 2. Check-out reminder (once, 8 hours after check-in)
            if [ -n "$checkin_timestamp" ] && [ "$checkout_done" != "$TODAY" ]; then
                local seconds_since_checkin=$((CURRENT_TIMESTAMP - checkin_timestamp))
                local hours_since_checkin=$((seconds_since_checkin / 3600))
                local required_seconds=$((HOURS_BEFORE_CHECKOUT * 3600))

                echo "Seconds since check-in: $seconds_since_checkin"
                echo "Hours since check-in: $hours_since_checkin"

                if [ "$seconds_since_checkin" -ge "$required_seconds" ]; then
                    echo "8 hours completed and still at office - sending check-out reminder"
                    send_notification "RMS Reminder" "8 hours completed! Time to check out." "open"
                    save_state "checkout_done" "$TODAY"
                else
                    local remaining_seconds=$((required_seconds - seconds_since_checkin))
                    local remaining_hours=$((remaining_seconds / 3600))
                    local remaining_minutes=$(((remaining_seconds % 3600) / 60))
                    echo "Checkout reminder in ${remaining_hours}h ${remaining_minutes}m"
                fi
            else
                echo "Checkout already done today or no check-in timestamp"
            fi
        fi
    else
        echo "IP is NOT within office range - no action"
        # Don't discard checkout - user might come back to office later
    fi
}

main
SCRIPT_EOF

# Replace placeholder with actual Chrome profile
sed -i '' "s|__CHROME_PROFILE__|$CHROME_PROFILE|g" ~/Scripts/rms-checkin-reminder.sh

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
echo "  • Office IP Range: 202.71.24.226 - 202.71.24.237"
echo "  • Chrome Profile: $CHROME_PROFILE"
echo "  • Checkout Reminder: 8 hours after check-in"
echo ""
echo "How it works:"
echo "  • Check-in reminder when you arrive at office"
echo "  • Check-out reminder once after 8 hours (if still at office)"
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
