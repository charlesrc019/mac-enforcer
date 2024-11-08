#!/bin/sh

#
#   .SYNOPSIS
#   This script is meant to monitor a masOS computer's usage
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
main_user="charles"
echo "Starting BlockComputerUsage.sh on `date` as `whoami`..." > /Library/Logs/BlockComputerUsage.log
echo " " >> /Library/Logs/BlockComputerUsage.log
run_hourly=0
run_once=0

# Monitor tasks continuously.
while [ 1 ]
do
    dow=$(date +%A)
    tm=$(date +%H%M)

    # Prevent night-time computer usage.
    # blocks:  <9:45am                    >2pm              any Saturday              any Sunday
    if (( 10#$tm < 945 )) || (( 10#$tm >= 1400 )) || [ $dow == "Saturday" ] || [ $dow == "Sunday" ]
    then
        echo "> Shutting down." >> /Library/Logs/BlockComputerUsage.log
        shutdown -h now  >> /Library/Logs/BlockComputerUsage.log
    fi

    # Prevent user from modifying this file, its startup, or hosts.
    [[ $0 = /* ]] && fullpath=$0 || fullpath=$PWD/${0#./}
    chflags schg $fullpath
    chflags uchg $fullpath
    chflags schg /Library/LaunchDaemons/com.user.BlockComputerUsage.plist
    chflags uchg /Library/LaunchDaemons/com.user.BlockComputerUsage.plist
    chflags schg /etc/sudoers
    chflags uchg /etc/sudoers

    # Prevent extra users.
    dscl . list /Users | grep -v "^_" | while read -r line
    do
        if [ "$line" != $main_user ] &&
           [ "$line" != "daemon"   ] &&
           [ "$line" != "nobody"   ] &&
           [ "$line" != "root"     ]
        then
            echo "> Deleting user '$line'." >> /Library/Logs/BlockComputerUsage.log
            dscl . -delete /Users/$line >> /Library/Logs/BlockComputerUsage.log
        fi
    done

    # Prevent extra user folders.
    ls /Users | while read -r line
    do
        if [ "$line" != $main_user   ] &&
           [ "$line" != "Shared"     ] &&
           [ "$line" != ".localized" ]
        then
            echo "> Deleting user folder '$line'." >> /Library/Logs/BlockComputerUsage.log
            rm -rf /Users/$line >> /Library/Logs/BlockComputerUsage.log
        fi
    done

    # Prevent enabling root user.
    if dscl . -read /Users/root Password | grep "\*\*" 
    then
        echo "> Disabling root user." >> /Library/Logs/BlockComputerUsage.log
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
        echo "> Resetting DNS servers." >> /Library/Logs/BlockComputerUsage.log
        networksetup -setdnsservers Wi-Fi 185.228.168.168 185.228.169.168 > /dev/null
        networksetup -setdnsservers Ethernet 185.228.168.168 185.228.169.168 > /dev/null
    fi

    # Prevent unmonitored hosts.
    tmp1=0
    if [ -f /etc/hosts ]
    then
        tmp1=$(wc -l /etc/hosts | awk '{print $1}')
    fi
    if (( 10#$tmp1 < 100 ))
    then
        echo "> Replacing blank hosts file." >> /Library/Logs/BlockComputerUsage.log
        if [ -f /etc/hosts ]
        then
            chflags noschg /etc/hosts
            chflags nouchg /etc/hosts
            rm /etc/hosts
        fi
        cp /Library/Scripts/User/hosts_cache.txt /etc/hosts
        cat /Library/Scripts/User/hosts_custom.txt >> /etc/hosts
        chown root:wheel /etc/hosts
        chmod 644 /etc/hosts
        killall -HUP mDNSResponder
    fi

    # Prevent use of Safari or Directory Utility.
    uid=$(id -u "$main_user")
    launchctl asuser $uid osascript -e "tell application \"Safari\" to quit" > /dev/null
    launchctl asuser $uid osascript -e "tell application \"Directory Utility\" to quit" > /dev/null

    # Run hourly tasks. Also run on script startup.
    if ((( (10#$tm % 100) == 0 )) && (( 10#$run_hourly != 10#$tm ))) || [ $run_once == 0 ]
    then
        run_hourly=$tm

        echo "> Locking system modifications..." >> /Library/Logs/BlockComputerUsage.log

        # Prevent extra user creation.
        security -q authorizationdb read system.preferences.accounts > /tmp/system.preferences.accounts.plist
        defaults write /tmp/system.preferences.accounts.plist group wheel > /dev/null
        security -q authorizationdb write system.preferences.accounts < /tmp/system.preferences.accounts.plist

        # Prevent time modification.
        security -q authorizationdb read system.preferences.datetime > /tmp/system.preferences.datetime.plist
        defaults write /tmp/system.preferences.datetime.plist group wheel > /dev/null
        security -q authorizationdb write system.preferences.datetime < /tmp/system.preferences.datetime.plist

        # Prevent screen recording modification.
        security -q authorizationdb read system.preferences.security > /tmp/system.preferences.security.plist
        defaults write /tmp/system.preferences.security.plist group wheel > /dev/null
        security -q authorizationdb write system.preferences.security < /tmp/system.preferences.security.plist 

        # Prevent directory permission modification and root enable.
        security -q authorizationdb read system.services.directory.configure > /tmp/system.services.directory.configure.plist
        defaults write /tmp/system.services.directory.configure.plist group wheel > /dev/null
        security -q authorizationdb write system.services.directory.configure < /tmp/system.services.directory.configure.plist
        security -q authorizationdb read system.services.directory > /tmp/system.services.directory.plist
        defaults write /tmp/system.services.directory.plist group wheel > /dev/null
        security -q authorizationdb write system.services.directory < /tmp/system.services.directory.plist

        echo "> + Complete!" >> /Library/Logs/BlockComputerUsage.log

        # Flush the DNS cache.
        echo "> Flushing the DNS cache..." >> /Library/Logs/BlockComputerUsage.log
        killall -HUP mDNSResponder
        echo "> + Complete!" >> /Library/Logs/BlockComputerUsage.log

        # Insure root is disabled.
        echo "> Locking-down root account..." >> /Library/Logs/BlockComputerUsage.log
        dscl . delete /Users/root AuthenticationAuthority
        dscl . -create /Users/root UserShell /usr/bin/false
        dscl . -create /Users/root Password '*'
        echo "> + Complete!" >> /Library/Logs/BlockComputerUsage.log

        echo "> Hour $tm tasks complete!" >> /Library/Logs/BlockComputerUsage.log
    fi

    # Run one-time tasks.
    if [ $run_once == 0 ]
    then
        run_once=1

        # Update hosts.
        if [ -f /etc/hosts ]
        then
            chflags schg /etc/hosts
            chflags uchg /etc/hosts
        fi
        if [ $dow == "Monday" ] && (( 10#$tm < 1200 ))
        then
            echo "> Updating hosts file..." >> /Library/Logs/BlockComputerUsage.log
            if [ -f /etc/hosts ]
            then
                chflags noschg /etc/hosts
                chflags nouchg /etc/hosts
                rm /etc/hosts
            fi
            cp /Library/Scripts/User/hosts_cache.txt /etc/hosts
            cat /Library/Scripts/User/hosts_custom.txt >> /etc/hosts
            chown root:wheel /etc/hosts
            chmod 644 /etc/hosts
            killall -HUP mDNSResponder
            echo "> + Complete!" >> /Library/Logs/BlockComputerUsage.log
        fi

        # Delay to ensure initialization.
        echo "> Waiting for initialization..." >> /Library/Logs/BlockComputerUsage.log
        sleep 20 > /dev/null
        echo "> + Complete!" >> /Library/Logs/BlockComputerUsage.log
        echo " " >> /Library/Logs/BlockComputerUsage.log
    fi

    sleep 0.5 > /dev/null

done
