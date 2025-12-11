#!/bin/bash

#
#   .SYNOPSIS
#   This script is meant to periodically monitor a macOS computer's 
#   usage and prevent users from doing disallowed things.
#
#   .AUTHOR
#   Charles Christensen
#
#   .NOTES
#   For best usage, add as a cronjob.
#

# Initialize.
main_user="charleschristensen"
admin_user="bmrclinicaladmin"
echo "Running MonitorComputerUsage.sh on $(date) as $(whoami)..." > /Library/Logs/MonitorComputerUsage.log
dow=$(date +%A)
tm=$(date +%H%M)

# Prevent night-time computer usage.
echo "> Checking time of day..." >> /Library/Logs/MonitorComputerUsage.log
if [[ "$dow" == "Sunday" ]] || \
 ( [[ "$dow" == "Monday"    ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
 ( [[ "$dow" == "Tuesday"   ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
 ( [[ "$dow" == "Wednesday" ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
 ( [[ "$dow" == "Thursday"  ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
 ( [[ "$dow" == "Friday"    ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
 ( [[ "$dow" == "Saturday"  ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) )
then
    echo "> !!! Shutting down." >> /Library/Logs/MonitorComputerUsage.log
    #shutdown -h now  >> /Library/Logs/MonitorComputerUsage.log
fi

# Prevent user from modifying this file, its startup, or hosts.
[[ $0 = /* ]] && fullpath=$0 || fullpath=$PWD/${0#./}
echo "> Preventing file modifications..." >> /Library/Logs/MonitorComputerUsage.log
chflags schg $fullpath
chflags uchg $fullpath
chflags schg /etc/hosts
chflags uchg /etc/hosts
chflags schg /etc/sudoers
chflags uchg /etc/sudoers

# Prevent extra users.
echo "> Checking user accounts..." >> /Library/Logs/MonitorComputerUsage.log
dscl . list /Users | grep -v "^_" | while read -r line
do
    if [[ "$line" != $main_user  ]] &&
       [[ "$line" != $admin_user ]] &&
       [[ "$line" != "daemon"    ]] &&
       [[ "$line" != "nobody"    ]] &&
       [[ "$line" != "root"      ]]
    then
        echo "> !!! Deleting user '$line'." >> /Library/Logs/MonitorComputerUsage.log
        dscl . -delete /Users/$line >> /Library/Logs/MonitorComputerUsage.log
    fi
done
ls /Users | while read -r line
do
    if [[ "$line" != $main_user   ]] &&
       [[ "$line" != $admin_user  ]] &&
       [[ "$line" != "Shared"     ]] &&
       [[ "$line" != ".localized" ]]
    then
        echo "> !!! Deleting user folder '$line'." >> /Library/Logs/MonitorComputerUsage.log
        rm -rf /Users/$line >> /Library/Logs/MonitorComputerUsage.log
    fi
done

# Prevent enabling root user.
echo "> Disabling root user..." >> /Library/Logs/MonitorComputerUsage.log
dscl . delete /Users/root AuthenticationAuthority
dscl . -create /Users/root UserShell /usr/bin/false
dscl . -create /Users/root Password '*'

# Prevent unmonitored DNS. (Lock to CleanBrowsing Family.)
echo "> Checking DNS..." >> /Library/Logs/MonitorComputerUsage.log
tmp1=$(scutil --dns | grep nameserver | grep -c -e 185.228.168.168 -e 127.0.0.1)
tmp2=$(scutil --dns | grep nameserver | grep -c -e 185.228.169.168 -e 127.0.0.1)
tmp3=$(scutil --dns | grep -c nameserver)
if (( 10#$tmp1 < 2 )) || (( 10#$tmp2 < 2 )) || (( 10#$tmp3 > 4 ))
then
    echo "> !!! DNS reset needed." >> /Library/Logs/MonitorComputerUsage.log
    captive_test=$(curl -s -I http://captive.apple.com 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '\r')
    if [[ "$captive_test" != "200" ]]
    then
        echo "> !!! Captive portal detected. Skipping DNS reset." >> /Library/Logs/MonitorComputerUsage.log
    else
        echo "> Resetting DNS servers." >> /Library/Logs/MonitorComputerUsage.log
        networksetup -setdnsservers Wi-Fi 185.228.168.168 185.228.169.168 2a0d:2a00:0001:0000:0000:0000:0000:0000 2a0d:2a00:0002:0000:0000:0000:0000:0000 > /dev/null
        networksetup -setdnsservers Ethernet 185.228.168.168 185.228.169.168 2a0d:2a00:0001:0000:0000:0000:0000:0000 2a0d:2a00:0002:0000:0000:0000:0000:0000 > /dev/null
    fi
fi

# Prevent unmonitored hosts.
echo "> Checking hosts file..." >> /Library/Logs/MonitorComputerUsage.log
tmp1=0
if [[ -f /etc/hosts ]]
then
    tmp1=$(wc -l /etc/hosts | awk '{print $1}')
fi
if (( 10#$tmp1 < 100 ))
then
    echo "> Replacing blank hosts file." >> /Library/Logs/MonitorComputerUsage.log
    if [[ -f /etc/hosts ]]
    then
        chflags noschg /etc/hosts
        chflags nouchg /etc/hosts
        rm /etc/hosts
    fi
    cp /Library/Scripts/charlesrc019/hosts_cache.txt /etc/hosts
    cat /Library/Scripts/charlesrc019/hosts_custom.txt >> /etc/hosts
    chown root:wheel /etc/hosts
    chmod 644 /etc/hosts
    killall -HUP mDNSResponder
    chflags schg /etc/hosts
    chflags uchg /etc/hosts
fi

# Prevent use of browsers and Directory Utility.
uid=$(id -u "$main_user")
for app in "Directory Utility" \
           "Safari" \
           "Firefox" \
           "Microsoft Edge" \
           "Opera" \
           "Brave Browser" \
           "Vivaldi" \
           "Tor Browser" \
           "Arc" \
           "UCBrowser" \
           "Maxthon" \
           "Samsung Internet" \
           "Puffin" \
           "Ghostery" \
           "SeaMonkey" \
           "Slimjet"
do
    launchctl asuser $uid osascript -e "tell application \"$app\" to quit" > /dev/null
done

# Lock settings modification.
echo "> Locking system modifications..." >> /Library/Logs/MonitorComputerUsage.log

security -q authorizationdb read system.preferences.accounts > /tmp/system.preferences.accounts.plist
defaults write /tmp/system.preferences.accounts.plist group wheel > /dev/null
security -q authorizationdb write system.preferences.accounts < /tmp/system.preferences.accounts.plist

security -q authorizationdb read system.preferences.datetime > /tmp/system.preferences.datetime.plist
defaults write /tmp/system.preferences.datetime.plist group wheel > /dev/null
security -q authorizationdb write system.preferences.datetime < /tmp/system.preferences.datetime.plist

security -q authorizationdb read system.preferences.security > /tmp/system.preferences.security.plist
defaults write /tmp/system.preferences.security.plist group wheel > /dev/null
security -q authorizationdb write system.preferences.security < /tmp/system.preferences.security.plist 

security -q authorizationdb read system.services.directory.configure > /tmp/system.services.directory.configure.plist
defaults write /tmp/system.services.directory.configure.plist group wheel > /dev/null
security -q authorizationdb write system.services.directory.configure < /tmp/system.services.directory.configure.plist
security -q authorizationdb read system.services.directory > /tmp/system.services.directory.plist
defaults write /tmp/system.services.directory.plist group wheel > /dev/null
security -q authorizationdb write system.services.directory < /tmp/system.services.directory.plist

# Flush the DNS cache.
echo "> Flushing the DNS cache..." >> /Library/Logs/MonitorComputerUsage.log
killall -HUP mDNSResponder

# Refresh hosts.
if [[ "$dow" == "Monday" ]] && (( 10#$tm < 1200 ))
then
    echo "> Updating hosts file..." >> /Library/Logs/MonitorComputerUsage.log
    if [[ -f /etc/hosts ]]
    then
        chflags noschg /etc/hosts
        chflags nouchg /etc/hosts
        rm /etc/hosts
    fi
    cp /Library/Scripts/charlesrc019/hosts_cache.txt /etc/hosts
    cat /Library/Scripts/charlesrc019/hosts_custom.txt >> /etc/hosts
    chown root:wheel /etc/hosts
    chmod 644 /etc/hosts
    killall -HUP mDNSResponder
    chflags schg /etc/hosts
    chflags uchg /etc/hosts
fi

echo "All complete!" >> /Library/Logs/MonitorComputerUsage.log