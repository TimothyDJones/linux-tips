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
