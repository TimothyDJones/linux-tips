# linux-tips
Collection of tips on Linux (mostly Debian/Ubuntu) helpful to me

## Basic configuration for new Git repository
```bash
# Set user name and e-mail address (required to do 'commit')
git config [--global] user.email "user@domain.com"
git config [--global] user.name "User Name"

# Set the remote repository (for existing code)
git remote add origin https://github.com/user/repo_name.git
```

## Add <em>existing</em> user to <em>existing</em> group
```bash
sudo usermod -a -G groupnames username
```
`-a` - <em>append</em> groups to group user belongs to (instead of overwrite).  
User <em>must</em> log out and back in for group membership updates to be applied.  
[Reference](http://askubuntu.com/a/79566)
