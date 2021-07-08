# linux-tips
Collection of tips on Linux (mostly Debian/Ubuntu) helpful to me

## Basic configuration for new Git repository
```bash
# Set user name and e-mail address (required to do 'commit')
git config [--global] user.email "user@domain.com"
git config [--global] user.name "User Name"

# Store/cache password
git config [--global] credential.helper store
git pull

# Set the remote repository (for existing code)
git remote add origin https://github.com/user/repo_name.git
```

## Add <em>existing</em> user to <em>existing</em> group
```bash
sudo usermod -a -G groupnames username
```
`-a` - <em>append</em> groups to group user belongs to (instead of overwrite).  
`groupnames` - a comma-separated (no spaces!) list of group names to add user to.  
User <em>must</em> log out and back in for group membership updates to be applied.  
[Reference](http://askubuntu.com/a/79566)

## Swap the `Caps Lock` and `(Right) Control` keys on keyboard
The level of configurability in Linux is simply amazing.  With the venerable [`xmodmap`](https://linux.die.net/man/1/xmodmap) utility, keyboard remapping is a snap. Just add these lines to your `$HOME/.xmodmap` file to swap the `Caps Lock` and `(Right) Control` keys.
```bash
remove Lock = Caps_Lock
remove Control = Control_R
keysym Control_R = Caps_Lock
keysym Caps_Lock = Control_R
add Lock = Caps_Lock
add Control = Control_R
```

## Enter Unicode characters with keyboard in Linux
In most applications in Linux, including at the command line, to enter a [Unicode](https://www.rapidtables.com/code/text/unicode-characters.html) character, hold down `<LeftCtrl>` and `<Shift>` plus _u_ and enter the 2- or 4-character *hexadecimal* Unicode code.  When you release `<LeftCtrl>` and `<Shift>`, the character will be displayed. For example, to enter superscript 2 (²), which is Unicode 00B2, type `<LeftCtrl>`+`<Shift>`+_u_+B2; for the trademark symbol (™), which is Unicode 2122, type `<LeftCtrl>`+`<Shift>`+_u_+2122. Note that you can use the numeric keys across the top of the keyboard or on the numeric keypad (with NumLock enabled).  
[Reference1](https://twitter.com/brianredbeard/status/1371862052797517825)  
[Reference2](https://old.reddit.com/r/linux/comments/m6dbbm/til_on_linux_one_can_type_arbitrary_unicode/)

## Install packages required to build application from source in Ubuntu/Debian
If you want to build an application from source for a new version of an application that has a Ubuntu/Debian package, you can use the `build-dep` utility to install the required dependencies in one go.
```bash
sudo apt-get build-dep PKG_NAME
```
where `PKG_NAME` is the package name, such as `vim-common`.  
[Reference](https://wiki.debian.org/BuildingTutorial#Get_the_build_dependencies)

## "Safe" alternative to bypassing password prompt for `sudo`
To avoid getting prompted for password when running commands with [`sudo`](https://manpages.ubuntu.com/manpages/precise/en/man8/sudo.8.html), one common option is to append `NOPASSWD:ALL` to your user name in the `/etc/sudoers` file. Obviously, this is a security risk. Instead, you can run the `sudo` command with the `-s` ("session") flag to allow the `sudo` session to be persistent until your close the terminal (end the session). To explicitly end the session run `sudo -k` ("kill").  
[Reference](https://vitux.com/how-to-specify-time-limit-for-a-sudo-session/)

## Upgrade Ubuntu to non-LTS version via command line
By default, most installations of Ubuntu are configured to upgrade only to LTS (long-term support) distribution releases, which come out every two years (e.g., 18.04, 20.04, etc.).  If you want to upgrade your Ubuntu installation to a non-LTS release (e.g., from Bionic Beaver [18.04] to Eoan Ermine [19.10]) you can do so via command line.  Here's how.

### Update current release to latest patches
```bash
sudo apt-get install update-manager-core -y
sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y
```

### Update upgrade manager to `normal` (non-LTS) setting
```bash
sudo sed -i 's/Prompt=lts/Prompt=normal/g' /etc/update-manager/release-upgrades
```

### Change distribution reference to desired version codename* and disable third-party repositories (PPAs)
```bash
sudo sed -i 's/bionic/eoan/g' /etc/apt/sources.list
sudo sed -i 's/^/#/' /etc/apt/sources.list.d/*.list
```
Replace `bionic` and `eoan` above with the current and desired distribution version codenames, respectively, as appropriate.
*See [here](https://en.wikipedia.org/wiki/Ubuntu_version_history) for list of Ubuntu distribution codenames with associated version numbers.

### Run the upgrade, remove unneeded packages, and reboot to complete update
```bash
echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections
sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confnew
sudo apt-get autoremove -f -y && sudo apt-get clean -y
sudo shutdown -r now
```
See [this article](https://unix.stackexchange.com/questions/22820/how-to-make-apt-get-accept-new-config-files-in-an-unattended-install-of-debian-f) for details about forcing use of new/package maintainer's version of configuration files.  For additional details refer to [this article](https://serverfault.com/a/858361).

### Confirm new release version
```bash
lsb_release -a
```

### Re-enable third-party repositories (PPAs) and change them to the new version codename
```bash
sudo sed -i '/deb/s/^#//g' /etc/apt/sources.list.d/*.list
sudo sed -i 's/bionic/eoan/g' /etc/apt/sources.list.d/*.list
sudo apt-get update && sudo apt-get upgrade -y
```
If you get any errors that a repository can't be found (e.g., `The repository 'http://linux.dropbox.com/ubuntu eoan Release' does not have a Release file.`), then you will need to revert these individual repositories to the earlier distribution version codename in `/etc/apt/sources.list.d` directory.

[Reference](https://www.linuxbabe.com/ubuntu/upgrade-ubuntu-18-04-to-ubuntu-19-10-from-command-line)

## Bash script to toggle touchpad on and off
If you use an external mouse with your laptop, you probably want to disable your touchpad when the mouse is plugged in. Here's how to create a simple Bash script to toggle the touchpad on and off.

At the Bash prompt, run this command to list _all_ of your input devices, such as the keyboard, mouse, and touchpad:
```bash
$ xinput
⎡ Virtual core pointer                      	id=2	[master pointer  (3)]
⎜   ↳ Virtual core XTEST pointer              	id=4	[slave  pointer  (2)]
⎜   ↳ USB Optical Mouse                       	id=10	[slave  pointer  (2)]
⎜   ↳ **SynPS/2 Synaptics TouchPad              	id=12**	[slave  pointer  (2)]
```
In this example, the touchpad, has device ID **12**. Next, we check the status (enabled or disabled) for this device:
```bash
$ xinput -list-props 12 | grep "Device Enabled"
	Device Enabled (**116**):	**1**
```
Here, the **1** means that the touchpad is _enabled_. Create a script named `touchpad.sh` with the following contents and replace **12** and **116** with the appropriate values for your machine:
```bash
#!/bin/bash
if xinput list-props **12** | grep "Device Enabled (**116**):.*1" >/dev/null
then
  xinput disable **12**
  notify-send -u low -i mouse "Touchpad disabled"
else
  xinput enable **12**
  notify-send -u low -i mouse "Touchpad enabled"
fi
```
Copy `touchpad.sh` to a directory in your `$PATH` and make it executable (`chmod +x touchpad.sh`). Simply run it anytime that you want to toggle the touchpad on or off.

[Reference](http://tuxdiary.com/2016/08/15/toggle-touchpad-ubuntu-16-04/)

## Disable GPG checking for third-party repositories (PPAs)
When using third-party repositories (PPAs), you typically need to install GPG key. If you have trouble with GPG keys, you can configure the repository, in `/etc/apt/sources.list` or the custom configuration file in `/etc/apt/sources.list.d/` by adding `trusted=yes` or `allow-insecure=yes`. The difference between them is that `allow-insecure=yes` will prompt you before allowing you to install, but `trusted=yes` won't.

For example, here's the setting used with the MongoDB repository:
```bash
deb [ arch=amd64 `allow-insecure=yes ] http://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse
```
[Reference](https://unix.stackexchange.com/questions/198000/bypass-gpg-signature-checks-only-for-a-single-repository)

## Reset 'root' password for MySQL Server (version 8.0+)
If you install [MySQL Server 8.0](https://dev.mysql.com/doc/refman/8.0/en/) or later in Ubuntu without specifying the `root` password, you can set (reset) it as follows.

Run `mysql` utility with `root` account without password:
```bash
sudo mysql
```
(Note: This only works if no `root` password is set.)

At the MySQL prompt, use the [`ALTER USER`](https://dev.mysql.com/doc/refman/8.0/en/alter-user.html) command to set the desired password.  It is important to specify the authentication plugin as [`mysql_native_password`](https://dev.mysql.com/doc/refman/8.0/en/native-pluggable-authentication.html) to allow applications such as [phpMyAdmin](https://www.phpmyadmin.net/) to connect (see also [here](https://github.com/phpmyadmin/phpmyadmin/issues/14220)).
```bash
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'new_root_password';
FLUSH PRIVILEGES;
```

Restart MySQL service:
```bash
sudo systemctl restart mysql
```

You should now be able to log in to MySQL from command prompt with the new password:
```bash
mysql -u root -pnew_root_password
```

[Reference](https://askubuntu.com/questions/766900/mysql-doesnt-ask-for-root-password-when-installing/766908#766908)

## Mount AWS S3 Bucket Using `s3fs`
`s3fs` is a [FUSE](http://manpages.ubuntu.com/manpages/precise/man8/mount.fuse.8.html) [(File System in Userspace)](https://en.wikipedia.org/wiki/Filesystem_in_Userspace) extension which allows you to mount an Amazon Web Services (AWS) S3 bucket as native local file system. In other words, no specialized tools are required.

We will use `s3fs` package from the Ubuntu repositories. You can install `s3fs` by building it from source; see [`s3fs` Github repository](https://github.com/s3fs-fuse/s3fs-fuse) for details.

Switch to the `root` user *before* performing the other steps:
```bash
sudo su -
```

Install `s3fs`:
```bash
apt-get install -y s3fs
```

Create the *system* `s3fs` password file using the appropriate AWS S3 credentials (access key ID and secret access key).
```bash
echo AWS_ACCESS_KEY_ID:AWS_SECRET_ACCESS_KEY > /etc/passwd-s3fs
chmod 600 /etc/passwd-s3fs
```
`/etc/passwd-s3fs` can contain multiple sets of credentials (access key ID and secret access key pair combinations) with each on its own line in the file.

Create file system directories to mount S3 bucket and for caching S3 bucket contents. The cache directory is optional, but will improve performance when using S3 bucket with large number of files.
```bash
mkdir /tmp/cache
mkdir /mnt/s3-bucket
chmod 777 /tmp/cache /mnt/s3-bucket
```

Mount the S3 bucket using `s3fs`. (Note: This mount is temporary/non-persistent. See below for mounting the file system on boot using `/etc/fstab`.)
```bash
s3fs s3-bucket-name /mnt/s3-bucket -o passwd_file=/etc/passwd-s3fs -o allow_other,use_cache=/tmp/cache
```
Replace `s3-bucket-name` with the desired S3 bucket for the credentials specified in `/etc/passwd-s3fs` from above. Note that `rw` means to mount the file system as "read-write" (the default setting); if you want to mount as "read-only", change this to `ro`.

Test the S3 bucket file system mount. You should see a "standard" file system listing. And, of course, you can use GUI file managers by navigating to `/mnt/s3-bucket`.
```bash
ls -lrt /mnt/s3-bucket
```

To mount the S3 bucket as your (non-root) user ID, at a *regular* (non-root) command prompt run `id ${USER}`. You should see something *like*:
```bash
id ${USER}
uid=1000(tim) gid=1000(tim) groups=1000(tim),4(adm),24(cdrom),27(sudo),30(dip),33(www-data),46(plugdev),107(input),121(lpadmin),131(lxd),133(sambashare),998(docker)
```
Use the `uid` and `gid` values above to run `s3fs`:
```bash
s3fs s3-bucket-name /mnt/s3-bucket -o passwd_file=/etc/passwd-s3fs -o allow_other,use_cache=/tmp/cache,uid=1000,umask=077,gid=1000
```
If you get an error about not being allowed to use `allow_other` as regular user, you will need to uncomment the `user_allow_other` line in `/etc/fuse.conf` FUSE configuration file.

To configure your system to automatically ("permanently") mount the S3 bucket when it boots, do the following. (This assumes that you are still logged in as `root` user.)
```bash
echo s3fs#s3-bucket-name /mnt/s3-bucket fuse _netdev,rw,nosuid,nodev,allow_other,nonempty,uid=1000,umask=077,uid=1000 0 0 >> /etc/fstab
```
Mount (re-mount) the file system to ensure that it works properly.
```bash
mount -a
```

That's it! Now you can transparently work with your S3 buckets just like they are local files.


[Reference1](https://sysadminxpert.com/how-to-mount-s3-bucket-on-linux-instance/)  
[Reference2](https://winscp.net/eng/docs/guide_amazon_s3_sftp#mounting)

## Fix HP Pavilion Laptop lockup/freeze problem on idle/inactivity in Linux
Some HP Pavilion laptops experience problems with freezing after inactivity timeouts or other idle conditions. To prevent such problems, some or all of the following items can help prevent such problems.

- Disable power saving features.
- Disable screensaver and screen lock features.
- Add [kernel boot parameters](https://wiki.ubuntu.com/Kernel/KernelBootParameters) to GRUB boot menu options.
	- `noapic` - Disable APIC (Advanced Programmable Interrupt Controller) support.
	- `idle=nomwait` - Disable "mwait" for CPU idle state.
	

[Reference1](https://stackoverflow.com/questions/53001737/what-do-boot-option-noapic-and-noacpi-actually-do)

## Display time and time zone details for system
For a quick check of the time and time zone details of your Linux system, run the _`timedatectl`_ command. It will show you the current local time, UTC time, RTC (real-time clock from BIOS) and the time zone, along with some additional details. The command can also be used to change these settings. See the [_`timedatectl`_](https://man7.org/linux/man-pages/man1/timedatectl.1.html) `man` page for more information.

***

## Show processor architecture information and use in shell script
Many times in a shell script, you may need to differentiate between whether your Linux platform is 32-bit or 64-bit and which processor type/architecture is used. Here are a few commands you can use to get such information.

| Command | Flags | Action | Example Output |
| :------ | :---- | :----- | :------------- |
| `uname` | `-m`  | Display machine hardware name | `x86_64` or `i686`|
| `arch`  |       | Alias for `uname -m` | `x86_64` |
| `dpkg`  | `--print-architecture` | Display machine/platform architecture (Debian/Ubuntu) | `amd64`, `arm64`, `i386` |
| `dpkg-architecture` | `--query DEB_BUILD_ARCH_CPU` | Display machine/platform architecture (Debian/Ubuntu) | `amd64`, `arm64`, `i386` |
| `nproc` |       | Display number of CPU cores | `4` |
| `getconf` | `LONG_BIT` | Displays 32 or 64, depending on address bus | `64` |
| `lscpu` |       | Detailed information about CPU | N/A |
| `lshw`  | `-C CPU` | Summary information about CPU | N/A |

[Reference1](https://www.tecmint.com/check-linux-cpu-information/)  
[Reference2](https://www.linuxtechi.com/server-cpu-architecture-linux/)  
[Reference3](https://stackoverflow.com/questions/45125516/possible-values-for-uname-m/45125525#45125525)

## Tidy up your Linux command line history with `HISTIGNORE`
If you use the Linux command line often, one of the greatest features is the [`history`](https://www.man7.org/linux/man-pages/man3/history.3.html) of commands run. Simply press the up and down arrows to navigate backward and forward through the commands or hit <kbd>Ctrl</kbd>+R to search. However, if you navigate around a lot and list directory contents, your history can filled with extra commands that you aren't likely to want to from history, since they are simple enough to just run again. To prevent history from adding these to your command history, just add the `HISTIGNORE` variable to your `.bashrc` with a list of the commands to ignore separated with colons (`:`). Here's an example:
```bash
HISTIGNORE="ls:ls -lrt:[bf]g:history*:exit:*shutdown*:*reboot*:[ \t]*"
```
In this example, we ignore `ls` by itself and `ls -lrt`, the `bg` and `fg` commands, `exit`, and anything _starting with_ `history`. Likewise, you can see that we've included "dangerous" commands like `shutdown` and `reboot` that we probably don't want to accidentally run when quickly scrolling through a long history list. And, finally, `[ \t]*` means to ignore any command that you enter that starts with a <kbd>Space</kbd> or <kbd>Tab</kbd> so that you can selectively run a command and have it ignored in the history.
