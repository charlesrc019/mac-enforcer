# Mac Usage Enforcer
### Script Overview
`mac-enforcer.sh` is a macOS script designed to monitor and restrict user access, system changes, and certain applications. It runs as a root LaunchDaemon and enforces configurable time-based access limitations, user restrictions, file integrity enforcement, and network security measures to ensure the system remains secure and controlled.

### Features
1. **Time-Based Access Control**:
   - Configurable rules to restrict computer usage during specific hours or days, allowing the system to automatically shut down or restrict access when outside of authorized periods.

2. **File and System Integrity Enforcement**:
   - Uses `chflags` to lock critical system files, preventing unauthorized modifications to key system configurations such as the script itself, LaunchDaemon settings, and important configuration files.

3. **User Management**:
   - Regularly scans and removes any unauthorized or non-designated user accounts, ensuring only approved users have access to the system.

4. **Root Access Restrictions**:
   - Disables root user access to prevent unauthorized privilege escalation or system modifications by disabling the root account and locking down the password.

5. **DNS and Hosts File Management**:
   - Monitors and enforces secure DNS settings, resetting to predefined values if unauthorized changes are detected.
   - Restores and secures the `/etc/hosts` file, preventing unwanted alterations.

6. **Application Blocking**:
   - Automatically closes specific applications (such as web browsers or system utilities) to prevent users from using unapproved programs during restricted times.

7. **Authorization Settings Enforcement**:
   - Restricts access to system preference panes and configurations, ensuring that only authorized users can modify critical system settings related to accounts, time, security, and directory permissions.

8. **Hourly and Startup Maintenance**:
   - Runs periodic checks and maintenance tasks to enforce the system restrictions, including refreshing DNS settings and locking system files.
   - Executes one-time setup tasks on startup, such as restoring configuration files if necessary.

### Installation Instructions
1. **Add as a LaunchDaemon**:
   - Place the script in a desired directory (e.g., `/Library/Scripts/mac-enforcer.sh`).
   - Set up a LaunchDaemon plist (`/Library/LaunchDaemons/com.user.mac-enforcer.plist`) to run the script automatically at startup as root.
   - Ensure that key administrative commands such as `chflags`, `killall`, `su`, and `visudo` are restricted to prevent circumvention.

2. **Configuration**:
   - Modify the `main_user` variable at the beginning of the script to specify the primary user who will have authorized access.

3. **Enable Logging**:
   - The script logs actions and events to `/Library/Logs/mac-enforcer.log`. Ensure the directory is writable by the root user.

### Usage Notes
- To disable the script, remove the associated LaunchDaemon plist file and adjust the `chflags` settings on the script file.
- The script requires root privileges to execute. Unauthorized access attempts are logged for monitoring and troubleshooting.

