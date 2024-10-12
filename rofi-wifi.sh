#!/usr/bin/env bash

# Constants
divider="---------"
goback="Back"
loading_message="Scanning for Wi-Fi networks..."

# Checks if Wi-Fi is enabled
wifi_enabled() {
    nmcli radio wifi
}

# Function to remove icon if present
remove_icon_if_present() {
    local ssid="$1"
    if [[ "$ssid" == "󱚻 "* ]]; then
        ssid="${ssid#󱚻 }"  # Remove the icon if it's at the start
    fi
    echo "$ssid"
}


# Toggles Wi-Fi power state
toggle_wifi() {
    if [[ $(wifi_enabled) == "enabled" ]]; then
        nmcli radio wifi off
    else
        nmcli radio wifi on
    fi
    show_menu
}

# Scans for available Wi-Fi networks
scan_networks() {
    nmcli device wifi rescan
    show_menu
}

# Lists available Wi-Fi networks
list_networks() {
    local connected_ssid
    connected_ssid=$(nmcli -t -f SSID,ACTIVE device wifi | grep 'yes' | cut -d: -f1)

    nmcli -t -f SSID,SECURITY device wifi list | tail -n +2 | \
    while IFS=: read -r ssid security; do
          if [[ -n "$ssid" && "$ssid" == "$connected_ssid" ]]; then
            # Highlight connected SSID
            echo -e "󱚻 $ssid"  # icon for connected SSID
        else
            echo "$ssid"
        fi
    done | grep -v '^$'
}

# Function to check if a connection exists and is active
is_connected() {
    local ssid="$1"
    nmcli -t -f STATE,CONNECTION device | grep -qE "^connected:$ssid$"
}

# Function to prompt for user choice with options
prompt_choice() {
    local prompt="$1"
    local options="$2"
    echo -e "$options" | rofi -dmenu -p "$prompt"
}

# Function to handle existing connection
handle_existing_connection() {
    local ssid="$1"

    if is_connected "$ssid"; then
        choice=$(prompt_choice "Already connected to $ssid. Choose an option:" "Disconnect\nDelete")
        case "$choice" in
            "Disconnect")
                nmcli device disconnect wlp1s0
                echo "Disconnected from $ssid."
                ;;
            "Delete")
                nmcli connection delete "$ssid"
                echo "Deleted the connection for $ssid."
                ;;
        esac
    else
        choice=$(prompt_choice "Connection exists for $ssid but is not active. Choose an option:" "Connect\nDelete")
        case "$choice" in
            "Connect")
                connect_to_wifi "$ssid"
                ;;
            "Delete")
                nmcli connection delete "$ssid"
                echo "Deleted the connection for $ssid."
                ;;
        esac
    fi
}

# Function to connect to Wi-Fi
connect_to_wifi() {
    local ssid="$1"

    # Show a Rofi window with a "Connecting..." message
    echo "Connecting..." | rofi -dmenu -p "Connecting to $ssid..." &

    # Get the PID of the Rofi process
    local rofi_pid=$!

    echo "Attempting to connect to $ssid."

    # Attempt to connect to the Wi-Fi
    nmcli device wifi connect "$ssid"

    # Kill the Rofi process
    kill "$rofi_pid"

}


# Function to handle new connection
handle_new_connection() {
    local ssid="$1"
    while true; do
        password=$(echo "" | rofi -dmenu -p "Enter password for $ssid: ")
        if [ -n "$password" ]; then

            # Show a Rofi window with a "Connecting..." message
            echo "Connecting..." | rofi -dmenu -p "Connecting to $ssid..." &

            # Get the PID of the Rofi process
            local rofi_pid=$!

            echo "Attempting to connect to $ssid."

            nmcli device wifi connect "$ssid" password "$password"
            if [[ $? -eq 0 ]]; then
                kill "$rofi_pid"
                echo "Connected successfully to $ssid."
                break
            else
                kill "$rofi_pid"
                echo "Connection failed. Removing the connection."
                nmcli connection delete "$ssid"
                choice=$(prompt_choice "Connection failed. The password may be incorrect. Choose an option:" "Retry\nCancel")
                if [[ "$choice" == "Cancel" ]]; then
                    echo "Cancelled. Returning to the network list."
                    break
                fi
                echo "Please re-enter the password."
            fi
        else
            rofi -e "No password provided."
            break
        fi
    done
}

# Main function to connect to Wi-Fi
connect_wifi() {
    local ssid=$(remove_icon_if_present "$1")
    nmcli connection show "$ssid" > /dev/null 2>&1
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "Connection exists for $ssid."
        handle_existing_connection "$ssid"
    else
        echo "Connection does not exist."
        handle_new_connection "$ssid"
    fi
    show_menu
}

# Disconnects from the current Wi-Fi connection
disconnect_wifi() {
    nmcli device disconnect wlp1s0
    show_menu
}


# Displays the status of the current Wi-Fi connection
print_status() {
    nmcli -t -f ACTIVE,NAME,TYPE connection show --active | grep '^yes:' | grep 'wireless' | cut -d: -f2 || echo "Not connected"
}

kill_rofi() {
    if pgrep -x "rofi" > /dev/null; then
        pkill -x "rofi"
    fi
}

# Main menu
show_menu() {
    local options
    local wifi_status
    wifi_status=$(wifi_enabled)

    if [[ "$wifi_status" == "enabled" ]]; then
        echo -e "Scanning Networks" | rofi -dmenu -p "Scanning" &
        options=$(list_networks)
        options="$options\n$divider\nPower: on\nExit"
    else
        options="Power: off\nExit"
    fi

    # kill the rofi process if it's still running
    kill_rofi
    chosen="$(echo -e "$options" | rofi -dmenu -p "Wi-Fi")"

    case "$chosen" in
        "" | "$divider")
            echo "No option chosen."
            ;;
        "Power: on")
            toggle_wifi
            ;;
        "Power: off")
            toggle_wifi
            ;;
        *)
            if [[ "$wifi_status" == "enabled" ]]; then
                connect_wifi "$chosen"
            fi
            ;;
    esac
}

case "$1" in
    --status)
        print_status
        ;;
    *)
        show_menu
        ;;
esac
