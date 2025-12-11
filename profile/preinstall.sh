#!/bin/bash

#
#   .SYNOPSIS
#   This script is meant to run on a macOS computer before installing the
#   corresponding config profile prevent users from doing disallowed things.
#
#   .AUTHOR
#   Charles Christensen
#
#   .NOTES
#   For best usage, run before installing config profile.
#

#todo shutdown-timer, DNS, bad browsers?. 

# Initialize.
main_user="charleschristensen"
admin_user="bmrclinicaladmin"
echo "Running MonitorComputerUsage.sh on $(date) as $(whoami)..."

# Prevent user from modifying  hosts.
echo "> Preventing file modifications..."
chflags schg /etc/hosts
chflags uchg /etc/hosts

# Prevent extra users.
echo "> Checking user accounts..."
dscl . list /Users | grep -v "^_" | while read -r line
do
    if [[ "$line" != $main_user  ]] &&
       [[ "$line" != $admin_user ]] &&
       [[ "$line" != "daemon"    ]] &&
       [[ "$line" != "nobody"    ]] &&
       [[ "$line" != "root"      ]]
    then
        echo "> !!! Deleting user '$line'."
        dscl . -delete /Users/$line
    fi
done
ls /Users | while read -r line
do
    if [[ "$line" != $main_user   ]] &&
       [[ "$line" != $admin_user  ]] &&
       [[ "$line" != "Shared"     ]] &&
       [[ "$line" != ".localized" ]]
    then
        echo "> !!! Deleting user folder '$line'."
        rm -rf /Users/$line
    fi
done

# Prevent enabling root user.
echo "> Disabling root user..."
dscl . delete /Users/root AuthenticationAuthority
dscl . -create /Users/root UserShell /usr/bin/false
dscl . -create /Users/root Password '*'

# Prevent unmonitored hosts.
echo "> Locking hosts file..."
chown root:wheel /etc/hosts
chmod 644 /etc/hosts
killall -HUP mDNSResponder
chflags schg /etc/hosts
chflags uchg /etc/hosts

# Lock settings modification.
echo "> Locking system modifications..."

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

echo "All complete!"