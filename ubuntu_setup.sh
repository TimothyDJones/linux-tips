#!/bin/bash

function getKernelType() {
	local KERNEL_TYPE

	# Determine if this is 32-bit or 64-bit version of kernel.
	if [[ $(uname -m | grep '64') ]]; then  # Check for 64-bit Linux kernel
		KERNEL_TYPE=amd64
	else    # Otherwise use version for 32-bit kernel
		KERNEL_TYPE=i386
	fi

	echo ${KERNEL_TYPE}
}

## Create a MySQL database.
## $1 (first parameter) is the database name (also used for username and password)
## Assumes that root username and password are root/root.
function mySqlCreateDatabase() {
	if [ "$1" != "" ]
	then
		local DB_NAME=( $1 )
		local DB_USER=( $1 )
		local DB_PASSWORD=( $1 )

		mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
		mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
		mysql -u root -proot -Bse "FLUSH PRIVILEGES;"

		echo "Database '" ${DB_NAME} "' created!"
	else
		echo "No database name specified!"
	fi
}

# Set some parameters for general use
WWW_HOME=/var/www/html


# Add some necessary non-default packages
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get autoremove -f -y
sudo apt-get install -y build-essential dtrx curl wget checkinstall gdebi \
	openjdk-8-jre python-software-properties software-properties-common \
	mc python3-pip

# Allow current user to run 'sudo' without password
# https://phpraxis.wordpress.com/2016/09/27/enable-sudo-without-password-in-ubuntudebian/
# http://stackoverflow.com/a/28382838
echo "${USER}" > /tmp/user.tmp
sudo bash -c 'echo "`cat /tmp/user.tmp` ALL=(ALL) NOPASSWD:ALL" | (EDITOR="tee -a" visudo)'
rm -f /tmp/user.tmp

# Add official Git package repository
sudo apt-add-repository -y ppa:git-core/ppa

# Add PHP 5.6/7.0/7.1 package repository
sudo apt-add-repository -y ppa:ondrej/php

# Add Vim 8.x package repository
# https://itsfoss.com/vim-8-release-install/
sudo apt-add-repository -y ppa:jonathonf/vim
# Add some settings to .bashrc to use Vim instead of Vi
cat >> $HOME/.config/vim_sh_config << EOF
# Enable 256 color support in terminal
export TERM=xterm-256color
# Use Vim instead of Vi, particularly for Git
export VISUAL=vim
export EDITOR=vim
# Make 'vi' a function that calls Vim
vi() {
    vim "$@"
}
EOF
echo 'source $HOME/.config/vim_sh_config' >> $HOME/.bashrc
source $HOME/.bashrc	# Reload Bash configuration

# Add NodeJS package repository
# https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -

# Install NodeJS, Vim 8, and Git
sudo apt-get install -y vim vim-gtk3 vim-common \
	git \
	nodejs

# Install MongoDB from official repository
# https://docs.mongodb.com/manual/tutorial/install-mongodb-on-ubuntu/
APP_NAME=mongodb
APP_VERSION=3.4
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
source /etc/lsb-release
echo "deb [ arch="${KERNEL_TYPE}" ] http://repo.mongodb.org/apt/ubuntu "${DISTRIB_CODENAME}"/mongodb-org/"${APP_VERSION}" multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-${APP_VERSION}.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo service mongod start

# Install PHP 5.6, Apache 2, and MySQL Server
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'  # Set MySQL password to 'root'.
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'
sudo apt-get install -y php5.6-bcmath php5.6-bz2 php5.6-cli php5.6-common php5.6-curl php5.6-gd php5.6-json php5.6-mbstring php5.6-mcrypt php5.6-mysql php5.6-readline php5.6-sqlite3 php5.6-xml php5.6-xsl php5.6-zip php-xdebug \
libapache2-mod-php5.6 libapache2-mod-xsendfile \
mysql-server mysql-workbench mycli

# Enable 'modrewrite' Apache module
sudo a2enmod rewrite
sudo service apache2 restart  ## Alternate command is 'sudo apachectl restart'

# Add current user to 'www-data' group
sudo usermod -a -G www-data ${USER}

# Change owner of /var/www/html directory to www-data
sudo chown -R www-data:www-data ${WWW_HOME}

# Enable PHP 5.6 as default version of PHP (if PHP 7.0+ gets installed, as well).
sudo a2dismod php7.0 ; sudo a2enmod php5.6 ; sudo service apache2 restart ; echo 1 | sudo update-alternatives --config php

# Create simple 'phpinfo' script in main web server directory
# Note: Must create file in /tmp and then move because 'sudo cat...' is allowed.
sudo cat > /tmp/phpinfo.php << EOL
<?php
	phpinfo();
?>
EOL
sudo mv /tmp/phpinfo.php ${WWW_HOME}
sudo chown www-data:www-data ${WWW_HOME}/phpinfo.php

# Disable XDebug on CLI to prevent warnings when installing/running Composer
sudo phpdismod -s cli xdebug

# Install PHP Composer as global utility
php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
sudo php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('/tmp/composer-setup.php');"
rm -f /tmp/composer-setup.php
sudo chmod +x /usr/local/bin/composer
sudo chown -R $USER:$USER $HOME/.composer

# Install latest PhpMyAdmin version via Composer
# https://docs.phpmyadmin.net/en/latest/setup.html#composer
cd ${WWW_HOME}
sudo php /usr/local/bin/composer create-project phpmyadmin/phpmyadmin --repository-url=https://www.phpmyadmin.net/packages.json --no-dev
sudo chown -R www-data:www-data ${WWW_HOME}/phpmyadmin
xdg-open http://localhost/phpmyadmin/setup &
cd $HOME

# Install apt-fast script for speeding up apt-get by downloading
# packages in parallel.
# https://github.com/ilikenwf/apt-fast
sudo add-apt-repository -y ppa:saiarcot895/myppa
sudo apt-get update
sudo apt-get -y install apt-fast

# Install Flatpak sandboxed installer utility from PPA
sudo add-apt-repository -y ppa:alexlarsson/flatpak
sudo apt-get update -y
sudo apt-get install -y flatpak

# Install bash-it script
cd $HOME
wget -O /tmp/bash-it.zip https://github.com/Bash-it/bash-it/archive/master.zip
dtrx -n /tmp/bash-it.zip
mv ./bash-it/bash-it-master $HOME/.bash-it
$HOME/.bash-it/install.sh --silent
source $HOME/.bashrc	# Enable bash-it configuration immediately.
rm -f /tmp/bash-it.zip
rm -rf $HOME/bash-it

# Install LilyTerm terminal
# http://lilyterm.luna.com.tw/
# Ubuntu does not have recent version in packages, so we build from source,
# which requires installation of GTK+2 and other libraries.
APP_NAME=LilyTerm
APP_VERSION=0.9.9.4
APP_EXT=tar.gz
sudo apt-get install -y pkg-config libglib2.0-dev libgtk2.0-dev libvte-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/Tetralet/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
if [[ ! -d "$HOME/.config/autostart" ]]; then
	mkdir -p $HOME/.config/autostart
fi
ln -s /usr/local/share/applications/lilyterm.desktop $HOME/.config/autostart/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Google Go language
APP_NAME=go
APP_VERSION=1.9.2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=386
fi
curl -o /tmp/${APP_NAME}.tar.gz -J -L https://storage.googleapis.com/golang/${APP_NAME}${APP_VERSION}.linux-${ARCH_TYPE}.tar.gz
sudo tar -C /usr/local -xzf /tmp/${APP_NAME}.tar.gz
# Add Go application to $PATH and $GOPATH env variable
echo 'export PATH="$PATH:/usr/local/go/bin"' >> $HOME/.bashrc
echo 'export GOPATH=$HOME/projects/go' >> $HOME/.bashrc
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> $HOME/.bashrc
source $HOME/.bashrc
mkdir -p $HOME/projects/go
rm -rf /tmp/go*
cd $HOME

# Install Lite IDE for Go language development
APP_NAME=LiteIDE
APP_VERSION=x33.1
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
sudo apt-get install -y qt4-default
curl -o /tmp/libpng12-0.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_${KERNEL_TYPE}.deb
sudo gdebi -n libpng12-0.deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION}.${ARCH_TYPE}-qt4.${APP_EXT}
curl -o /tmp/${APP_NAME,,}-system.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION}.${ARCH_TYPE}-qt4-system.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /opt
# Create icon in menus
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=IDE for editing and building projects written in the Go programming language
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/share/${APP_NAME,,}/welcome/images/liteide128.xpm
Type=Application
StartupNotify=false
Terminal=false
Categories=Development;Programming;
Keywords=golang;go;ide;programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/bin/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Firejail and Firetools utilities for running applications
# in isolated memory space.
APP_NAME=firejail
APP_VERSION=0.9.52_1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}   # '-n' is non-interactive mode for gdebi
rm -f /tmp/${APP_NAME}.${APP_EXT}
APP_NAME=firetools
APP_VERSION=0.9.50_1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/firejail/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}   # '-n' is non-interactive mode for gdebi
rm -f /tmp/${APP_NAME}.${APP_EXT}
cd $HOME

# Install Stacer Linux monitoring tool
# Must download specific version, because unable to get 'latest' from Sourceforge to work.
APP_NAME=stacer
APP_VERSION=1.0.8
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}   # '-n' is non-interactive mode for gdebi
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install DBeaver Java database utility
cd $HOME/Downloads
curl -o dbeaver.deb -J -L http://dbeaver.jkiss.org/files/dbeaver-ce_latest_${KERNEL_TYPE}.deb
sudo gdebi -n dbeaver.deb
rm -f dbeaver.deb
sudo apt-get install -y libmysql-java   # Install MySQL JDBC driver
cd $HOME

# Install Linux Brew (similar to MacOS X "Home Brew")
# Ruby *should* already be installed; it gets installed when Vim is installed. But we will install the dependencies, just in case.
# Linux Brew is installed as *user* (not global) application.
sudo apt-get install -y build-essential curl git python-setuptools ruby
cd $HOME/Downloads
wget -O linuxbrew.zip https://github.com/Linuxbrew/brew/archive/master.zip
dtrx -n linuxbrew.zip
mv $HOME/Downloads/linuxbrew/brew-master $HOME/.linuxbrew
echo 'export PATH="$HOME/.linuxbrew/bin:$PATH"' >> $HOME/.bashrc
echo 'export MANPATH="$HOME/.linuxbrew/share/man:$MANPATH"' >> $HOME/.bashrc
echo 'export INFOPATH="$HOME/.linuxbrew/share/info:$INFOPATH"' >> $HOME/.bashrc
source $HOME/.bashrc
rm -rf linuxbrew*
cd $HOME
brew update    # Update the Linuxbrew "formulae" (packages).

# Install Atom editor via PPA
sudo add-apt-repository -y ppa:webupd8team/atom
sudo apt-get update -y
sudo apt-get install -y atom

# Install Vivaldi web browser (stable version)
wget -O /tmp/vivaldi.deb https://downloads.vivaldi.com/stable/vivaldi-stable_1.11.917.39-1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/vivaldi.deb
rm -f /tmp/vivaldi.deb

# Install Cudatext editor from Sourceforge
APP_NAME=cudatext
APP_VERSION=1.39.0.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/release/Linux/${APP_NAME}_${APP_VERSION}_gtk2_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
rm -f /tmp/${APP_NAME}*

# Enable GetDeb repository for your version of Ubuntu
source /etc/os-release   # This config file contains Ubuntu version details.
DEB_STRING='deb http://archive.getdeb.net/ubuntu '${UBUNTU_CODENAME}'-getdeb apps'
sudo echo $DEB_STRING > /etc/apt/sources.list.d/getdeb.list
wget -q -O- http://archive.getdeb.net/getdeb-archive.key | sudo apt-key add -
sudo apt-get update -y

# Install Albert application launcher from PPA.
# http://sourcedigit.com/22129-linux-quick-launcher-ubuntu-albert-best-linux-launcher/
sudo add-apt-repository -y ppa:nilarimogard/webupd8
sudo apt-get update -y
sudo apt-get install -y albert
ln -s /usr/share/applications/albert.desktop $HOME/.config/autostart/  # Create link to autostart Albert on startup


# Install KSnip screenshot utility from Sourceforge
APP_NAME=KSnip
APP_VERSION=1.4.0
APP_EXT=tar.gz
sudo apt-get install -y cmake extra-cmake-modules libqt5x11extras5-dev # Install required packages
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/ksnip*

# Install CopyQ clipboard manager from Sourceforge
APP_NAME=copyq
APP_VERSION=3.0.3
source /etc/os-release
curl -o /tmp/${APP_NAME}.deb -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}/Linux/${APP_NAME}_${APP_VERSION}_Ubuntu_${VERSION_ID}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME}.deb
sudo ln -s /usr/local/share/applications/${APP_NAME}.desktop $HOME/.config/autostart/  # Configure CopyQ to autostart on system launch
rm -f /tmp/${APP_NAME}*

# Install Steel Bank Common Lisp (SBLC) from Sourceforge
APP_NAME=sbcl
APP_VERSION=1.4.4
APP_EXT=tar.bz2
sudo apt-get install -y sbcl   # Current packaged version of SBCL required to build the updated version from source
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}-source.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sh make.sh
INSTALL_DIR=/usr/local sudo sh install.sh
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Otter Browser from Sourceforge (from source)
APP_NAME=otter-browser
APP_VERSION=0.9.95
APP_EXT=tar.bz2
sudo apt-get install -y qt5-default libqt5multimedia5 qtmultimedia5-dev libqt5xmlpatterns5-dev libqt5webkit5-dev   # Qt5 development packages needed to build from source
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install MyNotes simple "sticky notes" tool
APP_NAME=mynotes
APP_VERSION=2.3.1
APP_EXT=deb
# Install python-ewmh package from Zesty Zebra distribution.
curl -o /tmp/python3-ewmh_0.1.5-1_all.deb -J -L http://ftp.osuosl.org/pub/ubuntu/pool/universe/p/python-ewmh/python3-ewmh_0.1.5-1_all.deb
sudo gdebi -n /tmp/python3-ewmh_0.1.5-1_all.deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/my-notes/${APP_NAME}_${APP_VERSION}-1_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/python3-ewmh*
rm -rf /tmp/${APP_NAME}*

# Install Plank dock, if not installed.
PLANK_EXE=/usr/bin/plank
if [ ! -f "$PLANK_EXE" ]; then
	sudo apt-get install -y plank
fi

# Install FUSE driver for Google Drive from PPA and mount local folder to your account.
# http://www.techrepublic.com/article/how-to-mount-your-google-drive-on-linux-with-google-drive-ocamlfuse/
sudo add-apt-repository -y ppa:alessandro-strada/ppa
sudo apt-get update -y
sudo apt-get install -y google-drive-ocamlfuse
google-drive-ocamlfuse   # This will launch browser window prompting you to allow access to Google Drive.
mkdir $HOME/google-drive   # Create directory to use as mount point for Google Drive.
google-drive-ocamlfuse $HOME/google-drive  # Mount Google Drive to folder.

# Install MuPDF PDF viewer from source.
# Install pre-requisite development packages.
APP_NAME=MuPDF
APP_VERSION=1.12.0
APP_EXT=tar.xz
sudo apt-get install -y libjbig2dec0-dev libfreetype6-dev libftgl-dev libjpeg-dev libopenjp2-7-dev zlib1g-dev xserver-xorg-dev mesa-common-dev libgl1-mesa-dev libxcursor-dev libxrandr-dev libxinerama-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://mupdf.com/downloads/${APP_NAME,,}-${APP_VERSION}-source.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-source
make && sudo make prefix=/usr/local install
# Create icon in menus
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Minimalist PDF reader/viewer
GenericName=PDF Reader
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}-gl
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Office;
Keywords=PDF;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /usr/local/bin/mupdf-gl /usr/local/bin/mupdf
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install tke text editor
APP_NAME=tke
APP_VERSION=3.4
APP_EXT=tgz
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls  # Install required packages
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sudo tclsh8.6 install.tcl
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Goto shell utility
wget -O /tmp/goto.zip https://github.com/Fakerr/goto/archive/master.zip
cd /tmp
dtrx -n /tmp/goto.zip
cd /tmp/goto/goto-master
mv goto.sh $HOME/.local/
echo "if [[ -s "${HOME}/.local/goto.sh" ]]; then" >> $HOME/.bashrc
echo "    source ${HOME}/.local/goto.sh" >> $HOME/.bashrc
echo "fi" >> $HOME/.bashrc
source $HOME/.local/goto.sh
cd $HOME
rm -rf /tmp/goto*

# Install Free42 HP-42S calculator simulator
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	FREE42_FILE_NAME=Free42Linux-64bit.tgz
else    # Otherwise use version for 32-bit kernel
	FREE42_FILE_NAME=Free42Linux-32bit.tgz
fi
wget -O /tmp/Free42Linux.tgz http://thomasokken.com/free42/download/${FREE42_FILE_NAME}
cd /tmp
dtrx -n /tmp/Free42Linux.tgz
cd /tmp/Free42Linux
sudo mv /tmp/Free42Linux/free42* /usr/local/bin
sudo ln -s /usr/local/bin/free42dec /usr/local/bin/free42
# Create icon in menus
cat > /tmp/free42.desktop << EOF
[Desktop Entry]
Name=Free42
Comment=RPN (postfix) Scientific Calculator
GenericName=Calculator
Exec=/usr/local/bin/free42
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Development
Keywords=calculator;rpn;
EOF
sudo mv /tmp/free42.desktop /usr/share/applications/
cd $HOME
rm -rf /temp/Free42*

# Modify keyboard mapping to swap Caps Lock and (Right) Control keys
# See https://github.com/501st-alpha1/scott-script/blob/master/newsystem
echo "! Swap Caps Lock and (Right) Control
remove Lock = Caps_Lock
remove Control = Control_R
keysym Control_R = Caps_Lock
keysym Caps_Lock = Control_R
add Lock = Caps_Lock
add Control = Control_R
" > $HOME/.xmodmap

# Install JOE (Joe's Own Editor) text editor from source
APP_NAME=joe
APP_VERSION=4.6
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-editor/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install KeePassXC password manager from source
APP_NAME=keepassxc
APP_VERSION=2.2.4
APP_EXT=tar.xz
curl -o /tmp/libgcrypt20-dev.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libg/libgcrypt20/libgcrypt20-dev_1.7.8-2ubuntu1_amd64.deb
curl -o /tmp/libgcrypt20.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libg/libgcrypt20/libgcrypt20_1.7.8-2ubuntu1_amd64.deb
sudo gdebi -n /tmp/libgcrypt20.deb
sudo gdebi -n /tmp/libgcrypt20-dev.deb
sudo apt-get install -y libcrypto++-dev libxi-dev libmicrohttpd-dev libxtst-dev qttools5-dev-tools cmake
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/keepassxreboot/${APP_NAME}/releases/download/${APP_VERSION}/${APP_NAME}-${APP_VERSION}-src.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
mkdir build && cd build
cmake .. -DWITH_TESTS=OFF && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install NewBreeze file manager
# Install from packages for 64-bit Linux
if $(uname -m | grep '64'); then 
	curl -o /tmp/NewBreeze-common.deb -J -L https://github.com/marcusbritanicus/NewBreeze/releases/download/v3-alpha2/newbreeze-common_3.0.0_amd64.deb
	curl -o /tmp/NewBreeze.deb -J -L https://github.com/marcusbritanicus/NewBreeze/releases/download/v3-alpha2/newbreeze_3.0.0_amd64.deb
	curl -o /tmp/NewBreeze-plugins.deb -J -L https://github.com/marcusbritanicus/NewBreeze/releases/download/v3-alpha2/newbreeze-plugins_3.0.0a_amd64.deb
	sudo gdebi -n /tmp/NewBreeze-common.deb
	sudo gdebi -n /tmp/NewBreeze.deb
	sudo gdebi -n /tmp/NewBreeze-plugins.deb
