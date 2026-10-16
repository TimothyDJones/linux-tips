#!/bin/bash

# NOTES:
# This script requires that the following environment variables
# be set *BEFORE* execution:
#   ROOT_PASSWORD - Password to use for root user.
#   USER - Regular user account. But default $USER will be used.
#   PASSWD - Password for the $USER account.
#   USER_EMAIL - E-mail address for SSH key generation.

# Change root user password
ROOT_USER=root
echo -e "$ROOT_PASSWD\n$ROOT_PASSWD" | sudo passwd $ROOT_USER

# Change user user password
echo -e "$PASSWD\n$PASSWD" | sudo passwd $USER

# Allow regular user passwordless root access
su root -c 'echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers'

# Remove some packages that we don't need
sudo apt remove -yy \
  libreoff* \
  firefox* \
  audacio*

# Clean up leftover packages after removal
sudo rm -rf /usr/lib/libreoffice
sudo apt autoremove -f -yy

# Update system
sudo apt update && sudo apt upgrade -yy

# Install important packages
sudo apt install -yy \
  7zip \
  build-essential \
  curl \
  extrepo \
  gdebi \
  geany \
  git \
  openjdk-21-jre \
  python3-pip \
  python3-venv \
  synaptic \
  tmux \
  vim \
  vim-airline \
  vim-airline-themes \
  wget \
  xclip

# Enable Librewolf repo and install
sudo extrepo enable librewolf
sudo apt update && sudo apt install -yy librewolf

# Install NodeJS Version Manager (NVM)
export NVM_VERSION=0.40.8
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash
source ~/.bashrc

# Install Liquid Prompt
export LP_VERSION=2.3.0
curl -o /tmp/liquidprompt.tar.gz -J -L https://downloads.sourceforge.net/liquid-prompt.mirror/liquidprompt-v${LP_VERSION}.tar.gz
cd /tmp
tar -xf /tmp/liquidprompt.tar.gz
mkdir -p $HOME/bin/liquidprompt
cp -R -a /tmp/liquidprompt/* ~/bin/liquidprompt
echo 'source $HOME/bin/liquidprompt/liquidprompt' >> $HOME/.bashrc
source $HOME/.bashrc

# Install Git Basher
export GB_VERSION=3.10.2
curl -o /tmp/gitbasher-${GB_VERSION}.tar.gz -J -L https://github.com/maxbolgarin/gitbasher/archive/refs/tags/v${GB_VERSION}.tar.gz
cd /tmp
tar -xf /tmp/gitbasher-${GB_VERSION}.tar.gz
sudo cp -a /tmp/gitbasher-${GB_VERSION}/dist/gitb /usr/local/bin
sudo chmod a+x /usr/local/bin/gitb

# Generate SSH key
ssh-keygen -t ed25519 -C "${USER_EMAIL}"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
# Copy public key contents to clipboard
xclip -selection c < ~/.ssh/id_ed25519.pub
