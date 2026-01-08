#!/bin/bash

#
#   .SYNOPSIS
#   This script is meant to monitor a macOS computer's usage
#   and prevent users from doing disallowed things.
#
#   .AUTHOR
#   Charles Christensen
#
#   .NOTES
#   For best usage, add as a LaunchDaemon to run as root on
#   startup and block chflags, killall, su, and visudo in sudoers.
#

# Initialize.
MAIN_USER="charlesrc019"
ADMIN_USER="admin"
run_hourly=0
run_once=0
[[ $0 = /* ]] && fullpath=$0 || fullpath=$PWD/${0#./}
echo "Starting $fullpath on $(date) as $(whoami)..." > /Library/Logs/mac-enforcer.log
echo " " >> /Library/Logs/mac-enforcer.log

# Monitor tasks continuously.
while true
do
    dow=$(date +%A)
    tm=$(date +%H%M)

    # Prevent night-time computer usage.
    if [[ "$dow" == "Sunday" ]] || \
    ( [[ "$dow" == "Monday"    ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
    ( [[ "$dow" == "Tuesday"   ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
    ( [[ "$dow" == "Wednesday" ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2140)) ) ) || \
    ( [[ "$dow" == "Thursday"  ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
    ( [[ "$dow" == "Friday"    ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) ) || \
    ( [[ "$dow" == "Saturday"  ]] && ( ((10#$tm < 900)) || ((10#$tm >= 2130)) ) )
    then
        echo "> Shutting down. (Outside allowable time.)" >> /Library/Logs/mac-enforcer.log
        #shutdown -h now  >> /Library/Logs/mac-enforcer.log
    fi

    # Kill switch check.
    today_date=$(date +%m/%d/%Y)
    if grep -q "$today_date" /Library/Scripts/mac-enforcer/kill_switch.txt
    then
        echo "> Shutting down. (Kill switch activated for $today_date.)" >> /Library/Logs/mac-enforcer.log
        shutdown -h now  >> /Library/Logs/mac-enforcer.log
    fi

    # Prevent user from modifying this file, its startup, or hosts.
    chflags schg "$fullpath"
    chflags uchg "$fullpath"
    chflags schg /Library/LaunchDaemons/com.charlesrc019.mac-enforcer.plist
    chflags uchg /Library/LaunchDaemons/com.charlesrc019.mac-enforcer.plist

    # Prevent extra users.
    dscl . list /Users | grep -v "^_" | while read -r line
    do
        if [ "$line" != "$MAIN_USER"  ] &&
           [ "$line" != "$ADMIN_USER" ] &&
           [ "$line" != "daemon"      ] &&
           [ "$line" != "nobody"      ] &&
           [ "$line" != "root"        ]
        then
            echo "> Deleting user '$line'." >> /Library/Logs/mac-enforcer.log
            dscl . -delete /Users/"$line" >> /Library/Logs/mac-enforcer.log
        fi
    done

    # Prevent extra user folders.
    ls /Users | while read -r line
    do
        if [ "$line" != "$MAIN_USER"   ] &&
           [ "$line" != "$ADMIN_USER"  ] &&
           [ "$line" != "Shared"       ] &&
           [ "$line" != ".localized"   ]
        then
            echo "> Deleting user folder '$line'." >> /Library/Logs/mac-enforcer.log
            rm -rf "/Users/$line" >> /Library/Logs/mac-enforcer.log
        fi
    done

    # Prevent enabling root user.
    if dscl . -read /Users/root Password | grep "\*\*" 
    then
        echo "> Disabling root user." >> /Library/Logs/mac-enforcer.log
        dscl . delete /Users/root AuthenticationAuthority
        dscl . -create /Users/root UserShell /usr/bin/false
        dscl . -create /Users/root Password '*'
    fi

    # Prevent unmonitored DNS. (Lock to CleanBrowsing Family.)
    tmp1=$(scutil --dns | grep nameserver | grep -c -e 185.228.168.168 -e 127.0.0.1)
    tmp2=$(scutil --dns | grep nameserver | grep -c -e 185.228.169.168 -e 127.0.0.1)
    tmp3=$(scutil --dns | grep -c nameserver)
    if (( 10#$tmp1 < 2 )) || (( 10#$tmp2 < 2 )) || (( 10#$tmp3 > 4 ))
    then
        echo "> DNS reset needed." >> /Library/Logs/mac-enforcer.log
        captive_test=$(curl -s -I http://captive.apple.com 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '\r')
        if [[ "$captive_test" != "200" ]]
        then
            echo "> + Captive portal detected. Clearing DNS reset." >> /Library/Logs/mac-enforcer.log
            networksetup -setdnsservers Wi-Fi Empty
            networksetup -setdnsservers Ethernet Empty
            sleep 5 > /dev/null
        else
            echo "> + Resetting DNS servers." >> /Library/Logs/mac-enforcer.log
            networksetup -setdnsservers Wi-Fi 185.228.168.168 185.228.169.168 2a0d:2a00:0001:0000:0000:0000:0000:0000 2a0d:2a00:0002:0000:0000:0000:0000:0000 > /dev/null
            networksetup -setdnsservers Ethernet 185.228.168.168 185.228.169.168 2a0d:2a00:0001:0000:0000:0000:0000:0000 2a0d:2a00:0002:0000:0000:0000:0000:0000 > /dev/null
        fi
    fi

    # Prevent unmonitored hosts.
    tmp1=0
    if [ -f /etc/hosts ]
    then
        tmp1=$(wc -l /etc/hosts | awk '{print $1}')
    fi
    if (( 10#$tmp1 < 100 ))
    then
        echo "> Replacing blank hosts file." >> /Library/Logs/mac-enforcer.log
        if [ -f /etc/hosts ]
        then
            chflags noschg /etc/hosts
            chflags nouchg /etc/hosts
            rm /etc/hosts
        fi
        cp /Library/Scripts/mac-enforcer/hosts_cache.txt /etc/hosts
        cat /Library/Scripts/mac-enforcer/hosts_custom.txt >> /etc/hosts
        chown root:wheel /etc/hosts
        chmod 644 /etc/hosts
        killall -HUP mDNSResponder
        chflags schg /etc/hosts
        chflags uchg /etc/hosts
    fi

    # Prevent use of browsers and Directory Utility.
    uid=$(id -u "$MAIN_USER")
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

    # Run hourly tasks. Also run on script startup.
    if ((( (10#$tm % 100) == 0 )) && (( 10#$run_hourly != 10#$tm ))) || [ "$run_once" == 0 ]
    then
        run_hourly=$tm

        echo "> Locking system modifications..." >> /Library/Logs/mac-enforcer.log

        # Prevent extra user creation.
        security -q authorizationdb read system.preferences.accounts > /tmp/system.preferences.accounts.plist
        defaults write /tmp/system.preferences.accounts.plist group wheel > /dev/null
        security -q authorizationdb write system.preferences.accounts < /tmp/system.preferences.accounts.plist

        # Prevent time modification.
        security -q authorizationdb read system.preferences.datetime > /tmp/system.preferences.datetime.plist
        defaults write /tmp/system.preferences.datetime.plist group wheel > /dev/null
        security -q authorizationdb write system.preferences.datetime < /tmp/system.preferences.datetime.plist

        # Prevent directory permission modification and root enable.
        security -q authorizationdb read system.services.directory.configure > /tmp/system.services.directory.configure.plist
        defaults write /tmp/system.services.directory.configure.plist group wheel > /dev/null
        security -q authorizationdb write system.services.directory.configure < /tmp/system.services.directory.configure.plist
        security -q authorizationdb read system.services.directory > /tmp/system.services.directory.plist
        defaults write /tmp/system.services.directory.plist group wheel > /dev/null
        security -q authorizationdb write system.services.directory < /tmp/system.services.directory.plist

        echo "> + Complete!" >> /Library/Logs/mac-enforcer.log

        # Flush the DNS cache.
        echo "> Flushing the DNS cache..." >> /Library/Logs/mac-enforcer.log
        killall -HUP mDNSResponder
        echo "> + Complete!" >> /Library/Logs/mac-enforcer.log

        # Insure root is disabled.
        echo "> Locking-down root account..." >> /Library/Logs/mac-enforcer.log
        dscl . delete /Users/root AuthenticationAuthority
        dscl . -create /Users/root UserShell /usr/bin/false
        dscl . -create /Users/root Password '*'
        echo "> + Complete!" >> /Library/Logs/mac-enforcer.log

        echo "> Hour $tm tasks complete!" >> /Library/Logs/mac-enforcer.log
    fi

    # Run one-time tasks.
    if [ "$run_once" == 0 ]
    then
        run_once=1

        # Update hosts.
        if [ -f /etc/hosts ]
        then
            chflags schg /etc/hosts
            chflags uchg /etc/hosts
        fi
        if [ "$dow" == "Monday" ] && (( 10#$tm < 1200 ))
        then
            echo "> Updating hosts file..." >> /Library/Logs/mac-enforcer.log
            if [ -f /etc/hosts ]
            then
                chflags noschg /etc/hosts
                chflags nouchg /etc/hosts
                rm /etc/hosts
            fi
            cp /Library/Scripts/mac-enforcer/hosts_cache.txt /etc/hosts
            cat /Library/Scripts/mac-enforcer/hosts_custom.txt >> /etc/hosts
            chown root:wheel /etc/hosts
            chmod 644 /etc/hosts
            killall -HUP mDNSResponder
            chflags schg /etc/hosts
            chflags uchg /etc/hosts
            echo "> + Complete!" >> /Library/Logs/mac-enforcer.log
        fi

        # Delay to ensure initialization.
        echo "> Waiting for initialization..." >> /Library/Logs/mac-enforcer.log
        sleep 20 > /dev/null
        echo "> + Complete!" >> /Library/Logs/mac-enforcer.log
        echo " " >> /Library/Logs/mac-enforcer.log
    fi

    sleep 1 > /dev/null

done