else # Install from source for 32-bit Linux
	sudo apt-get install -y libmagic-dev zlib1g-dev liblzma-dev libbz2-dev libarchive-dev xdg-utils libpoppler-qt5-dev libsource-highlight-dev libpoppler-qt5-dev libdjvulibre-dev
	curl -o /tmp/NewBreeze.tar.gz -J -L https://sourceforge.net/projects/newbreeze/files/v3-alpha2/NewBreeze%20v3%20Alpha%202.tar.gz/download
	cd /tmp
	dtrx -n NewBreeze.tar.gz
	cd /tmp/NewBreeze/*NewBreeze*
	qmake && make && sudo make install
fi
cd $HOME
rm -rf /tmp/NewBreeze*

# Install Miniflux browser-based RSS reader
# Requires PHP and SQLite.
curl -o /tmp/miniflux.tar.gz -J -L https://github.com/miniflux/miniflux/archive/v1.2.2.tar.gz
cd /tmp
dtrx -n /tmp/miniflux.tar.gz
cd /tmp/miniflux
sudo mv /tmp/miniflux/miniflux-1.2.2 ${WWW_HOME}/miniflux
sudo chown -R www-data:www-data ${WWW_HOME}
sudo chmod -R 777 ${WWW_HOME}/miniflux/data
xdg-open "http://localhost/miniflux"  # Open main page in default browser
cd $HOME
rm -rf /tmp/miniflux*

# Install QGIS (a.k.a. Quantum GIS) from Ubuntu PPA
# (Used PPA, because unable to install from QGIS official packages.)
sudo apt-add-repository -y ppa:ubuntugis/ubuntugis-unstable
sudo apt-get update
sudo apt-get install -y qgis python-qgis qgis-provider-grass postgis
sudo apt-get autoremove -y -f

# Install Playbox games from Sourceforge
curl -o /tmp/playbox.zip -J -L https://pilotfiber.dl.sourceforge.net/project/playbox/6/playbox-1.6.3.linux.gtk.x86_64.zip
cd /tmp
dtrx -n /tmp/playbox.zip
cd /tmp/playbox
sudo mv ./playbox /opt
sudo ln -s /opt/playbox/playbox /usr/local/bin/playbox
cd $HOME
rm -rf /tmp/playbox*

# Install WP-34s calculator from Sourceforge
if $(uname -m | grep '64'); then
	curl -o /tmp/wp-34s-emulator.tgz -J -L https://cytranet.dl.sourceforge.net/project/wp34s/emulator/wp-34s-emulator-linux64.tgz
else
	curl -o /tmp/wp-34s-emulator.tgz -J -L https://cytranet.dl.sourceforge.net/project/wp34s/emulator/wp-34s-emulator-linux.tgz
fi
cd /tmp
dtrx -n /tmp/wp-34s-emulator.tgz
cd /tmp/wp-34s-emulator
sudo mv wp-34s /opt
sudo ln -s /opt/wp-34s/WP-34s /usr/local/bin/wp34s
# Create icon in menus
cat > /tmp/wp34s.desktop << EOF
[Desktop Entry]
Name=WP-34s
Comment=RPN (postfix) Scientific Calculator
GenericName=Calculator
Exec=/opt/wp-34s/WP-34s
Icon=/opt/wp-34s/wp34s-logo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Development
Keywords=calculator;rpn;
EOF
sudo mv /tmp/wp34s.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/wp-34s-emulator*

# Install YouTube-DL-PyTK video downloader from Sourceforge
curl -o /tmp/youtube-dl-pytk.tar -J -L https://superb-sea2.dl.sourceforge.net/project/youtube-dl-gtk/17.4.16/YouTube-DL-PyTK_17.4.16.tar
cd /tmp
dtrx -n /tmp/youtube-dl-pytk.tar
cd /tmp/youtube-dl-pytk/YouTube-DL-PyTK
sudo ./install.sh
cd $HOME
rm -rf /tmp/youtube-dl-pytk*

# Install WCD chdir utility from source
APP_NAME=wcd
APP_VERSION=6.0.1
APP_EXT=tar.gz
sudo apt-get install -y libncursesw5-dev groff sed build-essential ghostscript po4a
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}/src
make all CURSES=ncursesw
sudo make PREFIX=/usr/local strip install
sudo ln -s /usr/local/bin/${APP_NAME}.exe /usr/bin/${APP_NAME}.exe	 # Create link so that shell integration works properly.
sudo make install-profile DOTWCD=1     # Set up shell integration and store configuration files under $HOME/.wcd.
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install BeeBEEP LAN messenger from Sourceforge
APP_NAME=beebeep
APP_VERSION=4.0.0
DL_BASE_FILE_NAME=beebeep-${APP_VERSION}-qt4-${KERNEL_VERSION}
sudo apt-get install -y qt4-default libqt4-xml libxcb-screensaver0 libavahi-compat-libdnssd1 libphonon4 libhunspell-dev phonon-backend-gstreamer
curl -o /tmp/${APP_NAME}.tar.gz -J -L https://superb-sea2.dl.sourceforge.net/project/beebeep/Linux/${DL_FILE_NAME}.tar.gz
cd /tmp
dtrx -n ${APP_NAME}.tar.gz
cd /tmp/${APP_NAME}
mv ${DL_BASE_FILE_NAME} ${APP_NAME}
sudo mv ${APP_NAME} /opt
sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
cd $HOME

# Install tmux terminal multiplexer from source
APP_NAME=tmux
APP_VERSION=2.4
sudo apt-get install -y libevent-dev libncurses5-dev
curl -o /tmp/${APP_NAME}.tar.gz -J -L https://github.com/tmux/tmux/releases/download/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.tar.gz
cd /tmp
dtrx -n ${APP_NAME}.tar.gz
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/tmux*

# Install Ranger CLI file manager from source
APP_NAME=ranger
APP_VERSION=1.8.1
curl -o /tmp/${APP_NAME}.tar.gz -J -L http://nongnu.org/ranger/ranger-stable.tar.gz
cd /tmp
dtrx -n ${APP_NAME}.tar.gz
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Coypu To Do list
APP_NAME=coypu
APP_VERSION=1.3.0
curl -o /tmp/${APP_NAME}.deb -J -L https://download.coypu.co/download/linux_deb
cd /tmp
sudo gdebi -n coypu.deb
cd $HOME
rm -f /tmp/coypu*

# Install calc shell calculator from source
APP_NAME=calc
APP_VERSION=2.12.6.0
APP_EXT=tar.bz2
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
make && make install
cd $HOME
rm -rf /tmp/${APP_NAME}*


# Install Leanote Desktop app
APP_NAME=leanote-desktop
APP_VERSION=2.6
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
curl -o /tmp/${APP_NAME}.zip -J -L https://superb-dca2.dl.sourceforge.net/project/${APP_NAME}-app/${APP_VERSION}/${APP_NAME}-linux-${ARCH_TYPE}-v${APP_VERSION}.zip
cd /tmp
dtrx -n ${APP_NAME}.zip
# cd /tmp/${APP_NAME}/${APP_NAME}-linux-${ARCH_TYPE}-v${APP_VERSION}
sudo mv ${APP_NAME} /opt
sudo ln -s /opt/${APP_NAME}/Leanote /usr/local/bin/leanote
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Leanote
Comment=Full-featured PIM built with Electron/Atom
GenericName=PIM
Exec=/opt/${APP_NAME}/Leanote
Icon=/opt/${APP_NAME}/leanote.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;
Keywords=pim;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/

# Install QXmlEdit from source via Sourceforge
APP_NAME=QXmlEdit
APP_VERSION=0.9.9.2
APP_EXT=tgz
sudo apt-get install -y libqt5xmlpatterns5-dev libqt5svg5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-src.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME}.desktop /usr/share/applications/${APP_NAME}.desktop
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Idiomind flash card utility
APP_NAME=idiomind
APP_VERSION=0.2.9
curl -o /tmp/${APP_NAME}.deb -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/${APP_VERSION}/${APP_NAME}_${APP_VERSION}_all.deb
sudo gdebi -n /tmp/${APP_NAME}.deb   # '-n' is non-interactive mode for gdebi
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Jailer Java database utility
APP_NAME=jailer
APP_VERSION=7.6.1
curl -o /tmp/${APP_NAME}.zip -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}.zip
cd /tmp
dtrx -n ${APP_NAME}.zip
sudo mv ${APP_NAME} /opt
# sudo ln -s /opt/${APP_NAME}/${APP_NAME}.sh /usr/local/bin/${APP_NAME}
echo "export PATH=$PATH:/opt/${APP_NAME}" >> $HOME/.bashrc
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ZinjaI C++ IDE
APP_NAME=zinjai
APP_VERSION=20171016
APP_EXT=tgz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=l64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=l32
fi
sudo apt-get install -y gdb
curl -o /tmp/${APP_NAME}.tgz -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${ARCH_TYPE}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo mv ${APP_NAME} /opt
# sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=ZinjaI
Comment=C++ IDE
GenericName=C++ IDE
Exec=/opt/${APP_NAME}/${APP_NAME}
Icon=/opt/${APP_NAME}/imgs/zinjai.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development
Keywords=ide;programming;cpp;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
/opt/${APP_NAME}/${APP_NAME} &
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install PhpWiki
# Reference:  https://hostpresto.com/community/tutorials/install-and-configure-phpwiki-on-ubuntu-16-04/
APP_NAME=phpwiki
APP_VERSION=1.5.5
DB_NAME=phpwikidb
DB_USER=phpwiki
DB_PASSWORD=phpwiki
curl -o /tmp/${APP_NAME}.zip -J -L https://versaweb.dl.sourceforge.net/project/${APP_NAME}/PhpWiki%201.5%20%28current%29/${APP_NAME}-${APP_VERSION}.zip
cd /tmp
dtrx -n ${APP_NAME}.zip
cd ${APP_NAME}
mv ${APP_NAME}-${APP_VERSION} ${APP_NAME}
sudo mv ${APP_NAME} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
# sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
# Create configuration file for PhpWiki
cat > ./config.ini << EOF
WIKI_NAME = phpWiki
ADMIN_USER = admin
ADMIN_PASSWD = admin
ENCRYPTED_PASSWD = false
ENABLE_REVERSE_DNS = true
ZIPDUMP_AUTH = false
ENABLE_RAW_HTML = true
ENABLE_RAW_HTML_LOCKEDONLY = true


EOF
xdg-open http://localhost/${APP_NAME}/setup &
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install PWman shell-based password manager
APP_NAME=pwman
APP_VERSION=0.4.5
curl -o /tmp/${APP_NAME}.deb -J -L https://pilotfiber.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}_${APP_VERSION}-1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME}.deb
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Sorter utility for automatic file organization by type
APP_NAME=sorter
APP_VERSION=2.0.1
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	curl -o /tmp/${APP_NAME}.tar.gz -J -L https://cytranet.dl.sourceforge.net/project/file-${APP_NAME}/v${APP_VERSION}/Sorter_${APP_VERSION}_Ubuntu16.04_x64.tar.gz
	dtrx -n ${APP_NAME}.tar.gz
	cd /tmp/${APP_NAME}
	curl -o ./${APP_NAME}.png -J -L https://sourceforge.net/p/file-sorter/code/ci/master/tree/assets/icon.png?format=raw
	sudo mv ${APP_NAME} /opt
	sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
	# Create icon in menus
	cat > /tmp/${APP_NAME}.desktop << EOF
	[Desktop Entry]
	Name=${APP_NAME}
	Comment=Utility to automatically sort files by type
	GenericName=${APP_NAME}
	Exec=/opt/${APP_NAME}/${APP_NAME}
	Icon=/opt/${APP_NAME}/${APP_NAME}.png
	Type=Application
	StartupNotify=true
	Terminal=false
	Categories=Utility;
	Keywords=file_management;
	EOF
	sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
	cd $HOME
	rm -rf /tmp/${APP_NAME}*
else    # Otherwise use version for 32-bit kernel
	echo "Sorry...  No 32-bit version of '${APP_NAME}' available."
fi

# Install xosview X11 performance meter
APP_NAME=xosview
APP_VERSION=2-2.2.3
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://superb-sea2.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}${APP_VERSION}
./configure && make && sudo make install
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=xosview2
Comment=X11 Performance Meter
GenericName=X11 Performance Meter
Exec=/usr/local/bin/xosview2
#Icon=/opt/wp-34s/wp34s-logo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Development
Keywords=meter;monitor;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
ln -s /usr/share/applications/${APP_NAME}.desktop $HOME/.config/autostart/  # Create link to autostart xosview on startup

# Install File Rally MRU list utility for all folders
APP_NAME=FileRally
APP_VERSION=v1.3
curl -o /tmp/${APP_NAME,,}.tar.gz -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME,,}/${APP_NAME}.${APP_VERSION}.tar.gz
cd /tmp
dtrx -n ${APP_NAME,,}.tar.gz
sudo mv ${APP_NAME,,} /opt
# Create icon in menus
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=MRU list of all folders
GenericName=MRU list of all folders
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
Icon=/opt/${APP_NAME,,}/${APP_NAME}Icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Development
Keywords=mru;monitor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
ln -s /usr/share/applications/${APP_NAME,,}.desktop $HOME/.config/autostart/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Madedit-Mod text editor from Sourceforge
APP_NAME=madedit-mod
APP_VERSION=0.4.11-1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}_Ubuntu16.04.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install IT-Edit (Integrated Terminal Editor)
APP_NAME=it-edit
APP_VERSION=3.0
# Enable GNOME 3 PPAs to get latest versions of dependent packages: 
sudo add-apt-repository -y ppa:gnome3-team/gnome3-staging
sudo add-apt-repository -y ppa:gnome3-team/gnome3
sudo apt-get update && sudo apt-get upgrade -y
curl -o /tmp/${APP_NAME}.deb -J -L http://www.open-source-projects.net/Downloads/${APP_NAME}-${APP_VERSION}_noarch.deb
cd /tmp
sudo gdebi -n /tmp/${APP_NAME}.deb
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Chirp Twitter client (64-bit ONLY)
APP_NAME=chirp
curl -o /tmp/${APP_NAME}.zip -J -L https://file-fevwnujbqw.now.sh/Chirp-linux-x64.zip
cd /tmp
dtrx -n ${APP_NAME}.zip
cd /tmp/${APP_NAME}
mv Chirp-linux-x64 ${APP_NAME}
sudo mv ${APP_NAME} /opt
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Chirp
Comment=Twitter client
GenericName=Twitter client
Exec=/opt/${APP_NAME}/Chirp
Icon=/opt/${APP_NAME}/resources/app/icon/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Network;
Keywords=twitter;messenger;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME}/Chirp /usr/local/bin/chirp
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Peg Solitaire game
APP_NAME=peg-solitaire
APP_VERSION=2.2-1
curl -o /tmp/${APP_NAME}.deb -J -L https://pilotfiber.dl.sourceforge.net/project/peg-solitaire/version%202.2%20%28June%2C%202017%29/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.deb
cd /tmp
sudo gdebi -n ${APP_NAME}.deb
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install QuiteRSS RSS reader from PPA
APP_NAME=quiterss
sudo apt-add-repository -y ppa:quiterss/quiterss
sudo apt-get update
sudo apt-get install -y quiterss

# Install Makagiga Java-based PIM/RSS feed reader
APP_NAME=makagiga
APP_VERSION=5.8.3-1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Eternal Terminal SSH client via PPA
# Install dependencies
sudo apt-get install -y libboost-dev libsodium-dev libncurses5-dev libprotobuf-dev protobuf-compiler cmake libgoogle-glog-dev libgflags-dev unzip wget
sudo apt-add-repository -y ppa:jgmath2000/et
sudo apt-get update
sudo apt-get install -y et

# Install Gantt Project project management tool
APP_NAME=ganttproject
APP_VERSION=2.8.5-r2179-1
curl -o /tmp/${APP_NAME}.deb -J -L https://dl.ganttproject.biz/${APP_NAME}-2.8.5/${APP_NAME}_${APP_VERSION}_all.deb
cd /tmp
sudo gdebi -n ${APP_NAME}.deb
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install HTTP Test Tool (httest) from source
APP_NAME=httest
APP_VERSION_MAJOR=2.4
APP_VERSION_MINOR=23
APP_EXT=tar.gz
sudo apt-get install -y libapr1-dev libaprutil1-dev libpcre3-dev help2man
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/htt/${APP_NAME}-${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}
# Due to path for PCRE header file on Ubuntu,
# we have to update the source files for the #include
# directory for the header file.
cd src
sed -i 's@<pcre/pcre.h>@<pcre.h>@g' *
cd ..
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ubunsys installer/tweaker
APP_NAME=ubunsys
APP_VERSION=2017.12.24
APP_EXT=deb
source /etc/os-release   # This config file contains Ubuntu version details.
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://versaweb.dl.sourceforge.net/project/${APP_NAME}/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}_${VERSION_ID}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Jarun utilities from PPA: googler, Buku, and nnn
sudo add-apt-repository -y ppa:twodopeshaggy/jarun
sudo apt-get update
sudo apt-get install -y buku nnn googler

# Install bvi plus hex editor from source
APP_NAME=bviplus
APP_VERSION=1.0
APP_EXT=tgz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://managedway.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Skychart planetarium package from Sourceforge
APP_NAME=skychart
APP_VERSION_MAJOR=4.1
APP_VERSION_MINOR=3727
APP_EXT=deb
# libpasastro (Pascal astronomical library) is dependency for Skychart.
curl -o /tmp/libpasastro.deb -J -L https://superb-sea2.dl.sourceforge.net/project/libpasastro/version_1.1-20/libpasastro_1.1-20_${KERNEL_TYPE}.deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}_${APP_VERSION_MAJOR}-${APP_VERSION_MINOR}_${KERNEL_TYPE}.deb
cd /tmp
sudo gdebi -n libpasastro.deb
sudo gdebi -n ${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/libpasastro.* /tmp/${APP_NAME}*

# Install Qt Bitcoin Trader from source
APP_NAME=QtBitcoinTrader
APP_VERSION=1.40.00
APP_EXT=tar.gz
# Install package dependencies
sudo apt-get install -y g++ libssl-dev libglu1-mesa-dev qt5-qmake qtscript5-dev qtmultimedia5-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://svwh.dl.sourceforge.net/project/bitcointrader/SRC/${APP_NAME}-${APP_VERSION}.${APP_EXT}
export QT_SELECT=5		# Set Qt version 5 as active
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}/src
qmake QtBitcoinTrader_Desktop.pro
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Bash Snippets (tiny shell scripts for various functions, such as
# weather, stock prices, etc.)
APP_NAME=Bash-Snippets
APP_VERSION=1.7.0
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://codeload.github.com/alexanderepstein/${APP_NAME,,}/${APP_EXT}/v${APP_VERSION}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sudo ./install.sh currency
sudo ./install.sh stocks
sudo ./install.sh weather
sudo ./install.sh crypt
sudo ./install.sh geo
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Tagstoo file tag manager
APP_NAME=Tagstoo
APP_VERSION=1.9.1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://ayera.dl.sourceforge.net/project/${APP_NAME,,}/${APP_NAME}%20${APP_VERSION}%20${ARCH_TYPE}/${APP_NAME}_${APP_VERSION}_${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo mv ${APP_NAME} /opt
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Tagstoo
Comment=File tag manager
GenericName=Tagstoo
Exec=/opt/${APP_NAME}/${APP_NAME}
#Icon=/opt/${APP_NAME}/share/${APP_NAME}/welcome/images/liteide128.xpm
Type=Application
StartupNotify=false
Terminal=false
Categories=Accessories;System;
Keywords=tag;tagging;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Shiki shell-based Wikipedia reader
APP_NAME=shiki
APP_VERSION=1.1
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/jorvi/${APP_NAME}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sudo mv ${APP_NAME}.sh /usr/local/bin
echo 'source "/usr/local/bin/${APP_NAME}.sh"' >> $HOME/.bashrc
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Qalculate desktop calculator application from source
# http://qalculate.github.io/
APP_NAME=qalculate
APP_VERSION=0.9.12
APP_EXT=tar.gz
# Install dependencies
sudo apt-get install -y libcln-dev gnuplot-x11 gvfs libxml2-dev libgtk-3-dev
curl -o /tmp/lib${APP_NAME}.${APP_EXT} -J -L http://cfhcable.dl.sourceforge.net/project/${APP_NAME}/lib${APP_NAME}-${APP_VERSION}.${APP_EXT}
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L http://cfhcable.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}-gtk-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n lib${APP_NAME}.${APP_EXT}
cd /tmp/lib${APP_NAME}/lib${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-gtk-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install PuTTY SSH client from source.
# http://www.chiark.greenend.org.uk/~sgtatham/putty/
APP_NAME=putty
APP_VERSION=0.70
APP_EXT=tar.gz
# Install dependencies
sudo apt-get install -y libxml2-dev libgtk-3-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://the.earth.li/~sgtatham/${APP_NAME}/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
# Build and copy PNG icons
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}/icons
make
sudo cp *-16*.png /usr/local/share/icons/hicolor/16x16/apps
sudo cp *-32*.png /usr/local/share/icons/hicolor/32x32/apps
sudo cp *-48*.png /usr/local/share/icons/hicolor/48x48/apps
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=PuTTY
Comment=Popular SSH client
GenericName=PuTTY
Exec=putty
Icon=/usr/local/share/icons/hicolor/32x32/apps/putty-32.png
Type=Application
StartupNotify=false
Terminal=false
Categories=Accessories;System;
Keywords=ssh;terminal;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Calibre ebook reader and converter
sudo -v && wget -nv -O- https://download.calibre-ebook.com/linux-installer.py | sudo python -c "import sys; main=lambda:sys.stderr.write('Download failed\n'); exec(sys.stdin.read()); main()"

# Install WhipFTP client from package
APP_NAME=whipftp
APP_VERSION=3.1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://phoenixnap.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install XML Tree Editor from Debian package
APP_NAME=xmltreeedit
APP_VERSION=0.1.0.32
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}or/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
cd /tmp
sudo gdebi -n ${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Qiks LAN messenger from Debian package
APP_NAME=qiks
APP_VERSION=1.0
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L http://cfhcable.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
sudo gdebi -n ${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install vifm file manager from source
APP_NAME=vifm
APP_VERSION=0.9.1
APP_EXT=tar.bz2
sudo apt-get install -y libncursesw5-dev
curl -o /tmp/${APP_NAME}-${APP_VERSION}.${APP_EXT} -J -L https://ayera.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd ${APP_NAME}-${APP_VERSION}
./configure && make && make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install 4Pane file manager from package
APP_NAME=4pane
APP_VERSION=5.0
APP_EXT=deb
source /etc/lsb-release
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L http://cfhcable.dl.sourceforge.net/project/fourpane/${APP_VERSION}/ubuntu%20and%20derivatives/${APP_NAME}_${APP_VERSION}-1unofficial.${DISTRIB_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Tad Data Viewer from package (64-bit only)
APP_NAME=tad
APP_VERSION=0.8.5
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/antonycourtney/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_amd64.${APP_EXT}
	sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
	cd $HOME
	rm -rf /tmp/${APP_NAME}*
fi

# Install AVFS virtual file system
APP_NAME=avfs
APP_VERSION=1.0.5
APP_EXT=tar.bz2
sudo apt-get install -y libfuse-dev libarchive-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://versaweb.dl.sourceforge.net/project/avf/${APP_NAME}/1.0.5/${APP_NAME}-${APP_VERSION}.${APP_EXT}
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Worker File Manager (For AVFS support install AVFS above.)
APP_NAME=worker
APP_VERSION=3.14.0
APP_EXT=tar.bz2
sudo apt-get install -y liblua5.3-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://versaweb.dl.sourceforge.net/project/workerfm/workerfm/3.11.0/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && make install
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Worker File Manager
Comment=Simple canonical file manager
GenericName=Worker
Exec=worker
Icon=/usr/local/share/pixmaps/WorkerIcon.xpm
Type=Application
StartupNotify=false
Terminal=false
Categories=Accessories;System;
Keywords=file manager;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install PythonQt Python binding for Qt (required for ScreenCloud)
APP_NAME=libpythonqt-qt5
APP_VERSION=3.0-1
APP_EXT=deb
source /etc/lsb-release
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L http://ftp.gwdg.de/pub/opensuse/repositories/home:/olav-st/x${DISTRIB_ID}_${DISTRIB_RELEASE}/${KERNEL_TYPE}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ScreenCloud screen capture utility from Debian package
APP_NAME=screencloud
APP_VERSION=1.3.0
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://pilotfiber.dl.sourceforge.net/project/${APP_NAME}/${APP_VERSION}/linux/${APP_NAME}_${APP_VERSION}-1qt5_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Neofetch shell script system information tool
APP_NAME=neofetch
APP_VERSION=3.3.0
APP_EXT=tar.gz
# Install dependencies
sudo apt-get install -y imagemagick curl 
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/dylanaraps/${APP_NAME}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sudo make PREFIX=/usr/local install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Digital Clock 4
APP_NAME=digital_clock_4
APP_VERSION=4.7.0
APP_EXT=tar.xz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://iweb.dl.sourceforge.net/project/digitalclock4/${APP_VERSION}/${APP_NAME}-linux_${ARCH_TYPE}.tar.xz
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}
mv Digital\ Clock\ 4/ ${APP_NAME}
sudo mv ${APP_NAME} /opt
sudo cp /opt/${APP_NAME}/digital_clock.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME}/digital_clock /usr/local/bin/digital_clock
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Oprofile task/process profiler from source
APP_NAME=oprofile
APP_VERSION=1.2.0
APP_EXT=tar.gz
sudo apt-get install -y libpopt-dev binutils-dev libiberty-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://sourceforge.net/projects/${APP_NAME}/files/latest/download
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
sudo addgroup oprofile
sudo /usr/sbin/useradd -p $(openssl passwd -1 oprofile) oprofile  # Add special account for profiler.
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install HTTraQt web scraper tool from source
APP_NAME=httraqt
APP_VERSION=1.4.9
APP_EXT=tar.gz
sudo apt-get install -y libhttrack-dev  # Install HTTrack dependency
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://sourceforge.net/projects/${APP_NAME}/files/latest/download
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./clean.sh
mkdir -p build && cd build && cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Brave web browser from package
APP_NAME=brave
APP_VERSION=0.19.5
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}-browser.mirror/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install reCsvEditor CSV editor
APP_NAME=reCsvEditor
APP_VERSION=0.98.3
APP_EXT=7z
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L http://cfhcable.dl.sourceforge.net/project/${APP_NAME,,}/${APP_NAME}/Version_${APP_VERSION}/${APP_NAME}_Installer_${APP_VERSION}.jar.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo java -jar /tmp/${APP_NAME}/${APP_NAME}_Installer_${APP_VERSION}.jar  # Launches GUI installer
sudo ln -s /usr/local/RecordEdit/reCsvEd/bin/runCsvEditor.sh /usr/local/bin/recsveditor
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ZenTao project management tool from package
APP_NAME=ZenTaoPMS
APP_VERSION=9.8.1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/zentao/${APP_NAME}_${APP_VERSION}_1_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install FastoNoSql GUI for NoSQL DBs from package
APP_NAME=fastonosql
APP_VERSION=1.6.0
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}-x86_64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf ${APP_NAME}*

# Install BoostNote notepad/PIM from package
APP_NAME=boostnote
APP_VERSION=0.8.20
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/BoostIO/boost-releases/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf ${APP_NAME}*

# Install Red Notebook notepad from source
APP_NAME=rednotebook
APP_VERSION=2.3
APP_EXT=tar.gz
sudo apt-get install -y python3-enchant gir1.2-webkit2-4.0 python3-pip python3-yaml  # Install dependencies
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
sudo pip3 install .
sudo cp ./rednotebook/images/rednotebook-icon/rn-48.png /usr/local/share/pixmaps/rednotebook-48.png
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Red Notebook
Comment=Basic notepad/PIM with Markdown support
GenericName=Notebook
Exec=rednotebook
Icon=/usr/local/share/pixmaps/rednotebook-48.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=Journal;Diary;Notes;Notebook;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install LIOS (Linux Intelligent OCR Solution) from package
APP_NAME=lios
APP_VERSION=2.5
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf ${APP_NAME}*

# Install SysCheck system profiler utility
APP_NAME=SysCheck
APP_VERSION=1.1.11
APP_EXT=zip
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/syschecksoftware/${APP_NAME}-v${APP_VERSION}-lite.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}
mv ${APP_NAME}-v${APP_VERSION}-lite ${APP_NAME,,} 
sudo mv ${APP_NAME,,} /opt
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install GeoServer Java-based mapping/GIS server
APP_NAME=geoserver
APP_VERSION=2.12.2
APP_EXT=zip
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}-bin.${APP_EXT}
cd /tmp

# Install Super Productivity To Do List and task manager from package
APP_NAME=superProductivity
APP_VERSION=1.3.4
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/super-productivity/${APP_NAME}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf ${APP_NAME}*

# Install exa, a replacement for 'ls' command
APP_NAME=exa
APP_VERSION=0.8.0
APP_EXT=zip
# Dependency on libhttp-parser2.1 below is needed due to problem noted
# on Github:  https://github.com/ogham/exa/issues/194
sudo apt-get install -y libhttp-parser2.1
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/ogham/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}-linux-x86_64-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
sudo mv /tmp/${APP_NAME}/${APP_NAME}-linux-x86_64 /usr/local/bin/exa
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install KLatexFormula from source
APP_NAME=klatexformula
APP_VERSION=4.0.0
APP_EXT=tar.bz2
sudo apt-get install -y libqt5x11extras5-dev qttools5-dev qttools5-dev-tools
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Psi XMPP messenger from source
APP_NAME=psi
APP_VERSION=1.3
APP_EXT=tar.xz
sudo apt-get install -y libqca2-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure --prefix=/usr/local/psi && make && sudo make install
sudo ln -s /usr/local/psi/bin/psi /usr/local/bin/psi
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Read the Bible from source
APP_NAME=Bible
APP_VERSION=6.3.6
APP_EXT=tar.xz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/readthebible/${APP_NAME}${APP_VERSION}-64bit.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
sudo mv ${APP_NAME} /opt
sudo ln -s /opt/${APP_NAME}/Bible6 /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Sidu database web GUI
APP_NAME=sidu
APP_VERSION=55
APP_EXT=zip
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}
sudo mv ${APP_NAME}${APP_VERSION} ${WWW_HOME}/${APP_NAME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Tilix (formerly Terminix) terminal emulator from PPA
# https://gnunn1.github.io/tilix-web/ 
sudo add-apt-repository -y ppa:webupd8team/terminix
sudo apt-get update
sudo apt-get install -y tilix

# Install Visual Studio Code editor from package
# https://code.visualstudio.com/docs/setup/linux
curl -o /tmp/vscode.deb -J -L https://go.microsoft.com/fwlink/?LinkID=760868
sudo gdebi -n /tmp/vscode.deb
cd $HOME
rm -rf /tmp/vscode*

# Install LTerm terminal emulator from source
APP_NAME=lterm
APP_VERSION=1.5.0
APP_EXT=tar.gz
sudo apt-get install -y libvte-2.91-dev libssl-dev libssh-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=LTerm
Comment=Terminal Emulator
GenericName=Terminal Emulator
Exec=${APP_NAME}
Icon=/usr/local/share/${APP_NAME}/img/main_icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Terminal;Shell;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Add debrepo repository to available repositories
source /etc/os-release   # This config file contains Ubuntu version details.
DEB_STRING='deb http://downloads.sourceforge.net/project/debrepo '${UBUNTU_CODENAME}' main'
echo $DEB_STRING >> /tmp/debrepo.list
DEB_STRING='deb-src http://downloads.sourceforge.net/project/debrepo '${UBUNTU_CODENAME}' main'
sudo echo $DEB_STRING >> /tmp/debrepo.list
sudo mv /tmp/debrepo.list /etc/apt/sources.list.d
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 172E9B0B
sudo apt-get update -y

# Install TUTOS project management tool
APP_NAME=TUTOS
APP_VERSION=1.12.20160813
APP_EXT=tar.bz2
DB_NAME=tutosdb
DB_USER=tutos
DB_PASSWORD=tutos
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-php-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /usr/share
sudo cp /usr/share/${APP_NAME,,}/php/config_default.pinc /usr/share/${APP_NAME,,}/php/config.php
sudo cp /usr/share/${APP_NAME,,}/apache.conf /etc/apache2/sites-available/tutos.conf
sudo a2ensite tutos.conf
sudo service apache2 restart
sudo chown -R www-data:www-data /usr/share/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"

# Install Webtareas project management tool
APP_NAME=webTareas
APP_VERSION=1.12p4
APP_EXT=zip
DB_NAME=webtareas
DB_USER=webtareas
DB_PASSWORD=webtareas
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R +w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/webtareas/installation/setup.php &

# Install JoPro productivity and office suite
APP_NAME=jopro
APP_VERSION=N/A
APP_EXT=sh
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-linux.${APP_EXT}
sudo sh /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Turtl secure, encrypted Evernote alternative
APP_NAME=turtl
APP_VERSION=0.6.4
APP_EXT=tar.bz2
# Determine if this is 32-bit or 64-bit version of kernel.
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	KERNEL_ARCH=64
else    # Otherwise use version for 32-bit kernel
	KERNEL_ARCH=32
fi
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://turtlapp.com/releases/desktop/${APP_NAME}-linux${KERNEL_ARCH}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
sudo sh /tmp/${APP_NAME}/${APP_NAME}-linux${KERNEL_ARCH}/install.sh
sudo chmod -R 777 /opt/turtl/turtl
sudo ln -s /opt/turtl/turtl/turtl /usr/local/bin/turtl
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install WebCollab web-based project management tool
APP_NAME=webcollab
APP_VERSION=3.45
APP_EXT=tar.gz
DB_NAME=webcollab
DB_USER=webcollab
DB_PASSWORD=webcollab
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo mv ${APP_NAME}-${APP_VERSION} ${APP_NAME}
sudo mv ${APP_NAME} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
sudo chmod 666 ${WWW_HOME}/${APP_NAME}/config/config.php
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
mysql --host=localhost --user=webcollab --password=webcollab webcollab < ${WWW_HOME}/${APP_NAME}/db/schema_mysql_innodb.sql
xdg-open http://localhost/${APP_NAME}/setup.php &

# Install ProjeQtor web-based project management tool
APP_NAME=projeqtor
APP_VERSION=6.5.5
APP_EXT=zip
DB_NAME=projeqtor
DB_USER=projeqtor
DB_PASSWORD=projeqtor
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/projectorria/${APP_NAME}V${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/ &

# Install kgclock desktop clock
APP_NAME=kgclock
APP_VERSION=1.2-1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*
kgclock &

# Install uGet GUI download manager
APP_NAME=uget
APP_VERSION=2.0.10
APP_EXT=deb
source /etc/os-release   # This config file contains Ubuntu version details.
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/urlget/${APP_NAME}_${APP_VERSION}-0ubuntu0+1~${UBUNTU_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Akiee Markdown-based task manager/to do list application
APP_NAME=akiee
APP_VERSION=0.0.4
APP_EXT=deb
KERNEL_TYPE=$(getKernelType)
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/rockiger/${APP_NAME}-release/raw/linux-release/dist/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Xiphos Bible study tool from PPA
sudo add-apt-repository -y ppa:unit193/crosswire
sudo apt-get update -y
sudo apt-get install -y xiphos

# Install Roamer text-based file manager
APP_NAME=roamer
APP_VERSION=0.2.0
APP_ACCT=abaldwin88
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -Lk https://github.com/${APP_ACCT}/${APP_NAME}/tarball/v${APP_VERSION}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/*${APP_NAME}*
sudo python3 setup.py install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Hyper JS/HTML/CSS Terminal 
APP_NAME=hyper
APP_VERSION=2.0.0-canary.8
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/hyper.mirror/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install QOwnNotes from PPA
sudo add-apt-repository -y ppa:pbek/qownnotes
sudo apt-get update -y
sudo apt-get install -y qownnotes

# Install Tiki Wiki CMS/groupware
APP_NAME=tiki
APP_VERSION=18.0
APP_EXT=tar.gz
DB_NAME=tikiwiki
DB_USER=tikiwiki
DB_PASSWORD=tikiwiki
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/tikiwiki/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo mv /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION} ${WWW_HOME}/${APP_NAME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/tiki-install.php &

# Install EU-Commander Tcl/Tk file manager
APP_NAME=eu-comm
APP_VERSION=0.119
APP_EXT=tar.gz
sudo apt-get install -y bwidget tk-table tcl8.6
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/eu-commander/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo mv ${APP_NAME} /opt
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=EU-Commander
Comment=Tcl/Tk File Manager
GenericName=File Manager
Exec=tclsh8.6 /opt/${APP_NAME}/${APP_NAME}.tcl
Icon=/opt/${APP_NAME}/themes/default/wicon.xbm
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Wcalc CLI calculator from source
APP_NAME=wcalc
APP_VERSION=2.5
APP_EXT=tar.bz2
sudo apt-get install -y libmpfr-dev libgmp-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/w-calc/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Eric Python IDE
APP_NAME=eric
APP_VERSION=6-18.02
APP_EXT=tar.gz
sudo apt-get install -y python3-pyqt5 python3-pyqt5.qsci python3-pyqt5.qtsvg python3-pyqt5.qtsql
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/eric-ide/${APP_NAME}${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}${APP_VERSION}
sudo python3 ./install.py
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Finanx 12c HP-12c financial calculator emulator
APP_NAME=finanx
APP_VERSION=12c-0.2.1
APP_EXT=zip
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/finanx/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
mv /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION} /tmp/${APP_NAME}/${APP_NAME}
cd /tmp/${APP_NAME}
sudo mv ${APP_NAME} /opt
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Finanx 12c
Comment=HP-12c Financial Calculator Emulator
GenericName=Financial Calculator
Exec=/opt/${APP_NAME}/${APP_NAME}.sh
#Icon=/opt/${APP_NAME}/themes/default/wicon.xbm
Type=Application
StartupNotify=true
Terminal=true
Categories=Accessories;System;
Keywords=Finance;Calculator;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install PivotX weblog platform
APP_NAME=pivotx
APP_VERSION=2.3.11
APP_EXT=zip
DB_NAME=pivotx
DB_USER=pivotx
DB_PASSWORD=pivotx
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/pivot-weblog/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME,,}/images/ ${WWW_HOME}/${APP_NAME,,}/pivotx/db/ ${WWW_HOME}/${APP_NAME,,}/pivotx/templates
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install Swiss File Knife (SFK) shell file utility
APP_NAME=sfk
APP_VERSION=189
APP_EXT=exe
	if [[ $(uname -m | grep '64') ]]; then  # Check for 64-bit Linux kernel
		ARCH_TYPE=linux-64
	else    # Otherwise use version for 32-bit kernel
		ARCH_TYPE=linux
	fi
curl -o /tmp/${APP_NAME} -J -L https://downloads.sourceforge.net/swissfileknife/${APP_NAME}${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
sudo chmod a+x /tmp/${APP_NAME}
sudo mv /tmp/${APP_NAME} /usr/local/bin

# Install Freeplane mind-mapping tool from package
APP_NAME=freeplane
APP_VERSION=1.6.13
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}~upstream-1_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install HyperJump Bash bookmark tool
APP_NAME=hyperjump
APP_VERSION=
APP_EXT=
sudo apt-get install -y dialog
curl -o /tmp/${APP_NAME} -J -L https://github.com/x0054/${APP_NAME}/raw/master/${APP_NAME}
mv /tmp/${APP_NAME} $HOME/bin/${APP_NAME}
echo '## Load HyperJump Bash bookmark tool' >> $HOME/.bashrc
echo 'source $HOME/bin/'${APP_NAME} >> $HOME/.bashrc
source $HOME/bin/${APP_NAME}	# Activate HyperJump immediately

# Install trolCommander (muCommander) file manager
APP_NAME=trolcommander
APP_VERSION=0_9_9
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/trol73/mucommander/releases/download/v0.9.9/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}
mv trolCommander-${APP_VERSION} ${APP_NAME}
sudo mv ${APP_NAME} /opt
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=trolCommander
Comment=trolCommander (muCommander) Java File Manager
GenericName=File Manager
Exec=/opt/${APP_NAME}/${APP_NAME}.sh
#Icon=/opt/${APP_NAME}/themes/default/wicon.xbm
Type=Application
StartupNotify=true
Terminal=true
Categories=Accessories;System;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME}/${APP_NAME}.sh /usr/local/bin/${APP_NAME}

# Install Feng Office
APP_NAME=fengoffice
APP_VERSION=3.5.1.5
APP_EXT=zip
DB_NAME=fengoffice
DB_USER=fengoffice
DB_PASSWORD=fengoffice
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/opengoo/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME,,}/cache/ ${WWW_HOME}/${APP_NAME,,}/config/ ${WWW_HOME}/${APP_NAME,,}/tmp/ ${WWW_HOME}/${APP_NAME,,}/upload/
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/public/install &

# Install CheckMails system tray new email notification tool from package
APP_NAME=checkmails
APP_VERSION=1.1.4-2
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install jEdit Java text editor from package
APP_NAME=jedit
APP_VERSION=5.4.0
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Franz messenger consolidator tool
APP_NAME=Franz
APP_VERSION=4.0.4
APP_EXT=tgz
	if [[ $(uname -m | grep '64') ]]; then  # Check for 64-bit Linux kernel
		ARCH_TYPE=x64
	else    # Otherwise use version for 32-bit kernel
		ARCH_TYPE=ia32
	fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/meetfranz/franz-app/releases/download/${APP_VERSION}/${APP_NAME}-linux-${ARCH_TYPE}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv franz /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Franz
Comment=Cross-platform message consolidation tool
GenericName=Messenger
Exec=/opt/${APP_NAME,,}/${APP_NAME}
#Icon=/opt/${APP_NAME}/themes/default/wicon.xbm
Type=Application
StartupNotify=true
Terminal=true
Categories=Accessories;Internet;
Keywords=Messenger;Chat;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Sciter Notes notepad utility
APP_NAME=sciter-notes
APP_VERSION=N/A
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://notes.sciter.com/distributions/${APP_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv bin.gtk ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Sciter Notes
Comment=Cross-platform notepad with capability to sync among devices
GenericName=Notepad
Exec=/opt/${APP_NAME,,}/notes
#Icon=/opt/${APP_NAME}/themes/default/wicon.xbm
Type=Application
StartupNotify=true
Terminal=true
Categories=Accessories;System;
Keywords=Notepad;Collaboration;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/notes /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Leo editor/IDE/PIM
APP_NAME=Leo
APP_VERSION=5.7b1
APP_EXT=zip
sudo apt-get install -y python3-pyqt5
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
python3 /opt/${APP_NAME,,}/launchLeo.py
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Leo Editor
Comment=Cross-platform text edtior/IDE/PIM
GenericName=IDE
Exec=python3 /opt/${APP_NAME,,}/launchLeo.py
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}/Icons/LeoApp.ico
Type=Application
StartupNotify=true
Terminal=true
Categories=Programming;Development;
Keywords=Editor;IDE;Python;PIM
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install bed (Binary Editor) from source
APP_NAME=bed
APP_VERSION=2.27.2
APP_EXT=tgz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/binaryeditor/${APP_NAME}-${APP_VERSION}.src.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Saga GIS application from source
APP_NAME=saga
APP_VERSION=6.2.0
APP_EXT=tar.gz
sudo apt-get install -y libwxgtk3.0-dev python-wxgtk3.0 postgresql-server-dev-all libgdal-dev libpqxx-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/saga-gis/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Group-Office web-based office suite (manual installation)
APP_NAME=groupoffice
APP_VERSION=6.2.82
APP_EXT=tar.gz
DB_NAME=${APP_NAME}
DB_USER=${APP_NAME}
DB_PASSWORD=${APP_NAME}
sudo apt-get install -y libwbxml2-utils tnef
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/group-office/${APP_NAME}-com-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}-com-${APP_VERSION} ${APP_NAME}
sudo mv ${APP_NAME} ${WWW_HOME}
cd $HOME
rm -rf /tmp/${APP_NAME}*
sudo touch ${WWW_HOME}/${APP_NAME}/config.php
sudo mkdir -p /home/${APP_NAME}
sudo mkdir -p /tmp/${APP_NAME}
sudo chmod -R 0777 /home/${APP_NAME} /tmp/${APP_NAME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME} /home/${APP_NAME} /tmp/${APP_NAME}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/ &

# Install ZenTao project management suite (manual installation)
APP_NAME=zentao
APP_VERSION=9.6.2_1
APP_EXT=zip
DB_NAME=${APP_NAME}
DB_USER=${APP_NAME}
DB_PASSWORD=${APP_NAME}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/ZenTaoPMS_${APP_VERSION}_all.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}pms ${APP_NAME}
sudo mv ${APP_NAME} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost/${APP_NAME,,}/www/index.php &

# Install Brackets text editor from package
APP_NAME=Brackets
APP_VERSION=1.12
APP_EXT=deb
	if [[ $(uname -m | grep '64') ]]; then  # Check for 64-bit Linux kernel
		ARCH_TYPE=64-bit
	else    # Otherwise use version for 32-bit kernel
		ARCH_TYPE=32-bit
	fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${APP_NAME}.Release.${APP_VERSION}.${ARCH_TYPE}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Worker File Manager from source
APP_NAME=worker
APP_VERSION=3.12.0
APP_EXT=tar.bz2
sudo apt-get install -y libdbus-glib-1-dev libmagic-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}fm/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CuteMarkEd Qt Markdown editor from source
APP_NAME=CuteMarkEd
APP_VERSION=0.11.3
APP_EXT=tar.gz
sudo apt-get install -y libqt5webkit5-dev qttools5-dev-tools qt5-default discount libmarkdown2-dev libhunspell-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/cloose/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
qmake && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Scilab math toolkit
APP_NAME=scilab
APP_VERSION=6.0.0
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i686
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.scilab.org/download/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.bin.linux-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}-${APP_VERSION} ${APP_NAME}
sudo mv ${APP_NAME} /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Scilab
Comment=Cross-platform IDE for math
GenericName=Scilab
Exec=/opt/${APP_NAME,,}/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME}/share/icons/hicolor/32x32/apps/scilab.png
Type=Application
StartupNotify=true
Terminal=true
Categories=Programming;Development;Science
Keywords=Math;Programming;Data;Science
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/bin/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install EeeWeather desktop weather widget from package
APP_NAME=eeeweather
APP_VERSION=0.71-1
APP_EXT=deb
KERNEL_TYPE=getKernelType()
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install XSchem circuit schematic editor from source
APP_NAME=xschem
APP_VERSION=2.4.4
APP_EXT=tar.gz
sudo apt-get install -y bison flex libxpm-dev libx11-dev tcl8.6-dev tk8.6-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}/src
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QPDF PDF utility from source
APP_NAME=qpdf
APP_VERSION=7.1.1
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Griffon multi-language IDE from source
APP_NAME=griffon
APP_VERSION=1.8.4
APP_EXT=tar.gz
sudo apt-get install -y vte-2.91-dev webkitgtk-3.0-dev gtksourceview-3.0-dev libgtk-3-dev libnotify-dev scons
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/griffonide/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
sudo ./install-griffon
sudo cp ./pixmaps/griffon_icon.png /usr/share/pixmaps
sudo cp ./${APP_NAME}.desktop /usr/local/share/applications
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}

# Install Collabtive project management suite (manual installation)
APP_NAME=Collabtive
APP_VERSION=31
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}
#mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
mkdir -p ./${APP_NAME,,}/templates_c
chmod 777 ./${APP_NAME,,}/config/standard/config.php ./${APP_NAME,,}/files ./${APP_NAME,,}/templates_c ./${APP_NAME,,}/templates
sudo mv ${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost/${APP_NAME,,}/install.php &

# Install Doogie Chromium-based browser with tree-style pages
APP_NAME=doogie
APP_VERSION=0.6.0
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/cretz/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}-${APP_VERSION}-linux64.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME} /opt
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install qdPM Web-Based Project Management Tool (manual installation)
APP_NAME=qdPM
APP_VERSION=9.0
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}
#mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv ${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost/${APP_NAME,,}/install/index.php &

# Install DK Tools system utility from source
APP_NAME=dktools
APP_VERSION=4.11.2
APP_EXT=tar.gz
KERNEL_TYPE=getKernelType()
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
sudo dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo chown -R ${USER}:${USER} /tmp/${APP_NAME,,}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Task Coach to do list manager from package
APP_NAME=taskcoach
APP_VERSION=1.4.3-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Agilefant Web-Based Project Management Tool (manual installation)
# https://github.com/Agilefant/agilefant/wiki/Agilefant-installation-guide
APP_NAME=agilefant
APP_VERSION=3.5.4
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
sudo apt-get install -y tomcat8 tomcat8-admin
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}
#mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,}.war /var/lib/tomcat8/webapps
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
sudo service tomcat8 restart
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost:8080/${APP_NAME,,}/ &

# Install Squirrel SQL Java database client utility
APP_NAME=squirrel-sql
APP_VERSION=3.8.1
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-standard.${APP_EXT}
sudo java -jar /tmp/${APP_NAME,,}.${APP_EXT}
sudo ln -s /usr/local/${APP_NAME,,}/${APP_NAME,,}.sh /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Only Office Desktop Editor from package
APP_NAME=onlyoffice-desktopeditors
APP_VERSION=4.8
APP_EXT=deb
source /etc/lsb-release
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://sourceforge.net/projects/teamlab/files/ONLYOFFICE_DesktopEditors/v${APP_VERSION}/ubuntu/${DISTRIB_RELEASE:0:2}/${APP_NAME}_${KERNEL_TYPE}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Beige UML editor
APP_NAME=beige-uml
APP_VERSION=16Aug2017
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://sourceforge.net/projects/beigeuml/files/${APP_VERSION}/${APP_NAME}-swing-jar-with-dependencies.jar
sudo mkdir /opt/${APP_NAME}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Beige UML
Comment=Java-based UML diagram editor
GenericName=Beige UML
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development
Keywords=Programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Upterm terminal/shell built with Electron (AppImage)
APP_NAME=upterm
APP_VERSION=0.4.1
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/railsware/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}-${APP_VERSION}-${ARCH_TYPE}-linux.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME}
sudo mv /tmp/${APP_NAME}.${APP_EXT} /opt/${APP_NAME}
sudo chmod +x /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Upterm
Comment=Electron-based terminal/shell
GenericName=Beige UML
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;Accessories;System
Keywords=Terminal;Shell;IDE
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CopyMastro file move/copy utility
APP_NAME=CopyMastro
APP_VERSION=2.1.4
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-qt5-${KERNEL_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
mv ${APP_NAME,,}* ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=File copy/move utility
GenericName=${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/${APP_NAME}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Copy;File;Utilities;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Printed Circuit Board Layout Tool
APP_NAME=pcb
APP_VERSION=4.1.0
APP_EXT=tar.gz
sudo apt-get install -y intltool libgtkglext1-dev libgd-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Organize My Files file management utility
APP_NAME=Organize-My-Files
APP_VERSION=2.1.1
APP_EXT=appimage
sudo apt-get install -y intltool libgtkglext1-dev libgd-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Agora Project groupware application (manual installation)
APP_NAME=agora_project
APP_VERSION=3.3.5
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/agora-project/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}
#mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv ${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install Strong Java Chess Engine (SJCE) graphical chess tool
APP_NAME=SJCE
APP_VERSION=14-11-17
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L  https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_bin.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}
#mv ${APP_NAME}_${APP_VERSION}_bin ${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_bin /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Strong Java Chess Engine (SJCE)
Comment=Java-based graphical chess tool
GenericName=SJCE
Exec=/opt/${APP_NAME,,}/${APP_NAME}_run_linux.sh
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Education;
Keywords=Chess;Java;Games;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Stellarium astronomy utility from PPA
sudo apt-add-repository -y ppa:stellarium/stellarium-releases
sudo apt-get update
sudo apt-get install -y stellarium

# Install EGroupware PHP-based groupware from package
APP_NAME=egroupware
APP_VERSION=
APP_EXT=
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
source /etc/lsb-release
wget -nv https://download.opensuse.org/repositories/server:eGroupWare/xUbuntu_${DISTRIB_RELEASE}/Release.key -O /tmp/Release.key
sudo apt-key add - < /tmp/Release.key
sudo apt-get update
sudo sh -c "echo 'deb http://download.opensuse.org/repositories/server:/eGroupWare/xUbuntu_"${DISTRIB_RELEASE}"/ /' > /etc/apt/sources.list.d/egroupware-epl.list"
sudo apt-get update
sudo apt-get install -y ${APP_NAME}-epl
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install clib package manager for C language from Github source
APP_NAME=clib
APP_VERSION=
APP_EXT=
sudo apt-get install -y libcurl4-gnutls-dev -qq
git clone https://github.com/clibs/${APP_NAME}.git /tmp/${APP_NAME}
cd /tmp/${APP_NAME}
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Newsboat command-line RSS reader (Newsbeuter replacements) from source
APP_NAME=newsboat
APP_VERSION=2.10.1
APP_EXT=tar.gz
sudo apt-get install -y libcurl4-gnutls-dev libstfl-dev pkg-config libxml2-dev libjson-c-dev libjson0-dev -qq
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/archive/r${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-r${APP_VERSION}
./config.sh && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Tiny Scan Java-based disk usage utility
APP_NAME=TinyScan
APP_VERSION=7.3
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based disk usage utility
GenericName=${APP_NAME}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Disk;System;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Shufti simple PyQt image viewer from source
APP_NAME=shufti
APP_VERSION=2.3
APP_EXT=tar.gz
sudo apt install -y python-pyqt5 python-pyqt5.qtsql -qq
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/danboid/${APP_NAME}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Simple PyQt image viewer
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME}/${APP_NAME}.py
Icon=/opt/${APP_NAME}/${APP_NAME}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;Graphics;
Keywords=Graphics;Image;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME}/${APP_NAME}.py /usr/local/bin/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Monitorix system monitoring utility from package
APP_NAME=monitorix
APP_VERSION=3.9.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.{APP_NAME,,}.org/{APP_NAME,,}_{APP_VERSION}-izzy1_all.deb
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Notes note-taking application from package
APP_NAME=notes
APP_VERSION=1.0.0
APP_EXT=deb
source /etc/lsb-release
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}-${DISTRIB_CODENAME}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Freemind Java-based mind mapping application
APP_NAME=freemind
APP_VERSION=1.1.0_Beta_2
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-bin-max-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=FreeMind
Comment=Java-based mind mapping application
GenericName=FreeMind
Exec=sh /opt/${APP_NAME,,}/${APP_NAME,,}.sh
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Graphics;Office;
Keywords=Mind;Mapping;Productivity;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Treeline tree-structured notepad
APP_NAME=TreeLine
APP_VERSION=2.9.0
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}
sudo python3 /tmp/${APP_NAME,,}/${APP_NAME}/install.py
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based mind mapping application
GenericName=${APP_NAME}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/icons/treeline/toolbar/32x32/treelogo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=Notes;Productivity;Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Micro terminal-based text editor
APP_NAME=micro
APP_VERSION=1.3.3
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/zyedidia/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION} /opt/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Bishop Java-based chess application
APP_NAME=bishop
APP_VERSION=1_0_0
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}chess/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Bishop Chess
Comment=Java-based chess game
GenericName=Chess
Exec=sh /opt/${APP_NAME,,}/${APP_NAME,,}.sh
Icon=/opt/${APP_NAME,,}/graphics/icon/icon_48.png
Path=/opt/${APP_NAME,,}
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;
Keywords=Games;Chess;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,}.sh /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Smuxi IRC/Twitter/Jabbr/XMPP client from PPA
sudo add-apt-repository -y ppa:meebey/smuxi-stable
sudo apt-get update
sudo apt-get install -y smuxi

# Install Textadept minimalist cross-platform text editor
APP_NAME=textadept
APP_VERSION=9.6
APP_EXT=tgz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://foicica.com/${APP_NAME,,}/download/${APP_NAME,,}_${APP_VERSION}.${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${ARCH_TYPE} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Textadept
Comment=Minimalist cross-platform text editor
GenericName=Editor
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/core/images/ta_32x32.png
Path=/opt/${APP_NAME,,}
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Accessories;System;Development;
Keywords=Editor;Text;Lua;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install TexStudio LaTeX editor
APP_NAME=texstudio
APP_VERSION=2.12.6
APP_EXT=tar.gz
sudo apt-get install -y libpoppler-qt5-dev libgs-dev qtscript5-dev texlive
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}${APP_VERSION}
qmake texstudio.pro && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Diffuse file compare/merge utility
APP_NAME=diffuse
APP_VERSION=0.4.8
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}-1_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install myNetPCB PCB layout and schematic capture tool
APP_NAME=myNetPCB
APP_VERSION=7_573
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based PCB layout and schematic capture tool
GenericName=${APP_NAME}
Exec=sh /opt/${APP_NAME,,}/bin/${APP_NAME}.sh
#Icon=
Path=/opt/${APP_NAME,,}/bin
Type=Application
StartupNotify=true
Terminal=false
Categories=Science;Education;Electronics;
Keywords=PCB;Electronics;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Shotcut video editor
APP_NAME=Shotcut
APP_VERSION=180102
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${APP_NAME,,}-linux-${ARCH_TYPE}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Cross-platform Video Editor
GenericName=Video Editor
Exec=/opt/${APP_NAME,,}/${APP_NAME}.app/${APP_NAME,,}
Icon=applications-multimedia
Path=/opt/${APP_NAME,,}/${APP_NAME}.app
Type=Application
StartupNotify=true
Terminal=false
Categories=Video;Multimedia;
Keywords=Video;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME}.app/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Nightcode Clojure/Clojurescript IDE from package
APP_NAME=Nightcode
APP_VERSION=2.5.6
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/oakes/${APP_NAME}/releases/download/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Dropbox online storage utility from package
APP_NAME=dropbox
APP_VERSION=2.10.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://linux.dropbox.com/packages/ubuntu/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install OovAide C++/Java IDE with UML support from package
APP_NAME=Oovaide
APP_VERSION=0.1.7
APP_EXT=deb
sudo apt-get install -y libclang1 libgtk-3-0
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-Linux.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install PlantUML Java-based UML modeling tool
APP_NAME=PlantUML
APP_VERSION=1.2017.18
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}.${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based UML modeling tool
GenericName=${APP_NAME}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=UML;Modeling;Programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}


# Install Clevit "smart" text editor
APP_NAME=Clevit
APP_VERSION=1.3.4.1
APP_EXT=tar.gz
sudo apt-get install -y build-essential make cmake qtdeclarative5-dev qml-module-qtquick-controls qt5-default
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}%20v${APP_VERSION}.${APP_EXT}
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/TigaxMT-Clevit-d44c1d3
qmake && make && sudo make install
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /usr/share/icons/hicolor/scalable/apps/icon.png /usr/share/icons/hicolor/scalable/apps/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment="Smart" text editor
GenericName=${APP_NAME}
Exec=/usr/bin/${APP_NAME}
Icon=/usr/share/icons/hicolor/scalable/apps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;Accessories;
Keywords=Editor;Text;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install OCS Store application installer from package
APP_NAME=ocsstore
APP_VERSION=2.2.1
APP_EXT=deb
sudo apt-get install -y libclang1 libgtk-3-0
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://dl.opendesktop.org/api/files/download/id/1506729421/${APP_NAME}_${APP_VERSION}-0ubuntu1_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install NixNote open source Evernote client from package
APP_NAME=nixnote
APP_VERSION=2.0.2
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/nevernote/${APP_NAME}2-${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Minbrowser minimalist web browser from package
APP_NAME=min
APP_VERSION=1.6.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/minbrowser/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install gFileFinder file search GUI utility from source
APP_NAME=gFileFinder
APP_VERSION=0.2
APP_EXT=tar.gz
sudo apt-get install -y libgtk-3-dev libxcb-ewmh-dev libxcb1-dev xcb-proto xcb-util-image xcb-util-wm xcb-util-xrm
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/gff${APP_VERSION}-src.${APP_EXT}
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/gff
make && sudo mv src/gff /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Polybar status bar from source
APP_NAME=polybar
APP_VERSION=3.0.5
APP_EXT=tar.gz
sudo apt-get install -y libcairo2-dev libx11-xcb-dev 
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/gff${APP_VERSION}-src.${APP_EXT}
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/gff
make && sudo mv src/gff /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install GLosung daily Bible verse tool from PPA
# http://www.godehardt.org/losung.html
sudo add-apt-repository -y ppa:godehardt/ppa
sudo apt-get update -y
sudo apt-get install -y glosung

# Install PHP Address Book web-based address book
# https://sourceforge.net/projects/php-addressbook/
APP_NAME=php-addressbook
APP_VERSION=9.0.0.1
APP_EXT=zip
DB_NAME=phpaddressbook
DB_USER=phpaddressbook
DB_PASSWORD=phpaddressbook
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/addressbookv${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
#cd /tmp/${APP_NAME,,}
#mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/addressbook ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install Qutebrowser keyboard-focused minimalist web browser from package
APP_NAME=qutebrowser
APP_VERSION=1.0.4
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}-1_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install LAME MP3 encoder from source
APP_NAME=lame
APP_VERSION=3.100
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Qodem terminal emulator from package
APP_NAME=qodem
APP_VERSION=1.0.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install dxirc Fox/Qt IRC client from source
APP_NAME=dxirc
APP_VERSION=1.30.0
APP_EXT=tar.gz
sudo apt-get install -y libfox-1.6-dev qt5-qmake libqt5multimedia5 qtmultimedia5-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ForeverNote open-source Evernote web client from package
APP_NAME=ForeverNote
APP_VERSION=1.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install OSMO organizer utility from source
APP_NAME=osmo
APP_VERSION=0.4.2
APP_EXT=tar.gz
sudo apt-get install -y libwebkitgtk-3.0-dev libxml2-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}-pim/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Delta Hex Editor Java-based hexadecimal editor from package
APP_NAME=deltahex-editor
APP_VERSION=0.1.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/deltahex/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install PDF Split and Merge (PDFsam) editor from package
APP_NAME=pdfsam
APP_VERSION=3.3.5-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Voya Media audio/video/image player from package
APP_NAME=voyamedia
APP_VERSION=2.9-5
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-free-${APP_VERSION}.noarch.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Geoserver as stand-alone binary
# http://docs.geoserver.org/latest/en/user/installation/linux.html
APP_NAME=geoserver
APP_VERSION=2.12.0
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}-bin.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION} /opt/${APP_NAME,,}
sudo chown -R $USER /opt/${APP_NAME,,}
echo "export GEOSERVER_HOME=/opt/"${APP_NAME,,} >> $HOME/.profile
source $HOME/.profile
sudo ln -s /opt/${APP_NAME,,}/bin/startup.sh /usr/local/bin/geoserver
sh /opt/${APP_NAME,,}/bin/startup.sh
xdg-open http://localhost:8080/geoserver &

# Install TeamPass PHP-based collaborative password manager
# https://github.com/nilsteampassnet/TeamPass
APP_NAME=TeamPass
APP_VERSION=2.1.27.9
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
sudo apt-get install -y php5.6-mcrypt php5.6-mbstring php5.6-iconv php5.6-xml php5.6-gd openssl
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://codeload.github.com/nilsteampassnet/${APP_NAME}/${APP_EXT}/${APP_VERSION}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/includes/config
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/includes/avatars
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/includes/libraries/csrfp/libs
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/includes/libraries/csrfp/log
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/includes/libraries/csrfp/js
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/backups
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/files
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/install
sudo chmod -R 0777 ${WWW_HOME}/${APP_NAME,,}/upload
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "grant all privileges on ${DB_NAME}.* to teampass_admin@'%' identified by 'PASSWORD';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd $HOME
rm -rf /tmp/${APP_NAME}*
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install Pentobi Blokus-style board game from source
APP_NAME=pentobi
APP_VERSION=14.1
APP_EXT=tar.xz
sudo apt-get install -y g++ make cmake qttools5-dev qttools5-dev-tools libqt5svg5-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
cmake -DCMAKE_BUILD_TYPE=Release . && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install FeedTurtle Java-based RSS news aggregator client
APP_NAME=FeedTurtle
APP_VERSION=X.3
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}${APP_VERSION} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based RSS news aggregator
GenericName=${APP_NAME}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION}.jar
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=RSS;News;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install cppcrypto multi-algorithm C++ crypto library including digest and cryptor utilities from source
APP_NAME=cppcrypto
APP_VERSION=0.17
APP_EXT=zip
sudo apt-get install -y g++ make yasm
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}-src.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}
make && sudo make install
cd ../cryptor
make && sudo make install
cd ../digest
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Video Easy Editor minimal video editor from source
APP_NAME=video-easy-editor
APP_VERSION=130
APP_EXT=tar.gz
sudo apt-get install -y pkg-config libopencv-dev ffmpeg libpulse-dev libgtk2.0-dev
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/easy-editor-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}
./build.sh && sudo cp easy-editor start-project video2yuv.sh yuv2mp4.sh /usr/local/bin && cp ctrlview.jpg $HOME
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install djvu2pdf tool to convert Djvu files to PDF files from package
# http://0x2a.at/s/projects/djvu2pdf
APP_NAME=djvu2pdf
APP_VERSION=0.9.2-1
APP_EXT=deb
sudo apt-get install -y djvulibre-bin ghostscript
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://0x2a.at/site/projects/${APP_NAME}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CodeLite C, C++, PHP and Node.js IDE and wxCrafter from package
APP_NAME=wxcrafter
APP_VERSION=2.8-1
APP_EXT=deb
source /etc/lsb-release
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://repos.codelite.org/ubuntu/pool/universe/w/${APP_NAME}/${APP_NAME}_${APP_VERSION}.${DISTRIB_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

APP_NAME=codelite
APP_VERSION=11.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://repos.codelite.org/ubuntu/pool/universe/c/${APP_NAME}/${APP_NAME}_${APP_VERSION}unofficial.${DISTRIB_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Buttercup JavaScript/Electron desktop password manager from package
APP_NAME=buttercup-desktop
APP_VERSION=0.24.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/buttercup/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Tuitter JavaScript/Electron Twitter client from package
APP_NAME=Tui
APP_VERSION=0.4.15
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/rhysd/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}-linux-${ARCH_TYPE}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}-linux-${ARCH_TYPE} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=JavaScript/Electron Twitter Client
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/resources/app/resources/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Twitter;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Komodo Edit editor from package
APP_NAME=Komodo-Edit
APP_VERSION_MAJOR=11.0.1
APP_VERSION_MINOR=18119
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://downloads.activestate.com/Komodo/releases/${APP_VERSION_MAJOR}/${APP_NAME}-${APP_VERSION_MAJOR}-${APP_VERSION_MINOR}-linux-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION_MAJOR}-${APP_VERSION_MINOR}-linux-${ARCH_TYPE}
sudo ./install.sh /opt/komodo-edit
sudo ln -s /opt/komodo-edit/bin/komodo /usr/local/bin/komodo
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CherryTree hierarchical notepad/text editor from package
# https://www.giuspen.com/cherrytree/
APP_NAME=cherrytree
APP_VERSION=0.38.4-0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.giuspen.com/software/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Raccoon Java-based Google Play Store and APK downloader utility
APP_NAME=raccoon
APP_VERSION=4.1.6
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L http://${APP_NAME}.onyxbits.de/sites/${APP_NAME}.onyxbits.de/files/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME}
sudo mv /tmp/${APP_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based Google Play Store and APK downloader utility
GenericName=${APP_NAME}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Android;APK;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Mind Map Architect mind mapping tool from package
APP_NAME=mmarchitect
APP_VERSION=0.5.0
APP_EXT=deb
# Install libgee2 dependency from Ubuntu 14.04
curl -o /tmp/libgee2.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libg/libgee/libgee2_0.6.8-1ubuntu1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libgee2.deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SmallBASIC interpreter from package
APP_NAME=smallbasic
APP_VERSION=0.12.11
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Java Hex Editor Java-based hexadecimal editor
APP_NAME=JavaHexEditor
APP_VERSION=linux
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based hexadecimal editor
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Programming;Development;
Keywords=Editor;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Kid3 audio tag editor
APP_NAME=Kid3
APP_VERSION=3.5.1
APP_EXT=tgz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-Linux.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo mv ${APP_NAME,,}-${APP_VERSION}-Linux /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Audio tag editor
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}-qt
Icon=/opt/${APP_NAME,,}/icons/hicolor/48x48/apps/${APP_NAME,,}-qt.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Audio;Multimedia;
Keywords=MP3;Tag;Editor
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,}-cli /usr/local/bin/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,}-qt /usr/local/bin/${APP_NAME,,}-qt
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Open Limbas PHP database utility
APP_NAME=openlimbas
APP_VERSION=3.3.16.345
APP_EXT=tar.gz
DB_NAME=limbas
DB_USER=limbas
DB_PASSWORD=limbas
source /etc/lsb-release
sudo apt-get install -y unixodbc php5.6-odbc
curl -o /tmp/mysql-odbc-driver.tar.gz -J -L https://cdn.mysql.com//Downloads/Connector-ODBC/5.3/mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit.tar.gz
cd /tmp
dtrx -n /tmp/mysql-odbc-driver.tar.gz
cd /tmp/mysql-odbc-driver/mysql-connector-odbc-5.3.9-linux-ubuntu16.04-x86-64bit
sudo mv ./bin/myodbc-install /usr/local/bin
sudo mv ./lib/* /usr/lib/x86_64-linux-gnu/odbc/
cat > /tmp/odbcinst.ini << EOF
[MySQL]
Description = ODBC for MySQL
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmyodbc5a.so
Setup = /usr/lib/x86_64-linux-gnu/odbc/libodbcmyS.so
FileUsage = 1
EOF
cat > /tmp/odbc.ini << EOF
[${APP_NAME}]
Description = MySQL Connection to OpenLimbas Database
Driver = MySQL
Database = ${DB_NAME}
Server = localhost
Port = 3306
User = ${DB_USER}
Password = ${DB_PASSWORD}
Socket = /var/run/mysqld/mysqld.sock
EOF
sudo mv -f /tmp/odbc* /etc
# Add link to MySQL daemon socket for use by ODBC
sudo ln -s /var/run/mysqld/mysqld.sock /tmp/mysql.sock
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/limbas/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo mv /tmp/${APP_NAME} ${WWW_HOME}/${APP_NAME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
sudo chmod -R a+w /var/www/html/${APP_NAME}/dependent
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/dependent/admin/install/index.php &

# Install Admidio organizational management tool
APP_NAME=admidio
APP_VERSION=3.2.14
APP_EXT=zip
DB_NAME=admidio
DB_USER=admidio
DB_PASSWORD=admidio
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME}.${APP_EXT}
sudo mv /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION} ${WWW_HOME}/${APP_NAME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME}
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME}/adm_my_files
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install Shiba JavaScript/Electron Markdown editor with preview from package
APP_NAME=Shiba
APP_VERSION=1.1.0
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/rhysd/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}-linux-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}-linux-${ARCH_TYPE} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=JavaScript/Electron Markdown editor with preview
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/resources/app/resources/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Editors;Office;Development;
Keywords=Markdown;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install WingIDE 101 Python editor/IDE from package
APP_NAME=WingIDE-101
APP_VERSION=6.0.8
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://wingware.com/pub/${APP_NAME,,}/${APP_VERSION}/${APP_NAME,,}-6_${APP_VERSION}-1_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Insomnia REST client from package
APP_NAME=insomnia
APP_VERSION=5.11.7
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://builds.insomnia.rest/downloads/ubuntu/latest
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install XnViewMP image viewer/converter from package
APP_NAME=XnViewMP
APP_VERSION=0.88
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://download.xnview.com/${APP_NAME}-linux-${ARCH_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QupZilla Qt5-based minimalistic web browser from source
APP_NAME=QupZilla
APP_VERSION=2.2.4
APP_EXT=tar.xz
sudo apt-get install -y qt5-default qtwebengine5-dev qtwebengine5-dev-tools libqt5x11extras5-dev qttools5-dev-tools libxcb-util0-dev libssl-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
qmake && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Simple-Arc-Clock Qt5-based desktop clock from source
APP_NAME=Simple-Arc-Clock
APP_VERSION=1.2
APP_EXT=tar.gz
sudo apt-get install -y qt5-default qtwebengine5-dev qtwebengine5-dev-tools libqt5x11extras5-dev qttools5-dev-tools libxcb-util0-dev libssl-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://github.com/phobi4n/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
qmake && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Shallot Python-based file manager from package
APP_NAME=shallot
APP_VERSION=1.0.3106
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://pseudopolis.eu/wiki/pino/projs/${APP_NAME}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Meteo-Qt Qt5-based weather utility from source
APP_NAME=Meteo-Qt
APP_VERSION=0.9.7
APP_EXT=tar.gz
sudo apt-get install -y python3-pyqt5 python3-sip python3-lxml
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://github.com/dglent/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
sudo python3 setup.py install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Electric Sheep screensaver from source
# https://blog.openbloc.fr/compiling-electric-sheep-on-ubuntu-linux-17-10/
APP_NAME=flam3
APP_VERSION=3.1.1
APP_EXT=tar.gz
sudo apt-get install -y libxml2-dev libjpeg8-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/scottdraves/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure && make && sudo make install

APP_NAME=electricsheep
APP_VERSION=master
APP_EXT=tar.gz
sudo apt-get install -y subversion autoconf libtool libgtk2.0-dev libgl1-mesa-dev libavcodec-dev libavformat-dev libswscale-dev liblua5.1-0-dev libcurl4-openssl-dev libxml2-dev libjpeg8-dev libgtop2-dev libboost-dev libboost-filesystem-dev libboost-thread-dev libtinyxml-dev freeglut3-dev glee-dev libwxgtk3.0-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://codeload.github.com/scottdraves/${APP_NAME}/${APP_EXT}/${APP_VERSION}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}/client_generic
./autogen.sh && ./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Leiningen and Clojure from script
APP_NAME=lein
APP_VERSION=
APP_EXT=
curl -o /tmp/${APP_NAME,,} -J -L https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}

# Install RSS Guard RSS reader/aggregator from source
# Note:  For Ubuntu 16.04, we must use version 3.2.4
#        for compatibility with Qt version 5.5.1
#        from the package repository.
APP_NAME=rssguard
APP_VERSION=3.2.4
APP_EXT=tar.gz
sudo apt-get install -y qttools5-dev qttools5-dev-tools cmake
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://codeload.github.com/martinrotter/${APP_NAME}/${APP_EXT}/${APP_VERSION}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
mkdir -p build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Moka Video Convert ffmpeg front-end from package
APP_NAME=moka-vc
APP_VERSION=1.0.41-1_Fix
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/moka-video-converter_${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Encrypt cross-platform GUI/CLI encryption tool from package
APP_NAME=encrypt
APP_VERSION=2017.09
APP_EXT=deb
curl -o /tmp/libgcrypt20.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libg/libgcrypt20/libgcrypt20_1.7.8-2ubuntu1_amd64.deb
sudo gdebi -n /tmp/libgcrypt20.deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}-1_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install MedleyText notepad/snippet manager built with Electron (AppImage)
APP_NAME=MedleyText
APP_VERSION=latest
APP_EXT=AppImage
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://s3.amazonaws.com/${APP_NAME,,}/releases/medley-latest.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Electron-based notepad/snippet manager
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;Accessories;System
Keywords=Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Sushi multi-panel web browser from package
APP_NAME=sushi-browser
APP_VERSION=0.13.5
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://sushib.me/dl/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Rufas Slider puzzle game from source
APP_NAME=rufasslider
APP_VERSION=9nov17
APP_EXT=tar.gz
sudo apt-get install -y qttools5-dev qttools5-dev-tools cmake
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/rs${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/rslid
sudo mkdir -p /opt/${APP_NAME}
sudo mv ./puzzles /opt/${APP_NAME}
sudo mv ./data /opt/${APP_NAME}
sudo mv ./include /opt/${APP_NAME}
sudo mv ./*.txt ./*.md /opt/${APP_NAME}
sudo mkdir -p /opt/${APP_NAME}/libs/gnu
sudo mv ./libs/gnu/* /opt/${APP_NAME}/libs/gnu
sudo mkdir -p /opt/${APP_NAME}/bin/gnu
sudo mv ./bin/gnu/* /opt/${APP_NAME}/bin/gnu
sudo mkdir -p /opt/${APP_NAME}/src
sudo mv *.cc *.cpp *.h *.hpp /opt/${APP_NAME}/src
sudo ln -s /opt/${APP_NAME}/bin/gnu/rufaslid /usr/local/bin/rufaslider
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install GEOrgET (GoogleEarth Organiser, Editor & Toolkit) map editing tool
APP_NAME=GEOrgET
APP_VERSION=1.5.0
APP_EXT=7z
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod a+x ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+r ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
# Populate data from scripts
mysql -h localhost -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} < ${WWW_HOME}/${APP_NAME,,}/timezone_regions.sql
mysql -h localhost -u root -proot ${DB_NAME} < ${WWW_HOME}/${APP_NAME,,}/timezones.sql  # Root permission required to create procedure.
mysql -h localhost -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} < ${WWW_HOME}/${APP_NAME,,}/cities.sql
xdg-open http://localhost/${APP_NAME,,}/${APP_NAME,,}.php &

# Install Software Process Dashboard Java-based project management tool
APP_NAME=processdash
APP_VERSION=2-4
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/pdash-install-main-${APP_VERSION}.${APP_EXT}
sudo java -jar /tmp/${APP_NAME,,}.${APP_EXT} &
sudo cp /opt/*.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Buku Python/SQLite command-line web bookmark manager from package
APP_NAME=buku
APP_VERSION=3.5-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-bookmark-manager/${APP_NAME,,}_${APP_VERSION}_ubuntu16.04.${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JSoko Java-based Sokoban puzzle game from package
APP_NAME=JSoko
APP_VERSION=1.81
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}applet/${APP_NAME}_${APP_VERSION}_linux.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Crystal Facet UML tool from package
APP_NAME=crystal_facet_uml
APP_VERSION=1.1.0
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/crystal-facet-uml/${APP_NAME}-${APP_VERSION}-Linux-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/crystal_facet
sudo cp -r * /
cd $HOME
rm -rf /tmp/${APP_NAME,,} /tmp/crystal_facet*

# Install Java Fabled Lands role-playing game
APP_NAME=JaFL
APP_VERSION=106
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://downloads.sourceforge.net/flapp/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /opt
sudo chmod a+w /opt/${APP_NAME,,}/user.ini
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar ./flands.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Java Fabled Lands
Comment=Java remake of 'Fabled Lands' RPG
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/flands.jar
Icon=/opt/${APP_NAME,,}/icon.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Games;RPG;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JFileProcessor Java-based file manager
APP_NAME=JFileProcessor
APP_VERSION=1.5.10
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/stant/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv jFileProcessor ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar ./${APP_NAME}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java file manager
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
#Icon=/opt/${APP_NAME,,}/icon.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QtPass GUI for pass, the standard Unix password manager from source
APP_NAME=QtPass
APP_VERSION=1.2.1
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -k -L https://github.com/IJHack/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./release-linux
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Mooedit text editor from source
APP_NAME=medit
APP_VERSION=1.2.92-devel
APP_EXT=tar.bz2
sudo apt-get install -y libgtk2.0-dev libxml2-dev python2.7-dev python-gtk2-dev intltool
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/mooedit/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install pyCSVDB SQLite and CSV DB management tool from source
APP_NAME=pyCSVDB
APP_VERSION=1V75
APP_EXT=zip
sudo apt-get install -y python3-tk
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
python3 ./${APP_NAME}.pyw
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Python SQLite/CSV database management tool
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME}.pyw
#Icon=/opt/${APP_NAME,,}/icon.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=SQLite;CSV;Database;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install gvSIG-CE Java-based mapping/GIS desktop tool
APP_NAME=gvSIG-CE
APP_VERSION=1.0.0.b1
APP_EXT=tar.bz2
sudo apt-get install -y python3-tk
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/gvsigce/${APP_NAME,,}-${APP_VERSION}-linux-64.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME,,}-${APP_VERSION}-linux-64 ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
./gvSIGCE.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Python SQLite/CSV database management tool
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/gvSIGCE.sh
Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=GIS;Mapping;
Keywords=GIS;Maps;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Nihil Dice Roller (NDR) dice-rolling utility for multiple RPG platforms
APP_NAME=ndr3
APP_VERSION=3.20.1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
sudo apt-get install -y python3-tk
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/nihildiceroller/${APP_NAME,,}-linux${ARCH_TYPE}.${APP_VERSION}.bin.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
./${APP_NAME}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Nihil Dice Roller
Comment=Dice-rolling program for multiple RPG platforms
GenericName=Dice Roller
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Dice;Games;RPG;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Shaarli PHP-based databaseless bookmark manager
APP_NAME=Shaarli
APP_VERSION=0.9.2
APP_EXT=tar.gz
sudo apt-get install -y qttools5-dev qttools5-dev-tools cmake
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://codeload.github.com/${APP_NAME,,}/${APP_NAME}/${APP_EXT}/v${APP_VERSION}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}-${APP_VERSION} ${APP_NAME,,}
sudo mv ${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
cd ${WWW_HOME}/${APP_NAME,,}
sudo composer update
xdg-open http://localhost/${APP_NAME,,}/index.php &
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install KiCad electronic design automation suite from PPA
sudo add-apt-repository -y ppa:js-reynaud/kicad-4
sudo apt update
sudo apt install -y kicad

# Install OpenShot video editor from PPA
sudo add-apt-repository -y ppa:openshot.developers/ppa
sudo apt-get update
sudo apt-get install -y openshot-qt

# Install View Your Mind (VYM) Qt mind-mapping tool from source
APP_NAME=vym
APP_VERSION=2.6.11
APP_EXT=tar.bz2
sudo apt-get install -y python3-tk
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qmake && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Vym (View Your Mind)
Comment=Mind-mapping tool
GenericName=Vym
Path=/usr/local/${APP_NAME,,}
Exec=/usr/local/${APP_NAME,,}/${APP_NAME,,}
Icon=/usr/local/${APP_NAME,,}/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Mind-mapping;Diagrams;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install GtkHash GUI tool for calculating file hashes/checksums from source
APP_NAME=gtkhash
APP_VERSION=1.1.1
APP_EXT=tar.xz
sudo apt-get install -y libgcrypt20-dev libb2-dev libssl-dev libcrypto++-dev libmbedtls-dev libmhash-dev nettle-dev intltool
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure --enable-libcrypto --enable-linux-crypto --enable-mbedtls --enable-mhash --enable-nettle --with-gtk=2.0
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install GridSheet printable PDF graph paper generator from package
APP_NAME=gridsheet
APP_VERSION=0.2.0-1
APP_EXT=deb
sudo apt-get install -y libgcrypt20-dev libb2-dev libssl-dev libcrypto++-dev libmbedtls-dev libmhash-dev nettle-dev intltool
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install ChessPDFBrowser for working with chess PDF books and PGNs
APP_NAME=ChessPDFBrowser
APP_VERSION=20171115
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}1/${APP_VERSION}.${APP_NAME}.v1.0.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_VERSION}.${APP_NAME}.v1.0 ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}/_binary
PATH=/opt/${APP_NAME,,}/_binary:$PATH; export PATH
java -jar ./ChessPDFbrowser.v1.0.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Tool to work with chess PDF books and PGNs
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/_binary
Exec=java -jar /opt/${APP_NAME,,}/_binary/ChessPDFbrowser.v1.0.jar
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Chess;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JStock stock market tool for 28 countries
APP_NAME=JStock
APP_VERSION=1.0.7.30
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/yccheok/${APP_NAME,,}/releases/download/release_1-0-7-30/${APP_NAME,,}-${APP_VERSION}-bin.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar ./${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Stock market tool for 28 countries
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Finance;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Riot instant messenger/collaboration platform from package
APP_NAME=riot-web
APP_VERSION=0.13.4
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://riot.im/packages/debian/pool/main/r/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Angry IP Scanner from package
APP_NAME=ipscan
APP_VERSION=3.5.2
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SimulIDE electronic circuit simulator
APP_NAME=SimulIDE
APP_VERSION=0.1.5
APP_MINOR_VERSION=SR1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=Lin64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=Lin32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}-${ARCH_TYPE}-${APP_MINOR_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp
mv ${APP_NAME}_${APP_VERSION}-${ARCH_TYPE}-RC3 ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}/bin
PATH=/opt/${APP_NAME,,}/bin:$PATH; export PATH
./${APP_NAME}_${APP_VERSION}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Electronic circuit emulator
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/bin
Exec=/opt/${APP_NAME,,}/bin/${APP_NAME}_${APP_VERSION}
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Science;Electronics;
Keywords=Electronics;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install GNU nano text editor from source
APP_NAME=nano
APP_VERSION=2.9.3
APP_EXT=tar.xz
sudo apt-get install -y libncurses5-dev libncursesw5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://nano-editor.org/dist/v2.9/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Terminal-based minimal text editor
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME}
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=true
Categories=Programming;Development;Accessories;
Keywords=Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install nuBASIC IDE and compiler for BASIC from package
APP_NAME=nubasic
APP_VERSION=1.48-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Xiki shell enhancement
sudo apt-get install -y emacs
curl -L https://xiki.com/install_xsh -o ~/install_xsh; sudo bash ~/install_xsh

# Install Incremental Scenario Testing Tool (ISTT) web-based test scenario management tool
APP_NAME=istt
APP_VERSION=v1.1.1
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod a+x ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+r ${WWW_HOME}/${APP_NAME,,}
# Update default password in configuration file
UPDATE_STRING=s/Teleca01/${APP_NAME}/g
sudo sed -i ${UPDATE_STRING} ${WWW_HOME}/${APP_NAME,,}/include/defines.php
# Update time zone in configuration file
sudo sed -i 's@Europe/Berlin@Americas/Chicago@g' ${WWW_HOME}/${APP_NAME,,}/include/defines.php
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install HOFAT (Hash Of File And Text) Java-based hash calculator
APP_NAME=HOFAT
APP_VERSION=18-12-17
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_bin.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME,,}_${APP_VERSION}_bin ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar ./${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based file/text hash calculator
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Security;Hash;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Terminus JavaScript/Electron terminal from package
APP_NAME=terminus
APP_VERSION=1.0.0-alpha.36
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/Eugeny/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Parlatype GTK audio player for transcription from source
APP_NAME=Parlatype
APP_VERSION=1.5.4
APP_EXT=tar.gz
sudo apt-get install -y build-essential automake autoconf intltool libgirepository1.0-dev libgladeui-dev gtk-doc-tools yelp-tools libgtk-3-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/gkarsay/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
autoreconf && ./configure --prefix=/usr --disable-introspection && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=GTK audio player for transcription
GenericName=${APP_NAME}
Path=/usr/bin
Exec=/usr/bin/${APP_NAME,,}
Icon=/usr/share/icons/hicolor/48x48/apps/com.github.gkarsay.parlatype.png
Type=Application
StartupNotify=true
Terminal=true
Categories=Audio;Multimedia;Other;
Keywords=Audio;Player;Multimedia;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install BashStyle-NG graphical tool for managing Bash and other shell tools from package
APP_NAME=BashStyle-NG
APP_VERSION=10.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://apt.nanolx.org/pool/main/b/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}-1nano_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JEditor Java-based text editor
APP_NAME=jEditor
APP_VERSION=0.4.14
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_GPL-bin-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -cp jEditorGPL.jar org.jeditor.app.JAppEditor
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based text editor
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -cp jEditorGPL.jar org.jeditor.app.JAppEditor
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;Programming;Development;
Keywords=Editor;Text;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install DataMelt Java-based scientific computation and visualization environment
# http://jwork.org/dmelt/
APP_NAME=dmelt
APP_VERSION=2.1
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
./${APP_NAME,,}.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based scientific computation and visualization environment
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.sh
Icon=/opt/${APP_NAME,,}/Docs/jehep.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Science;Scientific;Development;Math;
Keywords=Math;Science;Visualization;Programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Quickcal minimalist arithmetic and statistical calculator from package
APP_NAME=Quickcal
APP_VERSION=2.1-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install XML Copy Editor validating XML editor from package
APP_NAME=xmlcopyeditor
APP_VERSION=1.2.1.3-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/xml-copy-editor/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install qmmp Qt-based Multimedia Player from source
APP_NAME=qmmp
APP_VERSION=1.2.0
APP_EXT=tar.bz2
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-dev/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
cmake ./ -DCMAKE_INSTALL_PREFIX=/usr && make && sudo make install INSTALL_ROOT=/usr
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Dextrous Text Editor (DTE) console text editor from source
APP_NAME=DTE
APP_VERSION=1.6
APP_EXT=tar.gz
sudo apt-get install -y make gcc libncurses5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/craigbarnes/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
make -j8 && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Console text editor
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=/opt/${APP_NAME,,}/lib/ico-gvSIG.png
Type=Application
StartupNotify=true
Terminal=true
Categories=System;Accessories;Programming;Development;
Keywords=Editor;Text;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Sqlectron Electron-based database manager for PostgreSQL, MySQL, and MS SQL Server from package
APP_NAME=Sqlectron
APP_VERSION=1.29.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}-gui/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Modelio UML modeling tool from package
APP_NAME=Modelio
APP_VERSION=3.7_3.7.0-201711211349
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}uml/${APP_NAME,,}-open-source${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Dooble web browser from package
APP_NAME=Dooble
APP_VERSION=2.1.6
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install EncNotex encrypted notepad from package
APP_NAME=EncNotex
APP_VERSION=1.4.3.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://sites.google.com/site/${APP_NAME,,}/download/${APP_NAME,,}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Thonny minimalist Python IDE/editor from package
APP_NAME=Thonny
APP_VERSION=2.1.16
APP_EXT=sh
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://bitbucket.org/plas/${APP_NAME,,}/downloads/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
sudo chmod +x /tmp/${APP_NAME,,}.${APP_EXT}
/tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install cpu-stat command-line CPU usage statistics tool from source
# http://blog.davidecoppola.com/2016/12/released-cpu-stat-command-line-cpu-usage-statistics-for-linux/
APP_NAME=cpu-stat
APP_VERSION=0.01.02
APP_EXT=tar.gz
sudo apt-get install -y scons
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/vivaladav/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
scons mode=release
sudo scons mode=release install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Qt-based Torrent File Editor from source
APP_NAME=torrent-file-editor
APP_VERSION=0.3.10
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
mkdir - p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DQT5_BUILD=ON .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install OGapp Qt-based notepad from source
APP_NAME=OGapp
APP_VERSION=N/A
APP_EXT=N/A
git clone https://git.code.sf.net/p/${APP_NAME,,}/code /tmp/${APP_NAME,,}
cd /tmp/${APP_NAME,,}
qmake && make && sudo make install
sudo ln -s /usr/bin/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install MLTerm multi-language terminal emulator from source
APP_NAME=MLTerm
APP_VERSION=3.8.4
APP_EXT=tar.gz
sudo apt-get install -y libfribidi-dev libssh2-1-dev libvte-dev libgdk-pixbuf2.0-dev 
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
./configure && make && sudo make install
sudo cp ./doc/icon/mlterm_48x48.xpm /usr/local/share/icons/hicolor/48x48
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Multi-language terminal emulator
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/icons/hicolor/48x48/mlterm_48x48.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Terminal;Shell;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install util-linux general system utilites from source
APP_NAME=util-linux
APP_VERSION=2.31
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/karelzak/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
./autogen.sh && ./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Linux Process Explorer GUI process viewer/manager from package
APP_NAME=procexp
APP_VERSION=1.7.289
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}-0ubuntu1_all.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}.${APP_EXT}.1
sudo cp -R * /
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install MantisBT web-based bug tracking tool
APP_NAME=mantisbt
APP_VERSION=2.9.0
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME,,}-${APP_VERSION} ${APP_NAME,,}
sudo mv ${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/admin/install.php &

# Install VBox Raw Disk GUI Java-based VBox disk editing/resizing GUI
APP_NAME=vboxrawdiskgui
APP_GUI_NAME="VBox Raw Disk GUI"
APP_VERSION=v2.7
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/VBox%20Raw%20Disk%20GUI%20${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+r /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_GUI_NAME}
Comment=Java-based VBox disk editing/resizing GUI
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
#Icon=/opt/${APP_NAME,,}/Docs/jehep.png
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Utilities;
Keywords=Virtualization;Java;Disk;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install EJE (Everyone's Java Editor) minimalist Java IDE
APP_NAME=EJE
APP_GUI_NAME="EJE (Everyone's Java Editor)"
APP_VERSION=3.5
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME} /opt
sudo chmod a+x /opt/${APP_NAME}/${APP_NAME,,}.sh
sudo chmod -R a+w /opt/${APP_NAME}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:$PATH; export PATH
sh /opt/${APP_NAME}/${APP_NAME,,}.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_GUI_NAME}
Comment=Minimalist editor/IDE for Java programming
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}
Exec=sh /opt/${APP_NAME}/${APP_NAME,,}.sh
Icon=/opt/${APP_NAME}/resources/images/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Programming;Java;Editor;IDE;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Java YouTube Video Downloader (ytd2)
APP_NAME=ytd2
APP_GUI_NAME="Java YouTube Video Downloader (ytd2)"
APP_VERSION=V20170914
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/run_${APP_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
sudo chown -R root:root /opt/${APP_NAME,,}
sudo chmod -R a+r /opt/${APP_NAME}
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:$PATH; export PATH
java -jar /opt/${APP_NAME}/${APP_NAME,,}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_GUI_NAME}
Comment=Java-based GUI YouTube Video Downloader
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}
Exec=java -jar /opt/${APP_NAME}/${APP_NAME,,}.${APP_EXT}
#Icon=/opt/${APP_NAME}/resources/images/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Video;Internet;Multimedia;
Keywords=Video;Downloader;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Domination (Risk-style world conquest) Java-based game
APP_NAME=Domination
APP_GUI_NAME="Risk-style world conquest game built with Java"
APP_VERSION=1.1.1.7
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_install_${APP_VERSION}.${APP_EXT}
sudo java -jar /tmp/${APP_NAME,,}.${APP_EXT}
cat > /tmp/${APP_NAME,,} << EOF
# /bin/sh
cd /usr/local/${APP_NAME}
PATH=/usr/local/${APP_NAME}:$PATH; export PATH
/usr/local/${APP_NAME}/SwingGUI.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/${APP_NAME}
Exec=/usr/local/${APP_NAME}/SwingGUI.sh
Icon=/usr/local/${APP_NAME}/resources/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;
Keywords=Games;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Snd open-source sound editor from source
APP_NAME=Snd
APP_GUI_NAME="Popular open-source audio file editor"
APP_VERSION=18.0
APP_EXT=tar.gz
sudo apt-get install -y libasound2-dev wavpack
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure && make && sudo make install
sudo cp /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}/pix/s.png /usr/local/share/snd
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/snd/s.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Audio;Multimedia;
Keywords=Audio;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install pgweb cross-platform client for PostgreSQL databases 
APP_NAME=pgweb
APP_GUI_NAME="Cross-platform client for PostgreSQL databases"
APP_VERSION=0.9.11
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux_amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux_386
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${APP_NAME,,}_${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}_${ARCH_TYPE} & 
xdg-open http://localhost:8081/ &
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=/usr/local/share/snd/s.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;PostgreSQL;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Fileaxy Java-based file de-duplication, organization, and bulk previewing tool
APP_NAME=Fileaxy
APP_GUI_NAME="Java-based file de-duplication, organization, and bulk previewing tool"
APP_VERSION=122
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=/usr/local/${APP_NAME}/resources/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=File;Management;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install PDF Studio Viewer Java-based PDF viewer
APP_NAME=PDFStudioViewer
APP_GUI_NAME="PDF Studio Viewer"
APP_VERSION=v12_0_5
APP_EXT=sh
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/pdf-studio-viewer/${APP_NAME}_${APP_VERSION}_${ARCH_TYPE}.${APP_EXT}
sudo sh /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install ProjectLibre Java-based project management tool from package
APP_NAME=ProjectLibre
APP_VERSION=1.7.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install phpCollab web-based collaboration and project management tool
# http://www.phpcollab.com/
APP_NAME=phpCollab
APP_VERSION=v2.6
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} ${WWW_HOME}
sudo cp ${WWW_HOME}/${APP_NAME,,}/includes/settings_blank.php ${WWW_HOME}/${APP_NAME,,}/includes/settings.php
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME,,}/includes/settings.php ${WWW_HOME}/${APP_NAME,,}/files ${WWW_HOME}/${APP_NAME,,}/logos_clients
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/installation/setup.php &

# Install PySolFC Python-based Solitaire card game
APP_NAME=PySolFC
APP_GUI_NAME="Python-based Solitaire card game"
APP_VERSION=2.1.2
APP_EXT=tar.bz2
sudo apt-get install -y python3-pip
sudo pip3 install random2 sgmllib3k
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
sudo python3 ./setup.py install
# Install card sets
curl -o /tmp/${APP_NAME}-Cardsets-2.0.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-Cardsets-2.0.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}-Cardsets-2.0.${APP_EXT}
cd /tmp/${APP_NAME}-Cardsets-2.0
sudo cp -R /tmp/${APP_NAME}-Cardsets-2.0/* /usr/local/share/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME,,} /tmp/${APP_NAME}*

# Install Workrave repetitive-strain injury (RSI) prevention/recovery tool from source.
APP_NAME=Workrave
APP_GUI_NAME="Utility to remind you to take breaks when working at keyboard."
APP_VERSION=1.10.1
APP_EXT=tar.gz
sudo apt-get install -y libx11-dev libxtst-dev pkg-config libsm-dev libice-dev libglib2.0-dev python-cheetah libgtk2.0-dev libglibmm-2.4-dev libgtkmm-2.4-dev libsigc++-2.0-dev intltool libxss-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure --prefix=/usr/local && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,} /tmp/${APP_NAME}*

# Install Delta Hexadecimal Editor (Java-based) from package
APP_NAME=deltahex
APP_VERSION=0.1.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-editor_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Gambit Qt5 chess game from source
APP_NAME=Gambit
APP_GUI_NAME="Cross-platform Qt5 chess game."
APP_VERSION=1.0.4
APP_EXT=tar.xz
sudo apt-get install -y qtbase5-dev cmake make gcc g++
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}chess/${APP_NAME}-${APP_VERSION}-src.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-src
cd ./engine/gupta && make release
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-src
sh clean_all.sh
. ./setup_env.sh
c
b
sudo cp -R gambitchess ./data ./nls ./web ./doc ./artwork ./engine /opt/gambit
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}chess
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}chess
Icon=/opt/${APP_NAME,,}/data/icons/gambit/gambit-48.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Chess;Games;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Xtreme Download Manager (XDM) download accelerator from package
APP_NAME=xdm
APP_VERSION=2018
APP_EXT=tar.xz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/xdman/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo sh /tmp/${APP_NAME,,}/install.sh
# Remove built-in JRE and use system JRE instead.
sudo rm -rf /opt/xdman/jre
sudo mkdir -p /opt/xdman/jre/bin
sudo ln -s /usr/bin/java /opt/xdman/jre/bin/java
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install NGSpice electronic circuit simulation tool from source
APP_NAME=ngspice
APP_GUI_NAME="Classic electronic circuit simulation tool."
APP_VERSION=27
APP_EXT=tar.gz
sudo apt-get install -y libx11-dev libxaw7-dev libreadline6-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
mkdir -p release && cd release
../configure --with-x --with-readline=yes --disable-debug && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,} /tmp/${APP_NAME}*

# Install QDVDAuthor Qt-based DVD authoring tool from package
APP_NAME=qdvdauthor
APP_VERSION=2.3.1-8
APP_EXT=deb
source /etc/lsb-release
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://download.opensuse.org/repositories/home:/tkb/x${DISTRIB_ID}_${DISTRIB_RELEASE}/${KERNEL_TYPE}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install wxHexEditor hexadecimal editor from package
APP_NAME=wxHexEditor
APP_GUI_NAME="wxWidgets-based hexadecimal editor."
APP_VERSION=0.24
APP_EXT=tar.bz2
sudo apt-get install -y qtbase5-dev cmake make gcc g++
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-v${APP_VERSION}-Linux_x86_64.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo mv ${APP_NAME} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:$PATH; export PATH
/opt/${APP_NAME}/${APP_NAME}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}
Exec=/opt/${APP_NAME}/${APP_NAME}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Editor;Hex Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install DrJava lightweight Java editor/IDE
APP_NAME=DrJava
APP_GUI_NAME="Lightweight Java editor/IDE."
APP_VERSION=beta-20160913-225446
APP_EXT=jar
# Check to ensure Java installed
if ! [ -x "$(command -v java)" ]; then
	echo 'Error. Java is not installed. ' >&2
	echo 'Installing Java...'
	sudo apt-get install -y openjdk-8-jre
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Java;Programming;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install jPDFViewer cross-platform Java-based PDF viewer/reader
APP_NAME=jPDFViewer
APP_GUI_NAME="Cross-platform Java-based PDF viewer/reader."
APP_VERSION=N/A
APP_EXT=jar
# Check to ensure Java installed
if ! [ -x "$(command -v java)" ]; then
	echo 'Error. Java is not installed. ' >&2
	echo 'Installing Java...'
	sudo apt-get install -y openjdk-8-jre
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;System;
Keywords=PDF;Viewer;Reader;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install FinalCrypt Java-based file encryption utility from package
APP_NAME=FinalCrypt
APP_VERSION=Linux_x86_64_Debian_Based
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install SMPlayer Qt-based MPlayer front-end audio/video player with support for YouTube from source
APP_NAME=SMPlayer
APP_GUI_NAME="Cross-platform Qt-based audio/video player with support for YouTube."
APP_VERSION=17.12.0
APP_EXT=tar.bz2
sudo apt-get install -y qtbase5-dev qt5-qmake qt5-default qtscript5-dev qttools5-dev-tools qtbase5-private-dev libqt5webkit5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install OutWiker tree-style notepad/personal wiki from package
APP_NAME=OutWiker
APP_GUI_NAME="Cross-platform tree-style notepad/personal wiki."
APP_VERSION=2.1.0.834
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
	APP_VERSION=2.1.0.832   # Last version with builds for x86.
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/Jenyay/${APP_NAME,,}/releases/download/unstable_${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}_${ARCH_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Clevit Qt-based 'smart' text editor with built-in encryption from source
APP_NAME=Clevit
APP_GUI_NAME="Cross-platform Qt-based 'smart' text editor with built-in encryption."
APP_VERSION=1.4.0
APP_EXT=tar.gz
sudo apt-get install -y build-essential libssl-dev make cmake qtdeclarative5-dev qml-module-qtquick-controls qt5-default openssl
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/TigaxMT/${APP_NAME}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
qmake && make && sudo make install
sudo cp /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}/src/icons/icon.png /usr/share/icons/hicolor/scalable/apps/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/bin
Exec=/usr/bin/${APP_NAME}
Icon=/usr/share/icons/hicolor/scalable/apps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Programming;Development;
Keywords=Text;Editor;Encryption;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /usr/bin/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Alpus cross-platform offline dictionary viewer from package
APP_NAME=Alpus
APP_GUI_NAME="Freeware cross-platform offline dictionary viewer."
APP_VERSION=7.0
APP_EXT=tgz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=-x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://ng-comp.com/${APP_NAME,,}/${APP_NAME}-linux${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}/* /opt/${APP_NAME,,}
sudo mkdir -p /opt/${APP_NAME,,}/${APP_NAME}.Config
sudo chmod 777 /opt/${APP_NAME,,}/${APP_NAME}.Config
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME}.sh
#Icon=/usr/share/icons/hicolor/scalable/apps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;Education;
Keywords=Dictionary;Reference;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install WackoWiki PHP-based lightweight wiki tool
APP_NAME=wacko
APP_VERSION=r5.5.2
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}wiki/${APP_NAME,,}.${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,}.${APP_VERSION}/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+x ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+r ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install CuteCODE minimalist Tcl-based text editor
APP_NAME=CuteCODE
APP_GUI_NAME="Minimalist Tcl-based text editor."
APP_VERSION=N/A
APP_EXT=zip
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls  # Install required packages
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
sudo mv /tmp/${APP_NAME} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}/src
PATH=/opt/${APP_NAME}/src:$PATH; export PATH
wish /opt/${APP_NAME}/src/${APP_NAME}.tcl
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}/src
Exec=wish /opt/${APP_NAME}/src/${APP_NAME}.tcl
Icon=/opt/${APP_NAME}/Screenshots/${APP_NAME}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Programming;Development;
Keywords=Text;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install TeamSQL MySQL/PostgreSQL client from package
APP_NAME=TeamSQL
APP_GUI_NAME="Cross-platform MySQL/PostgreSQL client."
APP_VERSION=latest
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://teamsql.io/latest/linux
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install ProjectForge Java-based project management tool
APP_NAME=ProjectForge
APP_GUI_NAME="Cross-platform Java-based project management tool."
APP_VERSION=6.20.0
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/pforge/${APP_NAME}-application_${APP_VERSION}-RELEASE.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
mv ${APP_NAME}-application_${APP_VERSION}-RELEASE ${APP_NAME,,} 
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}-application-${APP_VERSION}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=/opt/${APP_NAME}/Screenshots/${APP_NAME}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Project;Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Sigil cross-platform ebook (EPUB) editor/creator from PPA
APP_NAME=Sigil
APP_GUI_NAME="Cross-platform ebook (EPUB) editor/creator."
APP_VERSION=0.9.9
APP_EXT=deb
sudo apt-add-repository -y ppa:ubuntuhandbook1/sigil
sudo apt-get update -y
sudo apt-get install -y sigil

# Install SpaceFM file manager from PPA
APP_NAME=SpaceFM
APP_GUI_NAME="GTK canonical file manager for Linux."
APP_VERSION=
APP_EXT=deb
sudo apt-add-repository -y ppa:mati75/spacefm
sudo apt-get update -y
sudo apt-get install -y spacefm udevil

# Install TexStudio LaTeX GUI editor from PPA
APP_NAME=TexStudio
APP_GUI_NAME="LaTeX GUI Editor."
APP_VERSION=
APP_EXT=deb
sudo apt-add-repository -y ppa:sunderme/texstudio
sudo apt-get update -y
sudo apt-get install -y texstudio

# Install Falcon Electron-based cross-platform SQL client from package
APP_NAME=falcon-sql-client
APP_GUI_NAME="Electron-based cross-platform SQL client."
APP_VERSION=2.4.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/plotly/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Cutterff FFMpeg video cutting utility from package
APP_NAME=Cutterff
APP_GUI_NAME="FFMpeg video cutting utility."
APP_VERSION=0.1
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i686
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-linux-${ARCH_TYPE}-static.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}*
mv ${APP_NAME,,}* ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/bin
PATH=/opt/${APP_NAME,,}/bin:$PATH; export PATH
/opt/${APP_NAME,,}/bin/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/bin
Exec=/opt/${APP_NAME,,}/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Multimedia;Video;
Keywords=FFMpeg;Video;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Tea Ebook reader from package
APP_NAME=tea-ebook
APP_GUI_NAME="Cross-platform Ebook (PDF and EPUB) reader."
APP_VERSION=N/A
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://app.${APP_NAME,,}.com/download/${ARCH_TYPE}/${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install PhotoFlare cross-platform Qt-based image viewer/editor from package
APP_NAME=PhotoFlare
APP_GUI_NAME="Cross-platform Qt-based image viewer/editor."
APP_VERSION=1.5
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://launchpad.net/photofiltre-lx/trunk/v${APP_VERSION}/+download/${APP_NAME}_CE_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Glyphr Studio Electron-based font editor
APP_NAME=Glyphr-Studio
APP_GUI_NAME="Cross-platform Electron-based font editor."
APP_VERSION=0.4.1
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME}-Desktop/releases/download/v${APP_VERSION}/Glyphr.Studio-linux-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/"Glyphr Studio"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/"Glyphr Studio"
#Icon=/opt/${APP_NAME,,}/parts/FreeLatin.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;
Keywords=Font;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Scrabble3D crossword game from package
APP_NAME=Scrabble3D
APP_GUI_NAME="Cross-platform crossword game."
APP_VERSION=N/A
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/scrabble/${APP_NAME}-${ARCH_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install VICE Versatile Commodore Emulator from source
APP_NAME=VICE
APP_GUI_NAME="Cross-platform retro Commodore computer emulator."
APP_VERSION=3.1
APP_EXT=tar.gz
sudo apt-get install -y build-essential autoconf bison flex libreadline-dev libxaw7-dev libpng-dev xa65 texinfo libpulse-dev texi2html libpcap-dev dos2unix libgtk2.0-cil-dev libgtkglext1-dev libvte-dev libvte-dev libavcodec-dev libavformat-dev libswscale-dev libmp3lame-dev libmpg123-dev yasm ffmpeg libx264-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-emu/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./autogen.sh && ./configure --enable-fullscreen --with-pulse --enable-ethernet --with-x --enable-gnomeui --enable-vte --enable-cpuhistory --with-resid --enable-external-ffmpeg && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=x64
#Icon=/opt/${APP_NAME,,}/parts/FreeLatin.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Emulator;
Keywords=Commodore;Emulator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Zeal Qt-based offline API documentation browser from source
APP_NAME=Zeal
APP_GUI_NAME="Cross-platform Qt-based offline API documentation browser."
APP_VERSION=0.5.0
APP_EXT=tar.gz
sudo apt-get install -y libarchive-dev libqt5webkit5-dev extra-cmake-modules libqt5x11extras5-dev libx11-xcb-dev libxcb-keysyms1-dev libsqlite3-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/zealdocs/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
mkdir -p build && cd build
cmake .. && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Dagri non-standard Tcl/Tk spreadsheet from source
APP_NAME=Dagri
APP_GUI_NAME="Non-standard Tcl/Tk spreadsheet."
APP_VERSION=1.4
APP_EXT=tar.gz
sudo apt-get install -y tcl8.6 tk8.6 tklib tkpng tk-tktray libtk-img tdom tcllib libsqlite3-tcl
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.jmos.net/download/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/stuff/icon/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=Spreadsheet;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Code::Blocks open-source, cross-platform, WX-based, free C, C++ and Fortran IDE
APP_NAME=codeblocks
APP_GUI_NAME="Open-source, cross-platform, WX-based, free C, C++ and Fortran IDE."
APP_VERSION=17.12
APP_EXT=tar.xz
# Code::Blocks requires at least version 1.62 of Boost C++ libraries
# TODO: Update to include check for version of Ubuntu before updating.
curl -o /tmp/libboost-dev.deb -J -L http://ubuntu.mirrors.tds.net/ubuntu/pool/main/b/boost1.62/libboost1.62-dev_1.62.0+dfsg-4_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libboost-dev.deb
curl -o /tmp/libboost-system-dev.deb -J -L http://ubuntu.mirrors.tds.net/ubuntu/pool/main/b/boost1.62/libboost-system1.62.0_1.62.0+dfsg-4_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libboost-system-dev.deb
curl -o /tmp/libhunspell.deb -J -L http://ubuntu.mirrors.tds.net/ubuntu/pool/main/h/hunspell/libhunspell-1.4-0_1.4.1-2build1_amd64.deb
sudo gdebi -n /tmp/libhunspell.deb
sudo apt-get install -y hunspell-en-us
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}_stable.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-common_${APP_VERSION}_all.deb
sudo gdebi -n /tmp/${APP_NAME,,}/lib${APP_NAME,,}0_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-contrib-common_${APP_VERSION}_all.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-libwxcontrib0_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/libwxsmithlib0_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/wxsmith-dev_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/wxsmith-headers_${APP_VERSION}_all.deb
sudo gdebi -n /tmp/${APP_NAME,,}/libwxsmithlib0-dev_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-contrib_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-contrib-common_${APP_VERSION}_all.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-dev_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}-headers_${APP_VERSION}_all.deb
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install news-indictor open-source Python desktop news notification tool from source
# Requires that NEWS_API_KEY environment variable be set to API key from https://newsapi.org/ (i.e., via $HOME/.profile).
APP_NAME=news-indicator
APP_GUI_NAME="Open-sourcePython desktop news notification tool."
APP_VERSION=master
APP_EXT=zip
sudo apt-get install -y python3-setuptools
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/0dysseas/${APP_NAME,,}/archive/${APP_VERSION}.zip
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
sudo python3 ./setup.py install

# Install hstr (a.k.a. 'hh') shell command history suggestion menu utility from PPA
sudo apt-add-repository -y ppa:ultradvorka/ppa
sudo apt-get update
sudo apt-get install -y hh
# Create 'hh' configuration file and call it from $HOME/.bashrc
cat >> $HOME/.config/hh_config << EOF
bind '"\e\C-r":"\C-ahh -- \C-j"'  # Bind 'hh' to <Ctrl>+<Alt>+R keyboard shortcut
export HH_CONFIG=hicolor   # Enable more colors for 'hh'
export HISTFILESIZE=10000
export HISTSIZE=${HISTFILESIZE}
export PROMPT_COMMAND="history -a; history -n; ${PROMPT_COMMAND}"  # Sync .bash_history with in-memory history
shopt -s histappend   # Force in-memory history to be appended to (instead of overwritten) .bash_history
export HISTCONTROL=ignorespace   # Add leading space(s) to exclude/ignore command in history
EOF
echo 'source $HOME/.config/hh_config' >> $HOME/.bashrc
source $HOME/.bashrc	# Reload Bash configuration

# Install bin64ed Qt-based Base64 file encoder/decoder from source
APP_NAME=bin64ed
APP_GUI_NAME="Cross-platform Qt-based Base64 file encoder/decoder."
APP_VERSION=2.0
APP_EXT=tar.bz2
sudo apt-get install -y qt5-default qt5-qmake
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/base64-binary/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
qtchooser -run-tool=qmake -qt=5 && make
sudo cp /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin  # No 'install' target for make
sudo cp /tmp/${APP_NAME,,}/images/info_icon.png /usr/local/share/pixmaps/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;System;
Keywords=Base64;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Legend of Edgar 2D platform adventure game from package
APP_NAME=edgar
APP_GUI_NAME="Cross-platform 2D platform adventure game."
APP_VERSION=1.28
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i686
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/riksweeney/${APP_NAME,,}/releases/download/${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}-1.${ARCH_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Universal Media Server (UMS) from package
APP_NAME=UMS
APP_VERSION=7.0.0-rc2
APP_EXT=tgz
sudo apt-get install -y mediainfo openjdk-8-jre dcraw vlc
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/unimediaserver/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}
sudo mv ${APP_NAME,,}-${APP_VERSION} /opt/${APP_NAME,,}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME}.sh /usr/local/bin/${APP_NAME,,}
ln -s /opt/${APP_NAME,,}/${APP_NAME}.sh $HOME/.config/autostart
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}

# Install PacmaniaQt Qt-based, C++ classic Pacman game from source
APP_NAME=PacmaniaQt
APP_GUI_NAME="Cross-platform Qt-based, C++ classic Pacman game."
APP_VERSION=v.1.0.0
APP_EXT=zip
sudo apt-get install -y qt5-default qt5-qmake qtmultimedia5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_Sources.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_Sources
qtchooser -run-tool=qmake -qt=5 && make
sudo cp /tmp/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_Sources/${APP_NAME,,} /usr/local/bin  # No 'install' target for make
sudo cp /tmp/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_Sources/resources/images/pac_map.png /usr/local/share/pixmaps/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Pacman;Arcade;Games;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Cumulonimbus Electron-based podcast player and organizer from package
APP_NAME=Cumulonimbus
APP_GUI_NAME="Cross-platform Electron-based podcast player and organizer."
APP_VERSION=1.9.3
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/z-------------/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Mozilla Rust programming language via installation shell script
# https://www.rust-lang.org/en-US/install.html
sudo apt-get install -y curl
curl -o /tmp/rustup-init.sh https://sh.rustup.rs -sSf
sh /tmp/rustup-init.sh -y
echo 'export PATH="$PATH:$HOME/.cargo/bin"' >> $HOME/.profile
source $HOME/.profile
cd $HOME
sudo rm -rf /tmp/rust*

# Install Norqualizer command-line audio normalizer/equalizer from source
APP_NAME=Norqualizer
APP_GUI_NAME="Cross-platform command-line audio normalizer/equalizer."
APP_VERSION=130
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
gcc norqualizer.c -o norqualizer
chmod a+x norqualizall
sudo cp norqualizall norqualizer /usr/local/bin
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Basilisk Browser cross-platform XUL-based modern web browser from package
APP_NAME=Basilisk
APP_GUI_NAME="Cross-platform XUL-based modern web browser."
APP_VERSION=latest
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i686
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://us.basilisk-browser.org/release/${APP_NAME,,}-${APP_VERSION}.${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/basilisk/browser/icons/mozicon128.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Web;Browser;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Pipette cross-platform screen color grabber from package
APP_NAME=Pipette
APP_GUI_NAME="Cross-platform screen color grabber."
APP_VERSION=N/A
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.zip -J -L https://www.sttmedia.com/downloads/PipetteDeb.zip
cd /tmp
dtrx /tmp/${APP_NAME,,}.zip
sudo gdebi -n /tmp/${APP_NAME,,}/${APP_NAME,,}*.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Searchmonkey GUI desktop search client from source
APP_NAME=Searchmonkey
APP_GUI_NAME="GUI desktop search client."
APP_VERSION=0.8.2
APP_EXT=tar.gz
sudo apt-get install -y autoconf automake
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
sh ./autogen.sh && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/pixmaps/searchmonkey/searchmonkey-48x48.png
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Search;Find;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install QVGE (Qt Visual Graph Editor) Qt-based 2-D visual graph editor from source
APP_NAME=QVGE
APP_GUI_NAME="Cross-platform Qt-based 2-D visual graph editor."
APP_VERSION=N/A
APP_EXT=git
sudo apt-get install -y qt5-qmake qt5-default libqt5x11extras5-dev
cd /tmp
git clone https://git.code.sf.net/p/${APP_NAME,,}/code ${APP_NAME,,}
cd /tmp/${APP_NAME,,}/code
qtchooser -run-tool=qmake -qt=5 && make 
sudo mkdir -p /usr/local/share/pixmaps
sudo cp ./src/Icons/AppIcon.png /usr/local/share/pixmaps/${APP_NAME,,}.png
sudo cp ./bin/${APP_NAME,,} /usr/local/bin
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Education;Accessories;
Keywords=Graphics;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install OpenProj cross-platform Java-based enterprise project management application from package
APP_NAME=OpenProj
APP_GUI_NAME="Cross-platform Java-based enterprise project management application."
APP_VERSION=1.4-2
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Functional Calculator Java-based multipurpose calculator
APP_NAME=FunctionalCalculator
APP_GUI_NAME="Java-based multipurpose calculator."
APP_VERSION=1.3
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
#Icon=/usr/local/${APP_NAME}/resources/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Science;Accessories;System;
Keywords=Math;Calculator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Flameshot Qt-based GUI/CLI screenshot capture tool from source
APP_NAME=Flameshot
APP_GUI_NAME="Qt-based GUI/CLI screenshot capture tool."
APP_VERSION=0.5.0
APP_EXT=tar.gz
sudo apt-get install -y qt5-qmake qt5-default qttools5-dev-tools
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/lupoDharkael/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Dibuja lightweight image editor similar to MS Paint from source
APP_NAME=Dibuja
APP_GUI_NAME="Lightweight image editor similar to MS Paint."
APP_VERSION=0.6.0
APP_EXT=tar.gz
sudo apt-get install -y intltool libgtk2.0-dev libbabl-dev libgegl-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://launchpad.net/${APP_NAME,,}/trunk/${APP_VERSION}/+download/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure --with-gegl-0.3 --libdir=/usr/include && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Miller text processor which combines functions of awk, sed, cut, join, and sort for name-indexed data such as CSV, TSV, and tabular JSON from source
APP_NAME=miller
APP_GUI_NAME="Text processor which combines functions of awk, sed, cut, join, and sort for name-indexed data such as CSV, TSV, and tabular JSON."
APP_VERSION=5.3.0
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/johnkerl/${APP_NAME,,}/releases/download/v${APP_VERSION}/mlr-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/mlr-${APP_VERSION}
./configure --prefix=/usr/local && make
# 'make install' doesn't work, so we manually install files
sudo cp doc/mlr.1 /usr/share/man/man1
sudo cp c/mlr c/mlrg c/mlrp c/parsing/lemon /usr/local/bin
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Easy Beginner's Environment for Qt (qtebe) simplified Qt-based C++ development environment from source
APP_NAME=qtebe
APP_GUI_NAME="Simplified Qt-based C++ development environment."
APP_VERSION=N/A
APP_EXT=sh
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/install_ebe.sh
cd /tmp
sh /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /usr/local/share/icons
sudo cp /tmp/ebe/icons/48/ebe.png /usr/local/share/icons
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=ebe
Icon=/usr/local/share/icons/ebe.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;Education;Other;
Keywords=C++;IDE;Programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Block Attack SDL Tetris clone from source
APP_NAME=BlockAttack
APP_GUI_NAME="SDL Tetris clone."
APP_VERSION=2.1.2
APP_EXT=tar.gz
sudo apt-get install -y libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev libphysfs-dev libboost-dev libboost-program-options-dev libutfcpp-dev cmake
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/Block%20Attack%20-%20Rise%20of%20the%20Blocks%20${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}*
./packdata.sh
cmake -DCMAKE_BUILD_TYPE=Release . && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install CrococryptFile Java-based file archiving and encryption utility
APP_NAME=CrococryptFile
APP_GUI_NAME="Java-based file archiving and encryption utility."
APP_VERSION=1.6
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/croco
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/croco
#Icon=/usr/local/${APP_NAME}/resources/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Encrypt;Decrypt;Archive;Crypto;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install BiglyBT Java-based (Azureus) GUI BitTorrent client
APP_NAME=BiglyBT
APP_GUI_NAME="Java-based (Azureus) GUI BitTorrent client."
APP_VERSION=1.4.0.0
APP_EXT=sh
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/BiglySoftware/${APP_NAME}/releases/download/v${APP_VERSION}/GitHub_${APP_NAME}_Installer.${APP_EXT}
sudo sh /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Java-- minimalist Eclipse-based IDE for learning Java programming
APP_NAME=JavaMM
APP_GUI_NAME="Minimalist Eclipse-based IDE for learning Java programming."
APP_VERSION=1.9.0-v20180112-1030
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-ide-${APP_VERSION}-linux.gtk.${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
/opt/${APP_NAME,,}/eclipse
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Java-- IDE (Eclipse)
Comment=${APP_GUI_NAME}
GenericName=Java-- IDE (Eclipse)
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/eclipse
Icon=/opt/${APP_NAME,,}/icon.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;Education;
Keywords=Java;Eclipse;IDE;Programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install FeedReader RSS news reader/aggregator from package
APP_NAME=FeedReader
APP_GUI_NAME="RSS news reader/aggregator."
APP_VERSION=1.6.2~ubuntu0.4.1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://launchpad.net/~eviltwin1/+archive/ubuntu/${APP_NAME,,}-stable/+files/${APP_NAME,,}_${APP_VERSION}_${ARCH_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install DB Tarzan Java-based database client from package
APP_NAME=DBTarzan
APP_GUI_NAME="Java-based database client."
APP_VERSION=1.09
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Koxinga Python-based board game similar to Jamaica
APP_NAME=Koxinga
APP_GUI_NAME="Python-based board game similar to Jamaica."
APP_VERSION=030
APP_EXT=tar.gz
sudo pip3 install pygame
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
Icon=/opt/${APP_NAME,,}/Images/back4.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Board;Game;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Crossword Express Java-based crossword/logic puzzle builder
APP_NAME=CrosswordExpress
APP_GUI_NAME="Java-based crossword/logic puzzle builder."
APP_VERSION=N/A
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.crauswords.com/program/${APP_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/Crossword-Express.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/Crossword-Express.jar
Icon=/opt/${APP_NAME,,}/graphics/crossword.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;Education;
Keywords=Word;Logic;Puzzle;Crossword;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Nathansoftware ConnectFour Java-based puzzle game
APP_NAME=ConnectFour
APP_GUI_NAME="ConnectFour Java-based puzzle game."
APP_VERSION=1.0.0
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/nathansoftware-games/${APP_NAME}-${APP_VERSION}-JAR.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
#Icon=/opt/${APP_NAME,,}/graphics/crossword.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;Education;
Keywords=Logic;Puzzle;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Galaxy Forces V2 2D multiplayer (and single-player versus AI) space shooter game 
APP_NAME=GalaxyV2
APP_GUI_NAME="2D multiplayer (and single-player versus AI) space shooter game."
APP_VERSION=1.85
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_linux_bin.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_linux_bin/* /opt/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME,,}/${ARCH_TYPE}/libportaudio.so /opt/${APP_NAME,,}/${ARCH_TYPE}/libportaudio.so.2
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/${ARCH_TYPE}
PATH=/opt/${APP_NAME,,}/${ARCH_TYPE}:$PATH; export PATH
/opt/${APP_NAME,,}/${ARCH_TYPE}/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/${ARCH_TYPE}
Exec=/opt/${APP_NAME,,}/${ARCH_TYPE}/${APP_NAME,,}
#Icon=/opt/${APP_NAME,,}/graphics/crossword.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;Education;
Keywords=Arcade;Retro;2D;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Git Town shell-based Git workflow enhancement from package
APP_NAME=Git-Town
APP_VERSION=6.0.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/Originate/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}-amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SMath Studio WYSIWYG math editor
APP_NAME=SMathStudio
APP_GUI_NAME="WYSIWYG math editor."
APP_VERSION=0_98_6588
APP_EXT=tar.gz
sudo apt-get install -y mono-runtime libmono-system-windows-forms4.0-cil
curl -o /tmp/${APP_NAME,,}.${APP_EXT} --referer https://en.smath.info/view/SMathStudio/summary -J -L https://smath.info/file/v4yoT/${APP_NAME}Desktop.${APP_VERSION}.Mono.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}/${ARCH_TYPE}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}_Desktop.exe
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME}_Desktop.exe
#Icon=/opt/${APP_NAME,,}/graphics/crossword.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Math;Science;Education;
Keywords=Calculator;Math;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Qt-TaskManager Qt-based to do list/time management tool from source
APP_NAME=Qt-TaskManager
APP_GUI_NAME="Qt-based to do list/time management tool."
APP_VERSION=N/A
APP_EXT=N/A
sudo apt-get install -y qt5-default
cd /tmp
git clone https://git.code.sf.net/p/${APP_NAME,,}/code ${APP_NAME,,}
cd /tmp/${APP_NAME,,}
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
sudo cp /tmp/${APP_NAME,,}/Icons/calendar.png /usr/share/pixmaps/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/bin
Exec=/usr/bin/${APP_NAME,,}
Icon=/usr/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=ToDo;Time;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install pcalc command-line programmer's calculator with support for HEX/DEC/OCT/BIN math from source
APP_NAME=pcalc
APP_GUI_NAME="Command-line programmer's calculator with support for HEX/DEC/OCT/BIN math."
APP_VERSION=4
APP_EXT=tar.gz
sudo apt-get install -y flex bison
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/vapier/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install bed cross-platform binary/hex data editor from package
APP_NAME=bed
APP_GUI_NAME="Cross-platform binary/hex data editor."
APP_VERSION=3.0.0
APP_EXT=deb
source /etc/lsb-release
# If our version of Ubuntu is *before* 17.04 (Zesty Zapus),
# then we need to install a couple of dependency packages.
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(ze|ar|bi)$ ]]; then
	curl -o /tmp/libhyperscan4.deb -J -L http://ubuntu.mirrors.tds.net/ubuntu/pool/universe/h/hyperscan/libhyperscan4_4.6.0-1_${KERNEL_TYPE}.deb
	sudo gdebi -n /tmp/libhyperscan4.deb
	curl -o /tmp/libre2-3.deb -J -L http://ubuntu.mirrors.tds.net/ubuntu/pool/universe/r/re2/libre2-3_20170101+dfsg-1_amd64.deb
	sudo gdebi -n /tmp/libre2-3.deb
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/binaryeditor/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QDirStat Qt-based GUI for viewing directory statistics from source
APP_NAME=QDirStat
APP_GUI_NAME="Qt-based GUI for viewing directory statistics."
APP_VERSION=1.4
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/shundhammer/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install usql cross-platform command-line SQL client in Go
APP_NAME=usql
APP_GUI_NAME="Cross-platform command-line SQL client in Go."
APP_VERSION=0.6.0
APP_EXT=tar.bz2
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/xo/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}-linux-amd64.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install IDLE SDL-based minimal Apple Lisa emulator from source
APP_NAME=IDLE
APP_GUI_NAME="SDL-based minimal Apple Lisa emulator."
APP_VERSION=N/A
APP_EXT=N/A
sudo apt-get install -y libsdl-dev git-svn
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/shundhammer/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
git svn clone https://svn.code.sf.net/p/idle-lisa-emu/code/ ${APP_NAME,,}
cd /tmp/${APP_NAME,,}
cp Makefile.unixsdl Makefile
make
sudo cp /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo cp /tmp/${APP_NAME,,}/lisa.ico /usr/share/icons/lisa_idle.ico
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/share/icons/lisa_idle.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Emulation;Games;Programming;
Keywords=Retro;Lisa;Mac;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CToy interactive C coding environment (REPL) from package
APP_NAME=CToy
APP_GUI_NAME="Interactive C coding environment (REPL) from package."
APP_VERSION=1.01
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://anael.maratis3d.com/${APP_NAME,,}/bin/${APP_NAME}-${APP_VERSION}-LINUX-x86_64.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-LINUX-x86_64/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}/${ARCH_TYPE}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/data/hello_world.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=REPL;C;Programming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CalcuDoku Qt-based KenKen puzzle game from source
APP_NAME=CalcuDoku
APP_GUI_NAME="Qt-based KenKen puzzle game."
APP_VERSION=N/A
APP_EXT=N/A
sudo apt-get install -y git-svn
cd /tmp
git svn clone https://svn.code.sf.net/p/${APP_NAME,,}/code/ ${APP_NAME,,}
cd /tmp/${APP_NAME,,}
# Need to insert "QT" module directive into Qt configuration file
sed -i~ '1iQT += core gui widgets printsupport' /tmp/${APP_NAME,,}/${APP_NAME,,}.pro
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install NotePuppy Qt-based minimalist text editor from source
APP_NAME=NotePuppy
APP_GUI_NAME="Qt-based minimalist text editor."
APP_VERSION=N/A
APP_EXT=N/A
sudo apt-get install -y git-svn
cd /tmp
git svn clone https://svn.code.sf.net/p/${APP_NAME,,}/code/ ${APP_NAME,,}
cd /tmp/${APP_NAME,,}
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install WebTorrent Desktop cross-platform Electron-based torrent streaming client from package
APP_NAME=WebTorrent-Desktop
APP_GUI_NAME="Cross-platform Electron-based torrent streaming client."
APP_VERSION=0.19.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Amp Rust-based command-line text editor from source
APP_NAME=Amp
APP_GUI_NAME="Cross-platform Rust-based command-line text editor."
APP_VERSION=0.3.2
APP_EXT=N/A
sudo apt-get install -y zlib1g-dev openssl libxcb1-dev cmake pkg-config
curl https://sh.rustup.rs -sSf | sh
cargo install --git https://github.com/jmacdonald/amp/ --tag 0.3.2

# Install Fractalscope Qt-based fractal explorer from source
APP_NAME=Fractalscope
APP_GUI_NAME="Cross-platform Qt-based fractal explorer."
APP_VERSION=1.1.0
APP_EXT=tar.gz
sudo apt-get install -y qt5-default yasm
# Install MPIR (Multiple Precision Integers and Rationals) LGPL C library
curl -o /tmp/mpir.tar.bz2 -J -L http://mpir.org/mpir-3.0.0.tar.bz2
cd /tmp && dtrx -n /tmp/mpir.tar.bz2 && cd /tmp/mpir/mpir-3.0.0
./configure --enable-gmpcompat && make && sudo make install
# Install GNU MPFR (multiple-precision floating-point computations with correct rounding) C Library
curl -o /tmp/mpfr.tar.xz -J -L http://www.mpfr.org/mpfr-current/mpfr-4.0.0.tar.xz
cd /tmp && dtrx -n /tmp/mpfr.tar.xz && cd /tmp/mpfr/mpfr-4.0.0
./configure --with-gmp-include=/usr/local/include --with-gmp-lib=/usr/local/lib && make && make check && sudo make install
# Install MPFR C++ library
curl -o /tmp/mpfrc++.zip -J -L http://www.holoborodko.com/pavel/wp-content/plugins/download-monitor/download.php?id=4
cd /tmp && dtrx -n /tmp/mpfrc++.zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-source.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-source/${APP_NAME}
cp /tmp/mpfrc++/mpreal.h /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-source/${APP_NAME}/gmp
qtchooser -run-tool=qmake -qt=5 CONFIG+=release Fractalscope.pro && make
sudo cp ./Fractalscope /usr/local/bin
sudo cp ./resources/icons/48x48/application.png /usr/share/icons/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME}
Icon=/usr/share/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Science;
Keywords=Math;Visualization;Fractals;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QFutureBuilder Qt-based goal-tracking tool from package
APP_NAME=QFutureBuilder
APP_GUI_NAME="Cross-platform Qt-based goal-tracking tool."
APP_VERSION=N/A
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/futurbuilder/linux_deb.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}/linux_deb/${APP_NAME,,}*.deb
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Pioneer space adventure game from package
APP_NAME=Pioneer
APP_GUI_NAME="Cross-platform space adventure game."
APP_VERSION=20180203
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/pioneerspacesim/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/data/icons/logo.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Adventure;Space;Games;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install mgrep multi-line grep utility
APP_NAME=mgrep
APP_VERSION=1.1.2
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/multiline-grep/${APP_NAME,,}-${APP_VERSION}-static.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Impressive PDF slide show presenter from source
APP_NAME=Impressive
APP_GUI_NAME="PDF slide show presenter."
APP_VERSION=0.12.0
APP_EXT=tar.gz
sudo apt-get install -y python-pygame python-imaging pdftk mupdf-tools xdg-utils mplayer ffmpeg
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python /opt/${APP_NAME,,}/${APP_NAME,,}.py \$1
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=python /opt/${APP_NAME,,}/${APP_NAME,,}.py \$1
#Icon=/opt/${APP_NAME,,}/data/icons/logo.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=PDF;Presentation;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Open-Numismat cross-platform PyQt-based coin-collection management tool from package
APP_NAME=Open-Numismat
APP_GUI_NAME="Cross-platform PyQt-based coin-collection management tool."
APP_VERSION=1.4.9
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install UNA social-media community management web-based tool (PHP/MySQL)
APP_NAME=UNA
APP_VERSION=9.0.0-RC5
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/una-io/${APP_NAME}-v.${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}-v.${APP_VERSION}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME,,}/storage ${WWW_HOME}/${APP_NAME,,}/tmp ${WWW_HOME}/${APP_NAME,,}/logs ${WWW_HOME}/${APP_NAME,,}/cache ${WWW_HOME}/${APP_NAME,,}/cache_public ${WWW_HOME}/${APP_NAME,,}/plugins_public ${WWW_HOME}/${APP_NAME,,}/inc
sudo chmod a+x ${WWW_HOME}/${APP_NAME,,}/plugins/ffmpeg/ffmpeg.exe
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/install &

# Install VeroRoute Qt-based PCB layout and routing tool from source
APP_NAME=VeroRoute
APP_GUI_NAME="Qt-based PCB layout and routing tool."
APP_VERSION=V1010
APP_EXT=zip
sudo apt-get install -y qt5-default
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_Src.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}_Src/Src
qtchooser -run-tool=qmake -qt=5 ${APP_NAME}.pro && make
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}_Src/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python /opt/${APP_NAME,,}/${APP_NAME} \$1
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME}
#Icon=/usr/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Science;Other;
Keywords=Electronics;PCB;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}
