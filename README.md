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

## Install packages required to build application from source
If you want to build an application from source for a new version of an application that has a Ubuntu/Debian package, you can use the `build-dep` utility to install the required dependencies in one go.
```bash
sudo apt-get build-dep PKG_NAME
```
where `PKG_NAME` is the package name, such as `vim-common`.
[Reference](https://wiki.debian.org/BuildingTutorial#Get_the_build_dependencies)

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

### Disable GPG checking for third-party repositories (PPAs)
When using third-party repositories (PPAs), you typically need to install GPG key. If you have trouble with GPG keys, you can configure the repository, in `/etc/apt/sources.list` or the custom configuration file in `/etc/apt/sources.list.d/` by adding `trusted=yes` or `allow-insecure=yes`. The difference between them is that `allow-insecure=yes` will prompt you before allowing you to install, but `trusted=yes` won't.

For example, here's the setting used with the MongoDB repository:
```bash
deb [ arch=amd64 ***allow-insecure=yes*** ] http://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse

```

[Reference](https://unix.stackexchange.com/questions/198000/bypass-gpg-signature-checks-only-for-a-single-repository)
