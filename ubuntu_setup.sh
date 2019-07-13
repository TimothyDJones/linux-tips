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

# Checks to see if tool/command exists
# https://github.com/kennylevinsen/dotfiles/blob/master/setup
function tool_installed() {
	which $1 1>/dev/null 2>/dev/null
	ret=$?
	printf '%b' "[Tool installation check for $1: $ret]\n" >> $LOGFILE
	return $ret
}

# Set some parameters for general use
LOGFILE=/var/log/ubuntu_setup.log
WWW_HOME=/var/www/html


# Add some necessary non-default packages
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get autoremove -f -y
sudo apt-get install -y build-essential dtrx curl wget checkinstall gdebi \
	openjdk-8-jre software-properties-common \
	mc python3-pip htop synaptic

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
	git git-svn \
	nodejs

# Install Yarn package manager (must install NodeJS from package repo first)
curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update && sudo apt-get install -y yarn

# Install MongoDB from official repository
# https://docs.mongodb.com/manual/tutorial/install-mongodb-on-ubuntu/
APP_NAME=mongodb
APP_VERSION=3.4
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
source /etc/lsb-release
# If Ubuntu version is above 16.04 (Xenial), then we use 16.04.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(ya|ze|ar|bi)$ ]]; then
	DISTRIB_CODENAME=xenial
fi
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
mysql-server mysql-workbench mycli libcurl3

# Enable 'modrewrite' Apache module
sudo a2enmod rewrite
sudo service apache2 restart  ## Alternate command is 'sudo apachectl restart'

# Add current user to 'www-data' group
sudo usermod -a -G www-data ${USER}

# Change owner of /var/www/html directory to www-data
sudo chown -R www-data:www-data ${WWW_HOME}

# Enable PHP 5.6 as default version of PHP (if PHP 7.0+ gets installed, as well).
sudo a2dismod php7.0 ; sudo a2enmod php5.6 ; sudo service apache2 restart ; echo 1 | sudo update-alternatives --config php

# Create script to allow switching between PHP 5.6 and 7.2
cat > /tmp/phpv << EOL
#! /bin/sh
if [ "\$1" = "5.6" ] || [ "\$1" = "5" ]; then
    sudo a2dismod php7.2
    sudo a2enmod php5.6
    sudo service apache2 restart
    echo 1 | sudo update-alternatives --config php
elif [ "\$1" = "7.2" ] || [ "\$1" = "7" ]; then
    sudo a2dismod php5.6
    sudo a2enmod php7.2
    sudo service apache2 restart
    echo 0 | sudo update-alternatives --config php
else
    echo "Invalid option!"
    echo "phpv 5.6 | 7.2"
fi
EOL
sudo mv /tmp/phpv /usr/local/bin
sudo chmod +x /usr/local/bin/phpv

# Create simple 'phpinfo' script in main web server directory
# Note: Must create file in /tmp and then move because 'sudo cat...' is allowed.
sudo cat > /tmp/phpinfo.php << EOL
<?php
	phpinfo();
?>
EOL
sudo mv /tmp/phpinfo.php ${WWW_HOME}
sudo chown www-data:www-data ${WWW_HOME}/phpinfo.php
xdg-open http://localhost/phpinfo.php &

# Disable XDebug on CLI to prevent warnings when installing/running Composer
sudo phpdismod -s cli xdebug

# Install PHP Composer as global utility
php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
sudo php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('/tmp/composer-setup.php');"
rm -f /tmp/composer-setup.php
sudo chmod +x /usr/local/bin/composer
sudo chown -R $USER:$USER $HOME/.composer

# Install Prestissimo Composer plugin for parallel downloads.
sudo php /usr/local/bin/composer global require hirak/prestissimo

# Install latest PhpMyAdmin version via Composer
# https://docs.phpmyadmin.net/en/latest/setup.html#composer
cd ${WWW_HOME}
sudo php /usr/local/bin/composer create-project phpmyadmin/phpmyadmin --repository-url=https://www.phpmyadmin.net/packages.json --no-dev
sudo chown -R www-data:www-data ${WWW_HOME}/phpmyadmin
xdg-open http://localhost/phpmyadmin/setup &
cd $HOME

# Install PHP 7.2 (optional)
sudo apt-get install -y php7.2-bcmath php7.2-bz2 php7.2-cli php7.2-common php7.2-curl php7.2-gd php7.2-json php7.2-mbstring  php7.2-mysql php7.2-readline php7.2-sqlite3 php7.2-xml php7.2-xsl php7.2-zip php-xdebug \
libapache2-mod-php7.2 libapache2-mod-xsendfile \
mysql-server mysql-workbench mycli 

# Install Jupyter Notebook support for Python 3
sudo apt-get install -y python3 python3-ipython
sudo pip3 install jupyter
# Add application menu icon to open new Jupyter notebook
cat > /tmp/jupyter.desktop << EOF
[Desktop Entry]
Name=Jupyter Notebook
Comment=Open a new Jupyter Python notebook.
GenericName=Jupyter
Exec=jupyter-notebook
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Jupyter;Python;
EOF
sudo mv /tmp/jupyter.desktop /usr/share/applications/

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
APP_VERSION=1.12.4
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
APP_VERSION=x36
QT_VERSION=qt5.5.1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
sudo apt-get install -y qt5-default
curl -o /tmp/libpng12-0.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libpng12-0.deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION}.${ARCH_TYPE}-${QT_VERSION}.${APP_EXT}
curl -o /tmp/${APP_NAME,,}-system.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION}.${ARCH_TYPE}-${QT_VERSION}-system.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/bin
PATH=/opt/${APP_NAME,,}/bin:\$PATH; export PATH
/opt/${APP_NAME,,}/bin/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
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
APP_VERSION=0.9.60_1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}   # '-n' is non-interactive mode for gdebi
rm -f /tmp/${APP_NAME}.${APP_EXT}
APP_NAME=firetools
APP_VERSION=0.9.58_1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/firejail/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}   # '-n' is non-interactive mode for gdebi
rm -f /tmp/${APP_NAME}.${APP_EXT}
cd $HOME

# Install Stacer Linux monitoring tool
# Must download specific version, because unable to get 'latest' from Sourceforge to work.
APP_NAME=stacer
APP_VERSION=1.0.9
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

# Install Vivaldi web browser (stable version) from package
APP_NAME=Vivaldi
APP_VERSION=2.6.1566.40-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-stable_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.vivaldi.com/stable/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -f /tmp/*${APP_NAME,,}*

# Install CudaText editor from Debian package
# http://www.uvviewsoft.com/cudatext/
APP_NAME=CudaText
APP_VERSION=1.84.1.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_gtk2_amd64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L --referer https://www.fosshub.com/${APP_NAME}.html "https://www.fosshub.com/${APP_NAME}.html?dwl=${FILE_NAME}.${APP_EXT}"
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
rm -f /tmp/${APP_NAME,,}*

# Enable GetDeb repository for your version of Ubuntu
source /etc/os-release   # This config file contains Ubuntu version details.
DEB_STRING='deb http://archive.getdeb.net/ubuntu '${UBUNTU_CODENAME}'-getdeb apps'
sudo echo $DEB_STRING > /etc/apt/sources.list.d/getdeb.list
wget -q -O- http://archive.getdeb.net/getdeb-archive.key | sudo apt-key add -
sudo apt-get update -y

# Install Albert application launcher from Debian package
# http://sourcedigit.com/22129-linux-quick-launcher-ubuntu-albert-best-linux-launcher/
APP_NAME=Albert
APP_VERSION=0.14.21
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
source /etc/lsb-release
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_${DISTRIB_RELEASE}/${KERNEL_TYPE}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
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

# Install CopyQ clipboard manager from Debian package
APP_NAME=CopyQ
APP_VERSION=3.9.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_Debian_9.0-1_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
sudo ln -s /usr/local/share/applications/${APP_NAME}.desktop $HOME/.config/autostart/  # Configure CopyQ to autostart on system launch
rm -f /tmp/${APP_NAME,,}*

# Install Steel Bank Common Lisp (SBCL) from source
APP_NAME=sbcl
APP_VERSION=1.5.4
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
APP_VERSION=0.9.99.3
APP_EXT=tar.bz2
sudo apt-get install -y qt5-default libqt5multimedia5 qtmultimedia5-dev libqt5xmlpatterns5-dev libqt5webkit5-dev libqt5svg5-dev cmake  # Qt5 development packages needed to build from source
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install MyNotes simple Python-based "sticky notes" tool from source
APP_NAME=MyNotes
APP_VERSION=2.4.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y python3-tk tk-tktray python3-pil python3-pil.imagetk
source /etc/lsb-release
# If our version of Ubuntu is *after* 17.04 (Zesty Zapus),
# then we use Python 3 EWMH package from distribution repository.
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(ar|bi)$ ]]; then
	sudo apt-get install -y python3-ewmh
else
	# Install python-ewmh package from Zesty Zebra distribution.
	curl -o /tmp/python3-ewmh_0.1.5-1_all.deb -J -L http://ftp.osuosl.org/pub/ubuntu/pool/universe/p/python-ewmh/python3-ewmh_0.1.5-1_all.deb
	sudo gdebi -n /tmp/python3-ewmh_0.1.5-1_all.deb
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/my-notes/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/*${APP_NAME}*
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
APP_VERSION=1.14.0
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
APP_VERSION=3.6
APP_EXT=tgz
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls  # Install required packages
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
cd /tmp/${APP_pNAME}/${APP_NAME}-${APP_VERSION}
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
APP_NAME=KeePassXC
APP_VERSION=2.4.3
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-src
LIBCRYPT20_VERSION=1.8.4-5
curl -o /tmp/libgcrypt20-dev.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libg/libgcrypt20/libgcrypt20-dev_${LIBCRYPT20_VERSION}ubuntu1_${KERNEL_TYPE}.deb
curl -o /tmp/libgcrypt20.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libg/libgcrypt20/libgcrypt20_${LIBCRYPT20_VERSION}ubuntu1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libgcrypt20.deb
sudo gdebi -n /tmp/libgcrypt20-dev.deb
sudo apt-get install -y libcrypto++-dev libxi-dev libmicrohttpd-dev libxtst-dev qttools5-dev-tools cmake libargon2-0-dev libqrencode-dev libsodium-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/keepassxreboot/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}
mkdir build && cd build
cmake .. -DWITH_TESTS=OFF && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install NewBreeze file manager from source
APP_NAME=NewBreeze
APP_VERSION=v3-rc5
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}%20${APP_VERSION}
sudo apt-get install -y libmagic-dev zlib1g-dev liblzma-dev libbz2-dev libarchive-dev xdg-utils libpoppler-qt5-dev libsource-highlight-dev libpoppler-qt5-dev libdjvulibre-dev libqscintilla2-qt5-dev 
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/*${APP_NAME}*
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

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
APP_VERSION=6.0.2
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

# Install BeeBEEP LAN messenger from package
APP_NAME=BeeBEEP
APP_GUI_NAME="Cross-platform secure LAN messenger."
APP_VERSION=5.6.2
if [[ $(uname -m | grep '64') ]]; then  # Check for 64-bit Linux kernel
	KERNEL_TYPE=amd64
	APP_VERSION=5.6.2
else    # Otherwise use version for 32-bit kernel
	KERNEL_TYPE=i386
	APP_VERSION=5.6.2
fi
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-qt4-${KERNEL_TYPE}
sudo apt-get install -y qt4-default libqt4-xml libxcb-screensaver0 libavahi-compat-libdnssd1 libphonon4 libhunspell-dev phonon-backend-gstreamer
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Networking;Accessories;
Keywords=Messenger;Productivity;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

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
APP_VERSION=2.6.1
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

# Install QXmlEdit XML editor and XSD viewer from source
APP_NAME=QXmlEdit
APP_VERSION=0.9.13
APP_EXT=tgz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-src
sudo apt-get install -y libqt5xmlpatterns5-dev libqt5svg5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n ${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}
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

# Install Jailer cross-platform Java database browser and editor from package
APP_NAME=Jailer
APP_GUI_NAME="Cross-platform Java database browser and editor"
APP_VERSION=8.7.8
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME,,}/* /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=/opt/${APP_NAME,,}/docs/favicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;SQL;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install ZinjaI C++ IDE
APP_NAME=zinjai
APP_VERSION=20180718
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
APP_VERSION=2-2.3.1
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME}.${APP_EXT}
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

# Install Madedit-Mod text editor from Debian package
APP_NAME=madedit-mod
APP_VERSION=0.4.16-1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}_Ubuntu18.04.${APP_EXT}
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

# Install Makagiga Java-based PIM/RSS feed reader from package
APP_NAME=Makagiga
APP_GUI_NAME="Cross-platform Java-based PIM/RSS feed reader."
APP_VERSION=6.6
APP_EXT=7z
FILE_NAME=${APP_NAME,,}-linux-x64-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}/* /opt/${APP_NAME,,}
sudo rm -rf /opt/${APP_NAME,,}/java-windows* /opt/${APP_NAME,,}/*.exe /opt/${APP_NAME,,}/*.bat
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}.sh
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
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.sh
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;Internet;
Keywords=PIM;RSS;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
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
APP_VERSION=2.8.8-r2304-1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
cd /tmp
sudo gdebi -n ${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install HTTP Test Tool (httest) from source
APP_NAME=httest
APP_VERSION=2.4.24
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y libapr1-dev libaprutil1-dev libpcre3-dev help2man zlib1g-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/htt/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
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
APP_VERSION=2018.10.14
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_ubuntu_all_${KERNEL_TYPE}
source /etc/os-release   # This config file contains Ubuntu version details.
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
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

# Install Skychart planetarium package from Debian package
APP_NAME=Skychart
APP_VERSION=4.1.1-3958
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
# libpasastro (Pascal astronomical library) is dependency for Skychart.
curl -o /tmp/libpasastro.${APP_EXT} -J -L https://downloads.sourceforge.net/libpasastro/libpasastro_1.1-20_${KERNEL_TYPE}.${APP_EXT}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
sudo gdebi -n libpasastro.${APP_EXT}
sudo gdebi -n ${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/libpasastro.* /tmp/${APP_NAME}* /tmp/${APP_NAME,,}*

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

# Install Tagstoo file tag manager from AppImage
APP_NAME=Tagstoo
APP_GUI_NAME="File tag manager"
APP_VERSION=2.0.1
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://ayera.dl.sourceforge.net/project/${APP_NAME,,}/${APP_NAME}%20${APP_VERSION}%20${ARCH_TYPE}/${APP_NAME}.${APP_EXT}
cd /tmp
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv ${APP_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
# Create icon in menus
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=/opt/${APP_NAME}/share/${APP_NAME}/welcome/images/liteide128.xpm
Type=Application
StartupNotify=false
Terminal=false
Categories=Accessories;System;
Keywords=tag;tagging;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
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
APP_VERSION=0.10
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

# Install AVFS virtual file system from source
APP_NAME=AVFS
APP_VERSION=1.1.0
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libfuse-dev libarchive-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/avf/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Worker File Manager (For AVFS support install AVFS above.)
APP_NAME=worker
APP_VERSION=4.0.0
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y liblua5.3-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/workerfm/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
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
APP_VERSION=4.7.5
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

# Install Brave web browser (release channel) from package
APP_NAME=Brave-Browser
APP_VERSION=0.62.51
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/brave/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install reCsvEditor CSV editor from package
APP_NAME=reCsvEditor
APP_VERSION=0.99.0
APP_EXT=zip
FILE_NAME=${APP_NAME}_Installer_${APP_VERSION}.jar
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo java -jar /tmp/${FILE_NAME}/${FILE_NAME}  # Launches GUI installer
sudo ln -s /usr/local/RecordEdit/reCsvEd/bin/runCsvEditor.sh /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ZenTao project management tool from package
APP_NAME=ZenTaoPMS
APP_VERSION=11.5.2.int
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
APP_VERSION=0.11.8
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/BoostIO/boost-releases/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf ${APP_NAME}*

# Install Red Notebook cross-platform journey/diary/PIM from source
APP_NAME=rednotebook
APP_VERSION=2.10
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

# Install Super Productivity To Do List and task manager from Debian package
APP_NAME=superProductivity
APP_VERSION=2.5.8
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/johannesjo/super-productivity/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
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
APP_VERSION=1.4
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
APP_VERSION=6.3.7
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
APP_VERSION=60
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
APP_VERSION=1.5.1
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
APP_VERSION=2.0p1
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
APP_VERSION=8.1.1
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
APP_VERSION=2.2.1
APP_EXT=deb
source /etc/os-release   # This config file contains Ubuntu version details.
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/urlget/${APP_NAME}_${APP_VERSION}-0ubuntu0~${UBUNTU_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
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

# Install Hyper JS/HTML/CSS Terminal from Debian package
APP_NAME=Hyper
APP_VERSION=3.0.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/hyper.mirror/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install QOwnNotes from PPA
sudo add-apt-repository -y ppa:pbek/qownnotes
sudo apt-get update -y
sudo apt-get install -y qownnotes

# Install Tiki Wiki CMS/groupware
APP_NAME=tiki
APP_VERSION=19.1
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
APP_VERSION=6-19.7
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
APP_VERSION=12c-0.2.4
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
APP_VERSION=1.9.4
APP_EXT=exe
	if [[ $(uname -m | grep '64') ]]; then  # Check for 64-bit Linux kernel
		ARCH_TYPE=linux-64
	else    # Otherwise use version for 32-bit kernel
		ARCH_TYPE=linux
	fi
curl -o /tmp/${APP_NAME} -J -L https://downloads.sourceforge.net/swissfileknife/${APP_NAME}${APP_VERSION//./}-${ARCH_TYPE}.${APP_EXT}
sudo chmod a+x /tmp/${APP_NAME}
sudo mv /tmp/${APP_NAME} /usr/local/bin

# Install Freeplane mind-mapping tool from package
APP_NAME=freeplane
APP_VERSION=1.7.9
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
APP_VERSION=5.5.0
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
APP_NAME=Leo-Editor
APP_GUI_NAME="Cross-platform, Python-based editor/IDE, outliner, and PIM."
APP_VERSION=5.8-b1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y python3-pyqt5
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/launchLeo.py
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=python3 /opt/${APP_NAME,,}/launchLeo.py
Icon=/opt/${APP_NAME,,}/leo/Icons/LeoApp.ico
Type=Application
StartupNotify=true
Terminal=true
Categories=Programming;Development;Accessories;
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
APP_VERSION=6.3.0
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
APP_NAME=GroupOffice
APP_VERSION=6.4.31
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-php-71
sudo apt-get install -y libwbxml2-utils tnef
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/group-office/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir ${WWW_HOME}/${APP_NAME,,}
sudo mv ${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo touch ${WWW_HOME}/${APP_NAME,,}/config.php
sudo mkdir -p /home/${APP_NAME,,}
sudo mkdir -p /tmp/${APP_NAME,,}
sudo chmod -R 0777 /home/${APP_NAME,,} /tmp/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,} /home/${APP_NAME,,} /tmp/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/ &
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install ZenTao project management suite (manual installation)
APP_NAME=zentao
APP_VERSION=10.2.stable_1
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
APP_VERSION=1.13
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
APP_NAME=XSchem
APP_VERSION=2.9.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y bison flex libxpm-dev libx11-dev tcl8.6-dev tk8.6-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://repo.hu/projects/${APP_NAME,,}/releases/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/src
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QPDF PDF utility from source
APP_NAME=QPDF
APP_VERSION=8.4.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y zlib1g-dev libjpeg62-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
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
APP_VERSION=9.1
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
APP_VERSION=4.22.0
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

# Install Task Coach to do list manager from Debian package
APP_NAME=TaskCoach
APP_VERSION=1.4.6-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
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
APP_VERSION=3.9.1
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-standard.${APP_EXT}
sudo java -jar /tmp/${APP_NAME,,}.${APP_EXT}
sudo ln -s /usr/local/${APP_NAME,,}/${APP_NAME,,}.sh /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Only Office Desktop Editor from package
APP_NAME=onlyoffice-desktopeditors
APP_VERSION=5.1
APP_EXT=deb
FILE_NAME=${APP_NAME}_${KERNEL_TYPE}
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(ze|ar|bi)$ ]]; then
	DISTRIB_RELEASE=16
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(vi|wi)$ ]]; then
	DISTRIB_RELEASE=14
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://sourceforge.net/projects/desktopeditors/files/v${APP_VERSION}/ubuntu/${DISTRIB_RELEASE:0:2}/${FILE_NAME}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

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
APP_VERSION=0.4.3
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
APP_VERSION=2.1.8
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

# Install Printed Circuit Board (PCB) Layout Tool from source
APP_NAME=pcb
APP_VERSION=4.2.0
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
APP_VERSION=2.4.0
APP_EXT=appimage
sudo apt-get install -y intltool libgtkglext1-dev libgd-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-Lite.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Agora Project groupware application (manual installation)
APP_NAME=agora_project
APP_VERSION=3.5.0
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
APP_VERSION=08-08-18
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
APP_VERSION=2.12
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
APP_VERSION=3.10.1
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
APP_VERSION=3.1.1
APP_EXT=tar.gz
sudo apt-get install -y python3-pyqt5
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}
sudo python3 /tmp/${APP_NAME,,}/${APP_NAME}/install.py
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Python/Qt-based tree-structured notepad
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
APP_VERSION=1.4.1
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
APP_VERSION=10.0
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
APP_VERSION=2.12.14
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

# Install myNetPCB Java-based PCB layout and schematic capture tool
APP_NAME=myNetPCB
APP_VERSION=7.58
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION//./_}.${APP_EXT}
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
APP_VERSION=19.07.07
APP_EXT=txz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
FILE_NAME=${APP_NAME,,}-linux-${ARCH_TYPE}-${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/mltframework/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME} /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME}.app/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Cross-platform Video Editor
GenericName=Video Editor
Exec=/opt/${APP_NAME,,}/${APP_NAME}.app/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/${APP_NAME}.app/share/icons/hicolor/64x64/apps/org.shotcut.Shotcut.png
Path=/opt/${APP_NAME,,}/${APP_NAME}.app
Type=Application
StartupNotify=true
Terminal=false
Categories=Video;Multimedia;
Keywords=Video;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Nightcode Clojure/Clojurescript IDE from package
APP_NAME=Nightcode
APP_VERSION=2.6.0
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
APP_VERSION=1.2019.7
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
APP_NAME=PDFSam
APP_VERSION=4.0.3-1
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=all
	APP_VERSION=4.0.1-1
fi
FILE_NAME=${APP_NAME}_${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Voya Media video, music, and picture player from Debian package
APP_NAME=VoyaMedia
APP_VERSION=3.1-200
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=noarch
	APP_VERSION=free-3.0-700
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}.${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Geoserver as stand-alone binary
# http://docs.geoserver.org/latest/en/user/installation/linux.html
APP_NAME=geoserver
APP_VERSION=2.15.1
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
APP_VERSION=17.1
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
APP_GUI_NAME="Java-based RSS news aggregator client"
APP_VERSION=11
APP_EXT=zip
FILE_NAME=${APP_NAME}%20${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}${APP_VERSION}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}${APP_VERSION}.jar
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
APP_VERSION=190
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
APP_VERSION=2.9-1unofficial
APP_EXT=deb
source /etc/lsb-release
if [ "${DISTRIB_CODENAME}" -eq "bionic" ]; then
	DISTRIB_CODENAME=artful;   # Use Artful Aardvark (17.10) files for 18.04.
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://repos.codelite.org/ubuntu/pool/universe/w/${APP_NAME}/${APP_NAME}_${APP_VERSION}.${DISTRIB_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

APP_NAME=codelite
APP_VERSION=12.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://repos.codelite.org/ubuntu/pool/universe/c/${APP_NAME}/${APP_NAME}_${APP_VERSION}unofficial.${DISTRIB_CODENAME}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Buttercup JavaScript/Electron desktop password manager from package
APP_NAME=buttercup-desktop
APP_VERSION=1.15.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/buttercup/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Tuitter Electron-based, cross-platform minimalist Twitter client from package
APP_NAME=Tui
APP_GUI_NAME="Electron-based, cross-platform minimalist Twitter client."
APP_VERSION=0.4.17
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
Comment=${APP_GUI_NAME}
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
APP_VERSION=0.38.6-0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.giuspen.com/software/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Raccoon Java-based Google Play Store and APK downloader utility from package
APP_NAME=Raccoon
APP_VERSION=4.7.0
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -k -L http://${APP_NAME,,}.onyxbits.de/sites/${APP_NAME,,}.onyxbits.de/files/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=Java-based Google Play Store and APK downloader utility
GenericName=${APP_NAME}
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Android;APK;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

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
APP_VERSION=0.12.14
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
APP_VERSION=3.7.1
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
APP_VERSION=3.5.12.606
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
APP_VERSION=3.3.10
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

# Install Insomnia REST client from Debian package
APP_NAME=Insomnia
APP_VERSION=6.5.3
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://updates.insomnia.rest/downloads/ubuntu/latest
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
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
APP_VERSION=2.2.5
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
APP_VERSION=1.2.3528
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
APP_VERSION=0.19.6
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://sushib.me/dl/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Rufas Slider puzzle game from source
APP_NAME=rufasslider
APP_GUI_NAME="Klotsky-style slider puzzle game."
APP_VERSION=8jan19
APP_EXT=7z
FILE_NAME=rsl${APP_VERSION}
sudo apt-get install -y qttools5-dev qttools5-dev-tools cmake
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/rslid
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
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/rufaslider
Icon=/opt/${APP_NAME}/data/nexslider.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Puzzle;Slider;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
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
APP_VERSION=3.7-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-bookmark-manager/${APP_NAME,,}_${APP_VERSION}_ubuntu16.04.${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JSoko Java-based Sokoban puzzle game from package
APP_NAME=JSoko
APP_VERSION=1.85
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}applet/${APP_NAME}_${APP_VERSION}_linux.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Crystal Facet UML tool from package
APP_NAME=crystal-facet-uml
APP_VERSION=1.13.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
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
APP_VERSION=0.10.4
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
APP_VERSION=2.7.0
APP_EXT=tar.bz2
sudo apt-get install -y python3-tk qt5-default libqt5svg5-dev libqt5scripttools5 qtscript5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 && make && sudo make install
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
APP_VERSION=1.2
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
APP_VERSION=0.15.7
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://riot.im/packages/debian/pool/main/r/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Angry IP Scanner from package
APP_NAME=ipscan
APP_VERSION=3.5.5
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SimulIDE electronic circuit simulator
APP_NAME=SimulIDE
APP_VERSION=0.3.10-SR2
#APP_MINOR_VERSION=SR1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=Lin64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=Lin32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp
mv ${APP_NAME}_${APP_VERSION}-${ARCH_TYPE} ${APP_NAME,,}
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
APP_GUI_NAME="Minimalist console text editor."
APP_VERSION=4.2
APP_EXT=tar.xz
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y libncurses5-dev libncursesw5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://nano-editor.org/dist/v4/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
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
APP_VERSION=08-08-18
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
APP_NAME=Terminus
APP_VERSION=1.0.77
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-linux
curl -o /tmp/${FILE_NAME,,}.${APP_EXT} -J -L https://github.com/Eugeny/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

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
APP_VERSION=10.5
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://apt.nanolx.org/pool/main/b/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}-1nano_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JEditor Java-based text editor
APP_NAME=jEditor
APP_VERSION=0.4.25
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
APP_VERSION=2.2
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
APP_VERSION=2.4-1
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
APP_VERSION=1.3.3
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
APP_GUI_NAME="Console text editor"
APP_VERSION=1.8.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y make gcc libncurses5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/craigbarnes/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make -j8 && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
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
APP_VERSION=3.8_3.8.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}uml/${APP_NAME,,}-open-source${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Dooble web browser from package
APP_NAME=Dooble
APP_VERSION=2019.07.07
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
APP_VERSION=0.3.14
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
APP_VERSION=3.5.2
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
APP_VERSION=19.5
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
APP_VERSION=0.10.0
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
APP_VERSION=1.9.0-1
APP_EXT=deb
sudo apt-get install openjdk-11-jre 
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}* /tmp/*${APP_NAME}*

# Install phpCollab web-based collaboration and project management tool
# http://www.phpcollab.com/
APP_NAME=phpCollab
APP_VERSION=v2.6.4
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
APP_VERSION=2.6.1
APP_EXT=tar.xz
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
APP_VERSION=30
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
APP_VERSION=2.3.1-10
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

# Install JPDFViewer cross-platform Java-based PDF viewer/reader
APP_NAME=JPDFViewer
APP_GUI_NAME="Cross-platform Java-based PDF viewer/reader."
APP_VERSION=N/A
APP_EXT=jar
# Check to ensure Java installed
if ! [ -x "$(command -v java)" ]; then
	echo 'Error. Java is not installed. ' >&2
	echo 'Installing Java...'
	sudo apt-get install -y openjdk-8-jre
fi
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.${APP_EXT}
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
APP_VERSION=18.5.0
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
APP_VERSION=7.6
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
APP_VERSION=r5.5.11
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
APP_VERSION=6.25.0
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
APP_VERSION=0.4
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
APP_VERSION=0.6.1
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
APP_VERSION=1.5
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

# Install Damn Cool Editor (DCE) Tcl/Tk plain text editor from source
APP_NAME=DCE
APP_GUI_NAME="Tcl/Tk plain text editor."
APP_VERSION=0.14
APP_EXT=tar.gz
sudo apt-get install -y tcl8.6 tk8.6 tklib tkpng tk-tktray libtk-img tdom tcllib libsqlite3-tcl
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.jmos.net/download/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
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
Categories=Office;Accessories;
Keywords=Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Code::Blocks open-source, cross-platform, WX-based, free C, C++ and Fortran IDE
APP_NAME=codeblocks
APP_GUI_NAME="Open-source, cross-platform, WX-based, free C, C++ and Fortran IDE."
APP_VERSION=17.12-1
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

# Install CPod (formerly Cumulonimbus) Electron-based podcast player and organizer from package
APP_NAME=CPod
APP_GUI_NAME="Cross-platform Electron-based podcast player and organizer."
APP_VERSION=1.17.1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/z-------------/cumulonimbus/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
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
APP_VERSION=0.8.3
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
APP_VERSION=0.5.3
APP_EXT=7z
sudo apt-get install -y qt5-qmake qt5-default libqt5x11extras5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-src.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-src/code
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
APP_VERSION=0.8.0
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
APP_VERSION=5.4.0
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
APP_VERSION=2.3.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev libphysfs-dev libboost-dev libboost-program-options-dev libutfcpp-dev cmake
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
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
APP_VERSION=2.0.0.0
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
APP_VERSION=1.16
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
APP_VERSION=1.1.0
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
APP_VERSION=0.99.6839
APP_EXT=tar.gz
sudo apt-get install -y mono-runtime libmono-system-windows-forms4.0-cil
curl -o /tmp/${APP_NAME,,}.${APP_EXT} --referer https://en.smath.info/view/SMathStudio/summary -J -L https://smath.info/file/v4yoT/${APP_NAME}Desktop.${APP_VERSION//./_}.Mono.${APP_EXT}
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
APP_VERSION=0.20.0-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Amp Rust-based command-line text editor from source
APP_NAME=Amp
APP_GUI_NAME="Cross-platform Rust-based command-line text editor."
APP_VERSION=0.5.1
APP_EXT=N/A
sudo apt-get install -y zlib1g-dev openssl libxcb1-dev cmake pkg-config libssl-dev
curl https://sh.rustup.rs -sSf | sh
cargo install --git https://github.com/jmacdonald/${APP_NAME,,}/ --tag ${APP_VERSION}

# Install Fractalscope Qt-based fractal explorer from source
APP_NAME=Fractalscope
APP_GUI_NAME="Cross-platform Qt-based fractal explorer."
APP_VERSION=1.3.5
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
APP_VERSION=10.0.0-B2
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
APP_VERSION=V1.52
APP_EXT=zip
sudo apt-get install -y qt5-default
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION//./}_Src.${APP_EXT}
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

# Install TupiTube cross-platform 2D animation tool for amateur artists from package
APP_NAME=TupiTube
APP_GUI_NAME="Cross-platform 2D animation tool for amateur artists."
APP_VERSION=0.2.11
APP_EXT=sh
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/tupi2d/${APP_NAME,,}_${APP_VERSION}_linux_${ARCH_TYPE}.${APP_EXT}
cd /tmp
sudo sh /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}_${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}.desk \$1
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
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.desk
Icon=/opt/${APP_NAME,,}/share/pixmaps/${APP_NAME,,}.desk.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Graphics;Other;
Keywords=Graphics;Animation;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install TraySearch Java-based cross-platform quick search utility
APP_NAME=TraySearch
APP_GUI_NAME="Java-based cross-platform quick search utility."
APP_VERSION=5.3.0
APP_EXT=jar
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
#Icon=/opt/${APP_NAME,,}/graphics/crossword.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Search;Productivity;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Abricotine cross-platform Electron-based Markdown editor with inline preview from package
APP_NAME=Abricotine
APP_GUI_NAME="Cross-platform Electron-based Markdown editor with inline preview."
APP_VERSION=0.6.0
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/brrd/${APP_NAME}/releases/download/${APP_VERSION}/${APP_NAME}-${APP_VERSION}-ubuntu-debian-${ARCH_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install INSTEAD Interactive Fiction interpreter/player from source
APP_NAME=INSTEAD
APP_GUI_NAME="Interactive Fiction interpreter/player."
APP_VERSION=3.2.2
APP_EXT=tar.gz
sudo apt-get install -y liblua5.1-dev libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev libsdl2-mixer-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
export PREFIX=/usr/local && ./configure.sh && make && sudo make install 
sudo rm -rf /usr/local/share/applications/instead.desktop
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/sdl-instead
Icon=/usr/local/share/pixmaps/sdl_instead.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Games;Adventure;Text;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install PyPref Python-based Russian card game Preferans
APP_NAME=PyPref
APP_GUI_NAME="Python-based Russian card game Preferans."
APP_VERSION=2.34
APP_EXT=zip
sudo apt-get install -y python-tk
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/python-pref/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python2 /opt/${APP_NAME,,}/${APP_NAME,,}.pyw
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
Exec=python2 /opt/${APP_NAME,,}/${APP_NAME,,}.pyw
Icon=/opt/${APP_NAME,,}/big/back.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Games;Cards;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install phpSysInfo web-based Linux system information utility
APP_NAME=phpSysInfo
APP_VERSION=3.3.0
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}/* ${WWW_HOME}/${APP_NAME,,}
sudo cp ${WWW_HOME}/${APP_NAME,,}/phpsysinfo.ini.new ${WWW_HOME}/${APP_NAME,,}/phpsysinfo.ini
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod a+x ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+r ${WWW_HOME}/${APP_NAME,,}
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install PICSimLab wxWidgets-based real-time PIC and Arduino microcontroller simulator laboratory from package
APP_NAME=PICSimLab
APP_GUI_NAME="Cross-platform real-time PIC and Arduino microcontroller simulator laboratory."
APP_VERSION=0.7
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/picsim/${APP_NAME,,}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install x-whnb self-contained web-based hierarchical notebook (similar to Cherrytree)
APP_NAME=x-whnb
APP_GUI_NAME="Self-contained web-based hierarchical notebook (similar to Cherrytree)."
APP_VERSION=v0.5.3
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}.${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=${WWW_HOME}
Exec=xdg-open http://localhost/${APP_NAME,,}/${APP_NAME,,}.html
#Icon=/opt/${APP_NAME,,}/big/back.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Internet;
Keywords=Productivity;Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}/${APP_NAME,,}.html &

# Install Text Trix Java-based minimalist text editor with HTML and RTF support
APP_NAME=TextTrix
APP_GUI_NAME="Java-based cross-platform minimalist text editor with HTML and RTF support."
APP_VERSION=1.0.2
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Programming;Development;
Keywords=Editor;Text;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install JSound Java-based audio player and editor
APP_NAME=JSound
APP_GUI_NAME="Java-based audio player and editor."
APP_VERSION=4.0
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/jortegasound/${APP_NAME,,}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/bin
PATH=/opt/${APP_NAME,,}/bin:\$PATH; export PATH
/opt/${APP_NAME,,}/bin/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/bin
Exec=/opt/${APP_NAME,,}/bin/${APP_NAME,,}
#Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Multimedia;Audio;
Keywords=Audio;Player;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install PeaZip cross-platform archive management utility from package
APP_NAME=PeaZip
APP_GUI_NAME="Cross-platform archive management utility."
APP_VERSION=6.8.1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.LINUX.GTK2-2_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install viewPDF Qt-based PDF viewer/editor
APP_NAME=viewPdf
APP_GUI_NAME="Qt-based PDF viewer/editor."
APP_VERSION=0.2.2
APP_EXT=N/A
sudo apt-get install -y libpoppler-qt5-1
curl -o /tmp/${APP_NAME,,} -J -L https://sourceforge.net/projects/${APP_NAME,,}/files/${APP_NAME}${APP_VERSION}/download
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=PDF;Viewer;Reader;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QFlashCards Qt-based flash card editor/viewer
APP_NAME=QFlashCards
APP_GUI_NAME="Qt-based flash card editor/viewer."
APP_VERSION=1.4
APP_EXT=N/A
curl -o /tmp/${APP_NAME,,} -J -L https://sourceforge.net/projects/${APP_NAME,,}/files/v${APP_VERSION}/${APP_NAME}/download
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Education;
Keywords=Flashcards;Viewer;Reader;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Flare SDL-based 2-D adventure RPG from source
APP_NAME=Flare
APP_GUI_NAME="SDL-based 2-D adventure RPG."
APP_VERSION=1.10
APP_EXT=tar.gz
sudo apt-get install -y libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev cmake
curl -o /tmp/${APP_NAME,,}-engine.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-game/${APP_NAME,,}-engine-v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}-engine.${APP_EXT}
cd /tmp/${APP_NAME,,}-engine/${APP_NAME,,}-engine-v${APP_VERSION}
cmake . && make && sudo make install
curl -o /tmp/${APP_NAME,,}-game.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-game/${APP_NAME,,}-game-v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}-game.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -r /tmp/${APP_NAME,,}-game/${APP_NAME,,}-game-v${APP_VERSION}/* /opt/${APP_NAME,,}
sudo ln -s /usr/local/share/games/${APP_NAME,,}/mods/default /opt/${APP_NAME,,}/mods
sudo ln -s /usr/local/games/${APP_NAME,,} /opt/${APP_NAME,,}
sudo rm -f /usr/local/share/applications/${APP_NAME,,}.desktop
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/usr/local/share/icons/hicolor/scalable/apps/${APP_NAME,,}.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Adventure;RPG;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install 16p Mahjong Python/Pygame tile puzzle game
APP_NAME=16mj
APP_GUI_NAME="Mahjong Python/Pygame tile puzzle game."
APP_VERSION=034
APP_EXT=tar.gz
sudo pip3 install pygame
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/mahjong-16p/${APP_NAME,,}_py${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}_py/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/p${APP_NAME,,}.py
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
Exec=python3 /opt/${APP_NAME,,}/p${APP_NAME,,}.py
Icon=/opt/${APP_NAME,,}/Image/Mjt7.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Mahjong;Puzzle;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Scintilla/SciTE GTK text editor from source
APP_NAME=SciTE
APP_GUI_NAME="GTK text editor."
APP_VERSION=4.2.0
APP_EXT=tgz
sudo apt-get install -y pkg-config libglib2.0-dev libgtk2.0-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/scintilla/${APP_NAME,,}${APP_VERSION//./}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/scintilla/gtk
make
cd /tmp/${APP_NAME,,}/${APP_NAME,,}/gtk
make && sudo make install
sudo ln -s /usr/bin/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install pgFormatter PostgreSQL and other DB SQL syntax beautifier from source
APP_NAME=pgFormatter
APP_GUI_NAME="PostgreSQL and other DB SQL syntax beautifier."
APP_VERSION=3.0
APP_EXT=tar.gz
sudo apt-get install -y git-svn unixodbc unixodbc-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}/* /opt/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME,,}/pg_format /usr/local/bin/pgformat
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Hydrus Python-based client/server media tagging and sharing tool from package
APP_NAME=Hydrus
APP_GUI_NAME="Python-based client/server media tagging and sharing tool."
APP_VERSION=296
APP_EXT=tar.gz
sudo apt-get install -y git-svn unixodbc unixodbc-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/hydrusnetwork/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME}.Network.${APP_VERSION}.-.Linux.-.Executable.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}\ network/* /opt/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME,,}/client /usr/local/bin/hydrus_client
sudo ln -s /opt/${APP_NAME,,}/server /usr/local/bin/hydrus_server
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Visual Paradigm Community Edition Eclipse-based UML and architecture diagramming tool from package
APP_NAME=Visual-Paradigm
APP_GUI_NAME="Eclipse-based UML and architecture diagramming tool."
APP_MAJOR_VERSION=15.0
APP_MINOR_VERSION=20180801
APP_EXT=sh
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=Linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=Linux32
fi
sudo apt-get install -y git-svn unixodbc unixodbc-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} --referer https://www.${APP_NAME,,}.com/download/community.jsp -J -L https://usa6.${APP_NAME,,}.com/${APP_NAME,,}/vpce${APP_MAJOR_VERSION}/${APP_MINOR_VERSION}/Visual_Paradigm_CE_${APP_MAJOR_VERSION//./_}_${APP_MINOR_VERSION}_Linux64.${APP_EXT}
sudo sh /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install InfiniTex Electron-based LaTeX source and WYSIWYG editor from AppImage
APP_NAME=InfiniTex
APP_GUI_NAME="Electron-based LaTeX source and WYSIWYG editor."
APP_VERSION=0.9.15
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-${APP_VERSION}-x86_64
sudo apt-get install -y git-svn unixodbc unixodbc-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/fetacore/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=LaTeX;Word;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Zettlr Electron-based Markdown editor with built-in preview from Debian package
APP_NAME=Zettlr
APP_GUI_NAME="Electron-based Markdown editor with built-in preview."
APP_VERSION=1.2.3
APP_EXT=deb
FILE_NAME=${APP_NAME}-linux-x64-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Bitwarden Electron-based desktop/online password manager from package
APP_NAME=Bitwarden
APP_GUI_NAME="Electron-based desktop/online password manager."
APP_VERSION=1.3.0
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/desktop/releases/download/v1.0.5/${APP_NAME}-${APP_VERSION}-amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SmartGit Java-based Git/SVN/Mercurial GUI client from package
APP_NAME=SmartGit
APP_GUI_NAME="Java-based Git/SVN/Mercurial GUI client."
APP_VERSION=17.1.5
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://www.syntevo.com/downloads/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION//./_}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install i-doit web-based CMDB and IT Documentation Repository
APP_NAME=i-doit
APP_VERSION=1.10.1
APP_EXT=zip
DB_NAME=${APP_NAME//-/}
DB_USER=${APP_NAME//-/}
DB_PASSWORD=${APP_NAME//-/}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME//-/}-open-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod a+x ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+r ${WWW_HOME}/${APP_NAME,,}
sudo find . -type d -name \* -exec chmod 775 {} \;
sudo find . -type f -exec chmod 664 {} \;
sudo chmod 774 controller 
sudo chmod 774 tenants 
sudo chmod 774 import 
sudo chmod 774 updatecheck 
sudo chmod 774 *.sh 
sudo chmod 774 setup/*.sh
sudo cp /etc/php/5.6/apache2/php.ini /tmp/php.ini && sudo chown ${USER}:${USER} /tmp/php.ini
echo '^M' >> /tmp/php.ini
echo 'max_input_vars = 10000' >> /tmp/php.ini
sed -i.bak 's@post_max_size = 8M@post_max_size = 128M@g' /tmp/php.ini
sudo cp /tmp/php.ini /etc/php/5.6/apache2/php.ini && sudo chown root:root /etc/php/5.6/apache2/php.ini
sudo service apache2 restart
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install QMPlay2 Qt-based multimedia player from package
APP_NAME=QMPlay2
APP_GUI_NAME="Qt-based multimedia player."
APP_VERSION=18.03.02
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/zaps166/${APP_NAME}/releases/download/${APP_VERSION}/${APP_NAME,,}-ubuntu-amd64-${APP_VERSION}-1.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Standard Notes Electron-based secure notepad from App Image
APP_NAME=Standard-Notes
APP_GUI_NAME="Electron-based secure notepad."
APP_VERSION=3.0.2
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=i386
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86_64
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/standardnotes/desktop/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s -f /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Disk;Utility;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Monte Note Electron-based Markdown notepad from package
APP_NAME=Monte-Note
APP_GUI_NAME="Electron-based Markdown notepad."
APP_VERSION=0.1.0b
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/urbanogardun/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Java_console cross-platform Java shell from source
APP_NAME=Java_console
APP_GUI_NAME="Cross-platform Java shell."
APP_VERSION=2.1.2
APP_EXT=tar.gz
sudo apt-get install -y openjdk-8-jdk
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/javaconsole222/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}
./compile.sh
cd /tmp/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME} /opt
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:\$PATH; export PATH
java -jar /opt/${APP_NAME}/${APP_NAME}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Simutron AVR/Arduino simulator GUI/IDE from package
APP_NAME=Simutron
APP_GUI_NAME="Cross-platform AVR/Arduino simulator GUI/IDE."
APP_VERSION=1.0.1-SR1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=Linux-x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=Lin32
fi
sudo apt-get install -y qt5-default cutecom gtkwave libelf1
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
LD_LIBRARY_PATH=/opt/${APP_NAME,,}/lib:\$LD_LIBRARY_PATH; export LD_LIBRARY_PATH
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
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Electronics;Education;Other;
Keywords=Electronics;Microcontroller;AVR;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SC Calculator cross-platform scientific calculator implemented in C++, Java, and JavaScript from package
APP_NAME=SCCalculator
APP_GUI_NAME="Cross-platform scientific calculator implemented in C++, Java, and JavaScript."
APP_VERSION=1.13
APP_EXT=zip
sudo apt-get install -y qt5-default cutecom gtkwave libelf1
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/calculator${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/java/calculator.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/java
Exec=java -jar /opt/${APP_NAME,,}/java/calculator.jar
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Programming;Math;Science;Other;
Keywords=Math;Calculator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Tiled Qt-based map tile editor from source
APP_NAME=Tiled
APP_GUI_NAME="Cross-platform Qt-based map tile editor."
APP_VERSION=1.2.4
APP_EXT=tar.gz
sudo apt-get install -y qt5-default qttools5-dev-tools zlib1g-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}%20${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/*${APP_NAME,,}*
mkdir -p build && cd build
qtchooser -run-tool=qmake -qt=5 ../${APP_NAME,,}.pro && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install iTop web-based ITSM and CMDB tool
APP_NAME=iTop
APP_VERSION=2.4.1-3714
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
sudo apt-get install -y php5.6-soap graphviz
sudo service apache2 restart
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/web/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install gpsim cross-platform simulator for Microchip's PIC microcontrollers from source
APP_NAME=gpsim
APP_GUI_NAME="Cross-platform simulator for Microchip's PIC microcontrollers."
APP_VERSION=0.30.0
APP_EXT=tar.gz
sudo apt-get install -y libreadline-dev libpopt-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure && make && sudo make install
sudo cp /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}/doc/metadata/${APP_NAME,,}.png /usr/local/share/icons
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Math;Science;Other;Engineering;
Keywords=Microcontroller;Electronics;Simulation;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Pidgin cross-platform, multi-service instant messenger (IM) utility from source
APP_NAME=Pidgin
APP_GUI_NAME="Cross-platform , multi-service instant messenger (IM) utility."
APP_VERSION=2.13.0
APP_EXT=tar.bz2
# Remove if installed from package
sudo apt-get remove pidgin*
sudo apt-get install -y libxss-dev intltool libgtkspell-dev libxml2-dev libidn1*-dev libavahi-glib-dev libavahi-client-dev libdbus-glib-1-dev libnm-glib-dev libgnutls28-dev libnss3-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure --disable-gstreamer --disable-vv --disable-meanwhile --disable-perl --disable-tcl && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install ZimmerSCP Java-based, cross-platform, 3-pane SCP (Secure Copy) utility from package
APP_NAME=ZimmerSCP
APP_GUI_NAME="Java-based, cross-platform, 3-pane SCP (Secure Copy) utility."
APP_VERSION=1.7
APP_EXT=zip
sudo apt-get install -y qt5-default cutecom gtkwave libelf1
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION//./_}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}logo.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Network;Accessories;
Keywords=SCP;FTP;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Joy of Text (JOT) minimalist text editor from package
APP_NAME=JOT
APP_GUI_NAME="Cross-platform minimalist text editor."
APP_VERSION=2.4.2
APP_EXT=tz
sudo ln -s /lib/x86_64-linux-gnu/libncurses.so.5 /lib/x86_64-linux-gnu/libncurses.so.6
sudo ln -s /lib/x86_64-linux-gnu/libtinfo.so.5 /lib/x86_64-linux-gnu/libtinfo.so.6
sudo ln -s /lib/x86_64-linux-gnu/libncursesw.so.5 /lib/x86_64-linux-gnu/libncursesw.so.6
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/joyoftext/${APP_NAME,,}_v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/v${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}/bin/lin64:\$PATH; export PATH
JOT_HOME=/opt/${APP_NAME,,}; export JOT_HOME
/opt/${APP_NAME,,}/bin/lin64/jot "$@"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Writer2LaTeX Java-based, command-line converters from OpenDocument Format (ODF/LibreOffice) to LaTeX/BibTeX, XHTML, XHTML+MathML and EPUB from package
APP_NAME=Writer2LaTeX
APP_GUI_NAME="Java-based, command-line converters from OpenDocument Format (ODF/LibreOffice) to LaTeX/BibTeX, XHTML, XHTML+MathML and EPUB."
APP_VERSION=1.6.1
APP_EXT=zip
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION//./}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}${APP_VERSION//./}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar "$@"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
sudo ln -s /usr/local/bin/${APP_NAME,,} /usr/local/bin/w2l
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install RHash cross-platform, shell-based tool for calculating and verifying various hash sums for files from source
APP_NAME=RHash
APP_GUI_NAME="Cross-platform, shell-based tool for calculating and verifying various hash sums for files."
APP_VERSION=1.3.8
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-src.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install MarkText Electron-based Markdown editor from Snap package
APP_NAME=MarkText
APP_GUI_NAME="Cross-platform, Electron-based Markdown editor."
APP_VERSION=0.12.25
APP_EXT=snap
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo snap install --dangerous /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CryptMount encrypted file system mounting tool from package
APP_NAME=CryptMount
APP_GUI_NAME="Encrypted file system mounting tool."
APP_VERSION=5.3-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install fmedia cross-platform fast media player/recorder/converter from package
APP_NAME=fmedia
APP_GUI_NAME="Cross-platform fast media player/recorder/converter."
APP_VERSION=0.37
APP_EXT=tar.xz
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://${APP_NAME,,}.firmdev.com/${APP_NAME,,}-${APP_VERSION}-linux-${KERNEL_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,}-0/* /opt/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Tixati cross-platform BitTorrent P2P file sharing client from package
APP_NAME=Tixati
APP_GUI_NAME="Cross-platform BitTorrent P2P file sharing client."
APP_VERSION=2.58-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://download2.${APP_NAME,,}.com/download/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install ZPlayer cross-platform Java-based audio player from package
APP_NAME=ZPlayer
APP_GUI_NAME="Cross-platform Java-based audio player."
APP_VERSION=3.5.1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://sites.google.com/site/zankuroplayer/${APP_NAME,,}.deb
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Still Yet Another Sokoban cross-platform puzzle game from source
APP_NAME=Sokoban
APP_GUI_NAME="Cross-platform puzzle game."
APP_VERSION=2.0.2
APP_EXT=zip
sudo apt-get install -y libsdl1.2-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/sya-${APP_NAME,,}/${APP_NAME,,}-source-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
make && sudo make install
sudo cp ./data/sokoban/icon/application_icon.ico /usr/local/share/icons/${APP_NAME,,}.ico
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/syasokoban
Icon=/usr/local/share/icons/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Sokoban;Puzzle
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install LPub3D cross-platform LDraw editor for LEGO style digital building instructions from package
APP_NAME=LPub3D
APP_GUI_NAME="Cross-platform LDraw editor for LEGO style digital building instructions."
APP_VERSION=2.2.0.0.795_20180316-xenial
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}-${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Typora cross-platform, Electron-based Markdown editor/notepad with code syntax support from package
APP_NAME=Typora
APP_GUI_NAME="Cross-platform, Electron-based Markdown editor/notepad with code syntax support."
APP_VERSION=N/A
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
sudo apt-get install -y libsdl1.2-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://${APP_NAME,,}.io/linux/${APP_NAME}-linux-${ARCH_TYPE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}-linux-${ARCH_TYPE}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/opt/${APP_NAME,,}/resources/app/asserts/icon/icon_32x32@2x.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Notepad;Editor;Markdown
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Notepadqq simple text editor similar to Notepad++ from package
APP_NAME=Notepadqq
APP_GUI_NAME="Simple text editor similar to Notepad++."
APP_VERSION=1.2.0-1
APP_EXT=deb
source /etc/lsb-release
# If our version of Ubuntu is *after* 17.04 (Zesty Zapus),
# then we use the 17.04 package from PPA.
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(ar|bi)$ ]]; then
	DISTRIB_CODENAME=zesty
fi
curl -o /tmp/${APP_NAME,,}-common.${APP_EXT} -J -L https://launchpad.net/~${APP_NAME,,}-team/+archive/ubuntu/${APP_NAME,,}/+files/${APP_NAME,,}-common_${APP_VERSION}~${DISTRIB_CODENAME}1_all.${APP_EXT}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://launchpad.net/~${APP_NAME,,}-team/+archive/ubuntu/${APP_NAME,,}/+files/${APP_NAME,,}_${APP_VERSION}~${DISTRIB_CODENAME}1_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}-common.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install CWED minimalist web-based C/C++ IDE
APP_NAME=CWED
APP_GUI_NAME="Minimalist web-based C/C++ IDE."
APP_VERSION=0.8.5
APP_EXT=tar
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y build-essential gdb make
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo ./setcwmod.sh
sudo ./install.sh
cd /tmp
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=${WWW_HOME}/${APP_NAME,,}
Exec=xdg-open http://localhost/cwed/
Icon=${WWW_HOME}/${APP_NAME,,}/res/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Development;Programming;
Keywords=C;C++;Programming;IDE;Editor
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Grisbi cross-platform, GTK+ 3-based personal finance tool from source
APP_NAME=Grisbi
APP_GUI_NAME="Cross-platform, GTK+ 3-based personal finance tool from source."
APP_VERSION=1.1.92
APP_EXT=tar.bz2
sudo apt-get install -y libgtk-3-dev libgsf-1-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install jdbsee cross-platform command-line utility for database actions via JDBC from package
APP_NAME=jdbsee
APP_GUI_NAME="Cross-platform command-line utility for database actions via JDBC."
APP_VERSION=0.4.1-1
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME}_${APP_VERSION}_all.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install QtChess cross-platform, peer-to-peer Qt/OpenGL chess program from source
APP_NAME=QtChess
APP_GUI_NAME="Cross-platform , peer-to-peer Qt/OpenGL chess program."
APP_VERSION=master
APP_EXT=zip
sudo apt-get install -y qt5-default
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 ${APP_NAME,,}.pro && make
# No target for 'make install', so must copy files explicitly
sudo cp ./${APP_NAME} /usr/local/bin
sudo cp ./Images/chess.ico /usr/local/share/icons/${APP_NAME,,}.ico
sudo ln -s -f /usr/local/bin/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/icons/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Chess
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install BlueJ educational Java IDE from package
APP_NAME=BlueJ
APP_GUI_NAME="Cross-platform educational Java IDE."
APP_VERSION=4.1.2
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.${APP_NAME,,}.org/download/files/${APP_NAME}-linux-${APP_VERSION//./}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Microsoft PowerShell cross-platform shell and scripting environment from package
# https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-powershell-core-on-macos-and-linux?view=powershell-6
APP_NAME=PowerShell
APP_GUI_NAME="Cross-platform shell and scripting environment."
APP_VERSION=6.2.1
APP_EXT=deb
source /etc/lsb-release
# PowerShell is only supported on LTS releases 
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(bi|xe)$ ]]; then
	curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}-1.ubuntu.${DISTRIB_RELEASE}_amd64.${APP_EXT}
	sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
else
	echo "Your version (" ${DISTRIB_RELEASE} ") of Ubuntu does not support installing PowerShell from package.  We will install from binary distribution."
	sudo apt-get install -y libunwind8 libicu*
	curl -o /tmp/${APP_NAME,,}.tar.gz https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/${APP_NAME,,}-${APP_VERSION}-linux-x64.tar.gz
	cd /tmp
	dtrx -n /tmp/${APP_NAME,,}.tar.gz
	sudo mv /tmp/${APP_NAME,,} /opt
	sudo chmod +x /opt/${APP_NAME,,}/pwsh
	sudo ln -s /opt/${APP_NAME,,}/pwsh /usr/local/bin/pwsh
	sudo ln -s /opt/${APP_NAME,,}/pwsh /usr/local/bin/powershell
fi
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Oni cross-platform GUI text editor based on Neovim and React/Redux from package
APP_NAME=Oni
APP_GUI_NAME="Cross-GUI text editor based on Neovim and React/Redux."
APP_VERSION=0.3.6
APP_EXT=deb
# Neovim must be installed to use Oni
sudo apt-get install -y python-dev python-pip python3-dev python3-pip
sudo add-apt-repository -y ppa:neovim-ppa/stable
sudo apt-get -y update
sudo apt-get install -y neovim
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/onivim/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME}-${APP_VERSION}-amd64-linux.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Rodent applications, including Rodent File Manager, from source
APP_NAME=xffm
APP_GUI_NAME="Rodent applications, including Rodent File Manager."
APP_VERSION=5.3.16.3
APP_EXT=tar.bz2
sudo apt-get install -y libzip-dev librsvg2-dev libmagic-dev
cd /tmp
FILE_NAME=libtubo0-5.0.15
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT} && cd /tmp/${FILE_NAME}
./configure && make && sudo make install && cd /tmp
FILE_NAME=libdbh2-5.0.22
curl -o /tmp/${FILE_NAME}.tar.gz -J -L https://downloads.sourceforge.net/dbh/${FILE_NAME}.tar.gz
dtrx -n /tmp/${FILE_NAME}.tar.gz && cd /tmp/${FILE_NAME}
./configure && make && sudo make install && cd /tmp
FILE_NAME=librfm5-5.3.16.4
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT} && cd /tmp/${FILE_NAME}
./configure && make && sudo make install && cd /tmp
FILE_NAME=rodent-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT} && cd /tmp/${FILE_NAME}
./configure && make && sudo make install && cd /tmp
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Remote Operation On Files (ROOF) FTP client from package
APP_NAME=ROOF
APP_GUI_NAME="Cross-platform educational Java IDE."
APP_VERSION=2.2.27
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_amd64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install jGameBase Java version of GameBase emulator frontend and database utility from package
APP_NAME=jGameBase
APP_GUI_NAME="Java version of GameBase emulator frontend and database utility."
APP_VERSION=0.68.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Flextype flat-file content management system (CMS)
APP_NAME=Flextype
APP_VERSION=0.2.0
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
sudo apt-get install -y php5.6-soap graphviz
sudo service apache2 restart
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n ${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME,,}/site
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install GoldenDict cross-platform Qt-based dictionary client from source
APP_NAME=GoldenDict
APP_GUI_NAME="Cross-platform Qt-based dictionary client."
APP_VERSION=1.5.0-RC2
APP_EXT=tar.gz
sudo apt-get install -y git pkg-config build-essential qt5-qmake libvorbis-dev zlib1g-dev libhunspell-dev x11proto-record-dev qtdeclarative5-dev libqtwebkit-dev libxtst-dev liblzo2-dev libbz2-dev libao-dev libavutil-dev libavformat-dev libtiff5-dev libeb16-dev libqt5webkit5-dev libqt5svg5-dev libqt5x11extras5-dev qttools5-dev qttools5-dev-tools
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 ${APP_NAME,,}.pro && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install FreeMAN extensible, cross-platform, Electron-based file manager for power users from package
APP_NAME=FreeMAN
APP_GUI_NAME="Extensible, cross-platform, Electron-based file manager for power users."
APP_VERSION=0.8.1
APP_EXT=snap
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/matthew-matvei/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_amd64.${APP_EXT}
sudo snap install --dangerous /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install PAGE drag-and-drop GUI generator for Python and Tkinter from source
APP_NAME=PAGE
APP_GUI_NAME="Drag-and-drop GUI generator for Python and Tkinter."
APP_VERSION=4.24
APP_EXT=tgz
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
sudo /opt/${APP_NAME,,}/configure
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/page-icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Python;Tk;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Easy Disk Cleaner cross-platform disk maintenance utility from package
APP_NAME=Easy-Disk-Cleaner
APP_GUI_NAME="Cross-platform disk maintenance utility."
APP_VERSION=2.0.0
APP_EXT=zip
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}-linux.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,} /opt
sudo chmod +x /opt/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-x86_64.AppImage
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-x86_64.AppImage /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}-x86_64.AppImage
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Disk;Utility;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Yoda Python-based personal assistant to terminal from source
APP_NAME=Yoda
APP_GUI_NAME="Python-based personal assistant to terminal."
APP_VERSION=0.2.0
APP_EXT=tar.gz
sudo apt-get install -y python-setuptools python-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/yoda-pa/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}
sudo python2 ./setup.py install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Pinguy ISO Builder live CD creator for Ubuntu-based distributions from package
APP_NAME=PinguyBuilder
APP_GUI_NAME="Live CD creator for Ubuntu-based distributions."
APP_VERSION=N/A
APP_EXT=deb
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ (ze|ar|bi)$ ]]; then  # 17.04, 17.10, 18.04
	APP_VERSION=5.2-1_all
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ (xe|ya)$ ]]; then  # 16.04, 16.10
	APP_VERSION=4.3-8_all-beta
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ (vi|wi)$ ]]; then  # 15.04, 15.10
	APP_VERSION=15.10
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ (tr|ut)$ ]]; then  # 14.04, 14.10
	APP_VERSION=3.3-7_all
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/pinguy-os/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Bodhi Builder live CD creator for Ubuntu-based distributions from Debian package
APP_NAME=BodhiBuilder
APP_GUI_NAME="Live CD creator for Ubuntu-based distributions."
APP_VERSION=N/A
APP_EXT=deb
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ (bi|co)$ ]]; then  # 18.04
	APP_VERSION=2.18.5_all
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ (xe|ya|ze|ar)$ ]]; then  # 16.04, 16.10, 17.04, 17.10
	APP_VERSION=2.2.7_all
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ (tr|ut|vi|wi)$ ]]; then  # 14.04, 14.10, 15.04, 15.10
	APP_VERSION=2.1.6_all
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Geogebra Java-based cross-platform math education and visualization tool from package
APP_NAME=Geogebra
APP_GUI_NAME="Java-based cross-platform math education and visualization tool."
APP_VERSION=6
APP_EXT=deb
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L http://www.${APP_NAME,,}.org/download/deb.php?arch=${KERNEL_TYPE}&ver=${APP_VERSION}
sudo gdebi -n /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install yEd Java-based cross-platform diagramming tool from package
APP_NAME=yEd
APP_GUI_NAME="Java-based cross-platform diagramming tool."
APP_VERSION=3.17.2
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://yworks.com/resources/${APP_NAME,,}/demo/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${FILE_NAME,,}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar -classpath /opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar -classpath /opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Icon=/opt/${APP_NAME,,}/icons/yicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Diagramming;Flowcharts;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install BlueGriffon cross-platform EPUB and web editor/IDE from package
APP_NAME=BlueGriffon
APP_GUI_NAME="Cross-platform EPUB and web editor/IDE."
APP_VERSION=3.0.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}.Ubuntu16.04-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://${APP_NAME,,}.org/freshmeat/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install LaTeX2RTF cross-platform utility to convert LaTeX files to RTF from package
APP_NAME=LaTeX2RTF
APP_GUI_NAME="Cross-platform utility to convert LaTeX files to RTF."
APP_VERSION=2.3.17
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT} && cd /tmp/${FILE_NAME}
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Mnemosyne cross-platform Python/Qt-based flashcard program from source
APP_NAME=Mnemosyne
APP_GUI_NAME="Cross-platform Python/Qt-based flashcard program."
APP_VERSION=2.6.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y python3-pip python3-pyqt5 python3-matplotlib python3-virtualenv python3-setuptools python3-wheel python3-webob python3-willow python3-pyqt5.qtwebengine python3-pyqt5.qtwebkit python3-pyqt5.qtsql python3-opengl
sudo pip3 install cheroot
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-proj/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT} && cd /tmp/${FILE_NAME}
sudo python3 ./setup.py install
sudo cp ./pixmaps/${APP_NAME,,}.ico /usr/local/share/pixmaps
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Education;
Keywords=Education;Flashcard;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install 8Bit Banditos HTML5/JavaScript retro arcade game from source
APP_NAME=8BitBanditos
APP_GUI_NAME="8bit Banditos HTML5/JavaScript retro arcade game."
APP_VERSION=1.4
APP_EXT=7z
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/banditos/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/banditos
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}/* ${WWW_HOME}/banditos
sudo chmod -R 777 ${WWW_HOME}/banditos
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=${WWW_HOME}/banditos
Exec=xdg-open ${WWW_HOME}/banditos/index.html
Icon=${WWW_HOME}/banditos/images/invader_bonus_48_24_1_1.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Arcade;Retro;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open ${WWW_HOME}/banditos/index.html
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install PHP Server Monitor web site and service monitoring platform
APP_NAME=PHPServerMon
APP_GUI_NAME="Web site and service monitoring platform."
APP_VERSION=3.3.0
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
cd ${WWW_HOME}/${APP_NAME,,}
sudo php ./composer.phar install
sudo php ./composer.phar update
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
# Create configuration file and copy to installation directory.
cat > /tmp/config.php << EOF
<?php
define('PSM_DB_HOST', 'localhost');
define('PSM_DB_PORT', '3306');
define('PSM_DB_NAME', '${DB_NAME}');
define('PSM_DB_USER', '${DB_USER}');
define('PSM_DB_PASS', '${DB_PASSWORD}');
define('PSM_DB_PREFIX', 'psm_');
define('PSM_BASE_URL', 'http://localhost/${APP_NAME,,}');
EOF
sudo mv /tmp/config.php ${WWW_HOME}/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=${WWW_HOME}/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php
Icon=${WWW_HOME}/${APP_NAME,,}/favicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Monitoring;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}/index.php &
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install VeraCrypt cross-platform disk encryption utility from package
APP_NAME=VeraCrypt
APP_GUI_NAME="Cross-platform disk encryption utility."
APP_VERSION=1.22
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-setup
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo sh /tmp/${FILE_NAME}/${FILE_NAME}-console-${ARCH_TYPE}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Pinky Bar window manager-independent status bar system information utility from source
APP_NAME=Pinky-Bar
APP_GUI_NAME="Window manager-independent status bar system information utility."
APP_VERSION=N/A
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}
sudo apt-get install -y pciutils libpci-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
perl set.pl "debian" && autoreconf --install --force
./configure --prefix=$HOME/.cache --without-x11 --without-colours && make && 
make install && mkdir -p $HOME/.pinky
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SwitchHosts cross-platform, Electron-based hosts file manager from package
APP_NAME=SwitchHosts
APP_GUI_NAME="Cross-platform, Electron-based hosts file manager."
APP_MAJOR_VERSION=3.3.12
APP_MINOR_VERSION=5349
APP_EXT=zip
FILE_NAME=${APP_NAME}-linux-x64_v${APP_MAJOR_VERSION}.${APP_MINOR_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/oldj/${APP_NAME}/releases/download/v${APP_MAJOR_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}\!-linux-x64/* /opt/${APP_NAME,,}
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME}\! /opt/${APP_NAME,,}/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
#Icon=/opt/${APP_NAME,,}/icons/yicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Network;Internet;
Keywords=Hosts;Networking;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Tweet Tray cross-platform, Electron-based Twitter client from package
APP_NAME=Tweet-Tray
APP_GUI_NAME="Cross-platform, Electron-based Twitter client."
APP_VERSION=1.1.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/jonathontoon/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install fd user-friendly alternative to Linux 'find' from package
APP_NAME=fd
APP_GUI_NAME="Cross-platform, user-friendly alternative to Linux 'find'."
APP_VERSION=7.3.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-musl_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/sharkdp/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install fileobj Python-based ncurses hex editor with Vi keybindings from source
APP_NAME=fileobj
APP_GUI_NAME="Python-based ncurses hex editor."
APP_VERSION=0.7.74
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/kusumi/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo python3 ./setup.py install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Flowblade multitrack non-linear video editor for Linux from package
APP_NAME=Flowblade
APP_GUI_NAME="Multitrack non-linear video editor for Linux."
APP_VERSION=1.16
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}.0-1_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/jliljebl/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install wxglterm Python and C/C++ Wx-based terminal emulator from source
APP_NAME=wxglterm
APP_GUI_NAME="Python and C/C++ Wx-based terminal emulator."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=N/A
sudo apt-get install -y libwxbase3.0-dev pybind11-dev libfontconfig1-dev libglew-dev libglfw*-dev cmake libwxgtk3.0-dev
cd /tmp
git clone https://github.com/stonewell/${APP_NAME,,}
cd /tmp/${APP_NAME,,}
mkdir -p build && cd build
cmake .. -DPYTHON_INCLUDE_DIR=$(python3 -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") -DBUILD_WXWIDGETS_UI=ON -DBUILD_OPENGL_UI=ON
make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Gocho LAN file-sharing application with node auto-discovery from package
APP_NAME=Gocho
APP_GUI_NAME="LAN file-sharing application with node auto-discovery."
APP_VERSION=0.1.0
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=386
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_linux${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/donkeysharp/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install LumberJack4Logs Java-based log file viewer with support for customer parser plugins from package
APP_NAME=LumberJack4Logs
APP_GUI_NAME="Java-based log file viewer with support for customer parser plugins."
APP_VERSION=20180404_2317
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:\$PATH; export PATH
sh /opt/${APP_NAME}/start_${APP_NAME,,}.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}
Exec=sh /opt/${APP_NAME}/start_${APP_NAME,,}.sh
Icon=/opt/${APP_NAME}/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;System;
Keywords=Logs;System;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install MultiBootUSB utility for creating bootable USB/Flash drive with multiple live Linux distributions from package
APP_NAME=MultiBootUSB
APP_GUI_NAME="Utility for creating bootable USB/Flash drive with multiple live Linux distributions."
APP_VERSION=9.2.0-1
APP_EXT=deb
FILE_NAME=python3-${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Miam-Player cross-platform Qt-based audio player from source
APP_NAME=Miam-Player
APP_GUI_NAME="Cross-platform Qt-based audio player."
APP_VERSION=0.8.0
APP_EXT=tar.gz
sudo apt-get install -y build-essential qt5-qmake qttools5-dev qttools5-dev-tools libqtav-dev libtag1-dev libqt5multimedia5 qtmultimedia5-dev libqt5x11extras5-dev
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/MBach/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
cd /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 ${APP_NAME,,}.pro && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install EtherApe GTK-based GUI network monitoring tool from source
APP_NAME=EtherApe
APP_GUI_NAME="GTK-based GUI network monitoring tool."
APP_VERSION=0.9.18
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y build-essential libglade2-dev libgnomecanvas2-dev libpcap-dev itstool libpopt-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Hale Studio cross-platform, Java-based interactive tool for data transformation and visualization from package
APP_NAME=Hale-Studio
APP_GUI_NAME="Cross-platform, Java-based interactive tool for data transformation and visualization."
APP_VERSION=3.3.2
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-linux.gtk.${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME//-/}/hale/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
mv ${FILE_NAME} ${APP_NAME,,}
sudo mv ${APP_NAME,,} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/HALE
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}
Exec=/opt/${APP_NAME,,}/HALE
Icon=/opt/${APP_NAME,,}/icon.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;System;
Keywords=Eclipse;Data;Science;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install rpCalc cross-platform, Python/Qt RPN calculator from source
APP_NAME=rpCalc
APP_GUI_NAME="Cross-platform, Python/Qt RPN calculator."
APP_VERSION=0.8.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y python3-pyqt5
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME}
sudo python3 ./install.py
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Opera web browser from package
APP_NAME=Opera
APP_GUI_NAME=""
APP_VERSION=52.0.2871.40
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-stable_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download3.operacdn.com/pub/${APP_NAME,,}/desktop/${APP_VERSION}/linux/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install smenu interactive shell script menu tool from source
APP_NAME=smenu
APP_GUI_NAME="Interactive shell script menu tool."
APP_VERSION=0.9.12
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libtinfo-dev lib64tinfo5 libncurses5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/p-gen/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./build.sh && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install DeaDBeeF minimalist audio player from package
APP_NAME=DeaDBeeF
APP_GUI_NAME="Minimalist audio player."
APP_VERSION=0.7.2-2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-static_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install ghostwriter Qt-based, cross-platform Markdown editor with built-in preview from source
APP_NAME=ghostwriter
APP_GUI_NAME="Qt-based, cross-platform Markdown editor."
APP_VERSION=1.7.4
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y qt5-default hunspell libhunspell-dev libqt5webkit5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/wereturtle/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
qtchooser -run-tool=qmake -qt=5 ghostwriter.pro && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Extraterm Electron-based, cross-platform terminal emulator from package
APP_NAME=Extraterm
APP_GUI_NAME="Electron-based, cross-platform terminal emulator."
APP_VERSION=0.41.1
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/sedwards2009/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Path=/opt/${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/resources/app/${APP_NAME,,}/resources/logo/${APP_NAME,,}_small_logo.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=System;TerminalEmulator;
Keywords=Terminal;Shell;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Ironclad Go-based, minimalist command line password manager from package
APP_NAME=Ironclad
APP_GUI_NAME="Go-based, minimalist command line password manager."
APP_VERSION=1.0.0
APP_EXT=zip
FILE_NAME=linux
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/dmulholland/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mv /tmp/${APP_NAME,,}/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Luna Electron-based GUI for Node.JS/NPM package management from package
APP_NAME=Luna
APP_GUI_NAME="Electron-based GUI for Node.JS/NPM package management."
APP_VERSION=3.0.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/rvpanoz/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install giv (Gtk+ Image Viewer) Gtk-based image and vector viewer from source
APP_NAME=giv
APP_GUI_NAME="Gtk-based image and vector viewer."
APP_VERSION=0.9.30
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtk-3-dev
# Install CFITSIO FITS File Subroutine Library <https://heasarc.gsfc.nasa.gov/fitsio/fitsio.html>
TEMP_FILE=cfitsio3440
curl -o /tmp/${TEMP_FILE}.${APP_EXT} -J -L http://heasarc.gsfc.nasa.gov/FTP/software/fitsio/c/${TEMP_FILE}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${TEMP_FILE}.${APP_EXT}
cd /tmp/${TEMP_FILE}/cfitsio
./configure && make
UPDATE_STRING=s@/tmp/${TEMP_FILE}/cfitsio@/usr@g
sudo sed -i ${UPDATE_STRING} ./lib/pkgconfig/cfitsio.pc
sudo cp -R ./lib/* /usr/lib
sudo cp fitsio.h fitsio2.h longnam.h drvrsmem.h /usr/include
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOMlE
rm -rf /tmp/${APP_NAME,,}

# Install Umbrella Note Electron-based minimalist notepad/journal utility from package
# https://github.com/arpban/umbrella-note
APP_NAME=Umbrella-Note
APP_GUI_NAME="Electron-based minimalist notepad/journal utility."
APP_VERSION=2.0.0
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://umbrellanote.com/updates/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install LiVES non-linear video editor from source
APP_NAME=LiVES
APP_GUI_NAME="Non-linear video editor."
APP_VERSION=2.8.9
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y imagemagick mplayer libjpeg62-dev sox libmjpegtools-dev lame ffmpeg libgtk-3-dev libgdk-pixbuf2.0-dev libjack-dev libpulse-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install && sudo ldconfig
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install GetIt GTK+-3-based HTTP request tool from source
APP_NAME=GetIt
APP_GUI_NAME="GTK+-3-based HTTP request tool."
APP_VERSION=4.0.9
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtk-3-dev libgtksourceview-3.0-dev libsoup2.4-dev libnotify-dev libglib2.0-dev json-glib-tools libjson-glib-dev gettext libwebkitgtk-dev meson
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/bartkessels/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
meson --prefix=/usr/local build && cd build && sudo ninja install
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Etcher cross-platform Electron-based tool to copy OS images to USB drives from package
APP_NAME=Etcher
APP_GUI_NAME="Cross-platform Electron-based tool to copy OS images to USB drives."
APP_VERSION=1.4.1
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
FILE_NAME=${APP_NAME,,}-electron-${APP_VERSION}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/resin-io/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}-electron-${APP_VERSION}*.AppImage /usr/local/bin
/usr/local/bin/${FILE_NAME}/${APP_NAME,,}-electron-${APP_VERSION}*.AppImage &
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install 2D Java Chess Java chess game from package
APP_NAME=Java-Chess-2D
APP_GUI_NAME="Java chess game."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/2D%20Java%20Chess.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Games;Chess;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install QCalc Java-based command-line high-precision calculator from package
APP_NAME=QCalc
APP_GUI_NAME="Java-based command-line high-precision calculator."
APP_VERSION=1.1-beta
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-uni
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/paroxayte/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo cp /tmp/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}.${APP_EXT}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /usr/local/bin
PATH=/usr/local/bin:\$PATH; export PATH
java -jar /usr/local/bin/${APP_NAME,,}.${APP_EXT} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install tkdiff Tcl-based text file difference viewer/editor from source
APP_NAME=tkdiff
APP_GUI_NAME="Tcl-based text file difference viewer/editor."
APP_VERSION=4.3.5
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION/./-}
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}

# Install FreeBASIC cross-platform BASIC compiler, with syntax similar MS-QuickBASIC and advanced features from package
APP_NAME=FreeBASIC
APP_GUI_NAME="Cross-platform BASIC compiler, with syntax similar MS-QuickBASIC and advanced features."
APP_VERSION=1.06.0
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME}-${APP_VERSION}-linux-${ARCH_TYPE}
sudo apt-get install -y gcc libncurses5-dev libffi-dev libgl1-mesa-dev libx11-dev libxext-dev libxrender-dev libxrandr-dev libxpm-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/fbc/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo ./install.sh -i /usr/local
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install LNAV log file viewer/searcher with syntax highlighting from package
APP_NAME=LNAV
APP_GUI_NAME="Log file viewer/searcher with syntax highlighting."
APP_VERSION=0.8.3a
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}-linux-64bit
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/tstack/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install DCEdit cross-platform, Java-based editor with built-in snippets for Java, SQL, and JavaFX from package
APP_NAME=DCEdit
APP_GUI_NAME="Cross-platform, Java-based editor with built-in snippets for Java, SQL, and JavaFX."
APP_VERSION=2.4
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
sh /opt/${APP_NAME,,}/${APP_NAME}.sh "\$1"
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
Exec=sh /opt/${APP_NAME,,}/${APP_NAME}.sh
Icon=/opt/${APP_NAME,,}/bin/img/splash.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming
Keywords=Editor;Text;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install PDF Sandwich utility to OCR images and embed text in original PDF file from package
APP_NAME=PDFSandwich
APP_GUI_NAME="Utility to OCR images and embed text in original PDF file."
APP_VERSION=0.1.6
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install CoolReader cross-platform eBook reader supporting FB2, TXT, RTF, DOC, TCR, HTML, EPUB, CHM, PDB, and MOBI formats from package
APP_NAME=CoolReader
APP_GUI_NAME="Cross-platform eBook reader supporting FB2, TXT, RTF, DOC, TCR, HTML, EPUB, CHM, PDB, and MOBI formats."
APP_VERSION=3.0.56-7
APP_EXT=deb
FILE_NAME=cr3_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/libpng12-0.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libpng12-0.deb
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/crengine/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install IndJShell independent, cross-platform Java shell/REPL from package
APP_NAME=IndJShell
APP_GUI_NAME="Independent, cross-platform Java shell/REPL."
APP_VERSION=0.0.2
APP_EXT=jar
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Webmin web-based Unix/Linux administration tool from package
APP_NAME=Webmin
APP_GUI_NAME="Web-based Unix/Linux administration tool."
APP_VERSION=1.881
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/webadmin/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install XiX Music Player cross-platform audio player from package
APP_NAME="XiX Music Player"
APP_GUI_NAME="Cross-platformaudio player."
APP_VERSION=N/A
APP_EXT=zip
# FILE_NAME="$(echo -e "${APP_NAME}" | tr -d '[:space:]')"_x64
FILE_NAME=${APP_NAME// /}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/xixmusicplayer/${FILE_NAME}_x64.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME// /} /opt
cat > /tmp/${FILE_NAME,,} << EOF
#! /bin/sh
cd /opt/${FILE_NAME}
PATH=/opt/${FILE_NAME}:\$PATH; export PATH
LD_LIBRARY_PATH=/opt/${FILE_NAME}/lib:\$LD_LIBRARY_PATH; export LD_LIBRARY_PATH
/opt/${FILE_NAME}/${FILE_NAME} "\$1"
cd $HOME
EOF
sudo mv /tmp/${FILE_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${FILE_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${FILE_NAME}
Exec=/usr/local/bin/${FILE_NAME,,}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Audio;Multimedia
Keywords=Audio;Music
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Nethack text-based RPG from source
# Build instructions based on http://jes.st/2015/compiling-playing-nethack-360-on-ubuntu/
APP_NAME=Nethack
APP_GUI_NAME="Text-based RPG."
APP_VERSION=3.6.1
APP_EXT=tgz
FILE_NAME=${APP_NAME,,}-${APP_VERSION//./}-src
sudo apt-get install -y flex bison build-essential libncurses5-dev checkinstall
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}
sed -i 's@/* #define LINUX */@#define LINUX@g' ./include/unixconf.h
# Enable Status Hilites
sed -i 's@/* #define STATUS_VIA_WINDOWPORT */@#define STATUS_VIA_WINDOWPORT@g' ./include/config.h
sed -i 's@/* #define STATUS_HILITES */@#define STATUS_HILITES@g' ./include/config.h
curl -o ./sys/unix/hints/linux -J -L https://gist.githubusercontent.com/jesstelford/67eceb7a7fa08405f6b7/raw/4579ba467ad6120a48e2e4b572c83b48dcdbc636/Makefile
# Generate Makefile
sh ./sys/unix/setup.sh ./sys/unix/hints/linux
make all && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Digital Logic Design (DLD) Java-based digital circuit designer and simulator from package
APP_NAME="Digital Logic Design"
APP_GUI_NAME="Java-based digital circuit designer and simulator."
APP_VERSION=N/A
APP_EXT=zip
FILE_NAME=DLD
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/digitalcircuitdesign/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${FILE_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${FILE_NAME,,}
cat > /tmp/${FILE_NAME,,}/${FILE_NAME,,} << EOF
#! /bin/sh
cd /opt/${FILE_NAME,,}
PATH=/opt/${FILE_NAME,,}:\$PATH; export PATH
java -jar /opt/${FILE_NAME,,}/${FILE_NAME}.jar "\$1"
cd $HOME
EOF
sudo mv /tmp/${FILE_NAME,,}/${FILE_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${FILE_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${FILE_NAME,,}
Exec=java -jar /opt/${FILE_NAME,,}/${FILE_NAME}.jar "\$1"
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Electronics;Education;Engineering;
Keywords=Electronics;Simulation;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Everest cross-platform JavaFX-based REST API client from package
APP_NAME=Everest
APP_GUI_NAME="Cross-platform JavaFX-based REST API client."
APP_VERSION=Alpha-1.0
APP_EXT=jar
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/RohitAwate/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Test;Web Services;API;REST;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Turing cross-platform, Qt-based Python IDE from package
APP_NAME=Turing
APP_GUI_NAME="Cross-platform, Qt-based Python IDE."
APP_VERSION=0.8
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}-nix
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/TuringApp/${APP_NAME}/releases/download/v${APP_VERSION}-beta/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,} "\$1"
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Python;Editor;IDE;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install KADOS (KAnban Dashboard for Online Scrum) web-based tool for managing Scrum projects with Kanban board
# http://www.kados.info/
APP_NAME=KADOS
APP_VERSION=r10-GreenBee
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${APP_NAME,,}_${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME,,} ${WWW_HOME}
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
sudo cp ${WWW_HOME}/${APP_NAME,,}/updates/R10-GreenBee/install/connect_r10.conf ${WWW_HOME}/${APP_NAME,,}/conf/connect.conf
sudo sed -i 's@PARAM_host@localhost@g' ${WWW_HOME}/${APP_NAME,,}/conf/connect.conf
sudo sed -i 's@PARAM_db@'${DB_NAME}'@g' ${WWW_HOME}/${APP_NAME,,}/conf/connect.conf
sudo sed -i 's@PARAM_user@'${DB_USER}'@g' ${WWW_HOME}/${APP_NAME,,}/conf/connect.conf
sudo sed -i 's@PARAM_password@'${DB_PASSWORD}'@g' ${WWW_HOME}/${APP_NAME,,}/conf/connect.conf
sudo sed -i 's@PARAM_charset@utf8_general_ci@g' ${WWW_HOME}/${APP_NAME,,}/conf/connect.conf
mysql --host=localhost --user=${DB_USER} --password=${DB_PASSWORD} ${DB_NAME} < /tmp/${APP_NAME,,}/sql/create_database_R10.sql
xdg-open http://localhost/${APP_NAME,,}/index.php &

# Install linNet symbolic Analysis of linear Electronic Circuits tool from package
APP_NAME=linNet
APP_GUI_NAME="Cross-platform, symbolic Analysis of linear Electronic Circuits tool."
APP_VERSION=1.0.1
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-svn/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/components/${APP_NAME}/* /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/bin/LINUX/PRODUCTION/${APP_NAME}
sudo rm -rf /opt/${APP_NAME,,}/bin/win*
echo 'LINNET_HOME=/opt/'${APP_NAME,,}'/bin/LINUX/PRODUCTION; export LINNET_HOME' >> $HOME/.bashrc
echo 'PATH=$PATH:$LINNET_HOME; export PATH' >> $HOME/.bashrc
source $HOME/.bashrc	# Reload Bash configuration
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/bin/LINUX/PRODUCTION
PATH=/opt/${APP_NAME,,}/bin/LINUX/PRODUCTION:\$PATH; export PATH
/opt/${APP_NAME,,}/bin/LINUX/PRODUCTION/${APP_NAME} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/bin/LINUX/PRODUCTION
Exec=/opt/${APP_NAME,,}/bin/LINUX/PRODUCTION/${APP_NAME} "\$1"
Icon=/opt/${APP_NAME,,}/doc/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Science;Electronics;
Keywords=Electronics;Circuits;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Eval minimalist console calculator from package
APP_NAME=concalc
APP_GUI_NAME="Cross-platform, minimalist console calculator."
APP_VERSION=N/A
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/eval-command-line-calculator/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/consolecalc/${APP_NAME} /usr/local/bin
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install FileRunner cross-platform, two-pane file manager with built-in FTP/SFTP client from package
APP_NAME=FileRunner
APP_GUI_NAME="Cross-platform, two-pane file manager with built-in FTP/SFTP client."
APP_VERSION=18.07.19.16-2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Web Video Downloader Zenity GUI for cclive video download utility from package
APP_NAME=WebVideoDownloader
APP_GUI_NAME="Zenity GUI for cclive video download utility."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=${APP_NAME}
sudo apt-get install -y zenity cclive
curl -o /tmp/${FILE_NAME} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}
sudo mv /tmp/${FILE_NAME} /usr/local/bin
sudo chmod +x /usr/local/bin/WebVideoDownloader
sudo ln -s /usr/local/bin/${FILE_NAME} /usr/local/bin/wvdl
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Origami SMTP cross-platform, Java-based, fake SMTP server with TLS support from package
APP_NAME=Origami-SMTP
APP_GUI_NAME="Cross-platform, Java-based, fake SMTP server with TLS support."
APP_VERSION=v1.6.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/origamismtp/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Diffuse cross-platform, local and cloud account (AWS S3, Dropbox, Google Drive, etc.) audio player from Snap package
APP_NAME=Diffuse
APP_GUI_NAME="Cross-platform, local and cloud account (AWS S3, Dropbox, Google Drive, etc.) audio player."
APP_VERSION=1.0.0-beta
APP_EXT=snap
FILE_NAME=${APP_NAME}_${APP_VERSION//.4/}_${KERNEL_TYPE}
sudo apt-get install -y snapd snapd-xdg-open
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/icidasset/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo snap install --dangerous /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}

# Install justmd cross-platform, Electron-based MarkDown editor with built-in preview from package
APP_NAME=justmd
APP_GUI_NAME="Cross-platform, Electron-based MarkDown editor with built-in preview "
APP_VERSION=v1.1.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-linux-x64-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/i38/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}-linux-x64/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME} "\$1"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=MarkDown;Editor;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Whale cross-platform advanced web browser from Debian package
APP_NAME=Whale
APP_GUI_NAME="Cross-platform advanced web browser."
APP_VERSION=stable
APP_EXT=deb
FILE_NAME=naver-${APP_NAME,,}-${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://update.whale.naver.net/downloads/installers/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME},,*

# Install Anteater Java-based manual test planning/tracking tool from package
APP_NAME=Anteater
APP_GUI_NAME="Cross-platform, Java-based manual test planning/tracking tool "
APP_VERSION=N/A
APP_EXT=zip
FILE_NAME=ae-pack
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar "\$1"
Icon=/opt/${APP_NAME,,}/mtu-automaton.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Testing;Development;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Nighthawk cross-platform, Electron-based minimalist music player from Debian package
APP_NAME=Nighthawk
APP_GUI_NAME="Cross-platform, Electron-based minimalist music player."
APP_VERSION=v2.0.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-linux-${APP_VERSION}-${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/quantumkv/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install MiluDBViewer cross-platform, Java-based multi-database (MySQL/PostgreSQL/Oracle/Cassandra/SQLite/SQLServer/MongoDB) viewer/editor client from package
# Requires JRE 9 or later with JavaFX
APP_NAME=MiluDBViewer
APP_GUI_NAME="Cross-platform, Java-based multi-database (MySQL/PostgreSQL/Oracle/Cassandra/SQLite/SQLServer/MongoDB) viewer/editor client."
APP_VERSION=0.3.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}.jre9.sh "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME}.jre9.sh "\$1"
Icon=/opt/${APP_NAME,,}/resources/images/winicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;Java;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install SET's Editor simple Turbo C++-style console-mode text editor from Debian package
APP_NAME=SETedit
APP_GUI_NAME="Simple  Turbo C++-style console-mode text editor."
APP_VERSION=0.5.8-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
curl -o /tmp/rhtvision2.2.1_2.2.1-4_amd64.${APP_EXT} -J -L https://downloads.sourceforge.net/tvision/rhtvision2.2.1_2.2.1-4_amd64.${APP_EXT}
sudo gdebi -n /tmp/rhtvision2.2.1_2.2.1-4_amd64.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME},,*

# Install dotProject web-based tool for project management including Gantt charts
# https://dotproject.net/
APP_NAME=dotProject
APP_VERSION=2.1.9
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/install/index.php &

# Install Textosaurus minimalist, cross-platform Qt5/Scintilla-based text editor from AppImage
APP_NAME=Textosaurus
APP_GUI_NAME="Minimalist, cross-platform Qt5/Scintilla-based text editor."
APP_MAJOR_VERSION=0.9.7
APP_MINOR_VERSION=f0908a3
APP_EXT=AppImage
FILE_NAME=${APP_NAME,,}-${APP_MAJOR_VERSION}-${APP_MINOR_VERSION}-linux64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/martinrotter/${APP_NAME,,}/releases/download/${APP_MAJOR_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;Accessories
Keywords=Editor;Text;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install sqlitebiter cross-platform CLI tool to convert CSV/Excel/HTML/JSON/LTSV/Markdown/SQLite/SSV/TSV/Google-Sheets to a SQLite database file from Debian package
APP_NAME=sqlitebiter
APP_GUI_NAME="Cross-platform, CLI tool to convert CSV/Excel/HTML/JSON/LTSV/Markdown/SQLite/SSV/TSV/Google-Sheets to a SQLite database file ."
APP_VERSION=0.22.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/thombashi/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install aria2 cross-platform, lightweight multi-protocol & multi-source, cross platform download utility which supports HTTP/HTTPS, FTP, SFTP, BitTorrent and Metalink from source
APP_NAME=aria2
APP_GUI_NAME="Cross-platform, lightweight multi-protocol & multi-source, cross platform download utility which supports HTTP/HTTPS, FTP, SFTP, BitTorrent and Metalink."
APP_VERSION=1.34.0
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install libssh-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/aria2/aria2/releases/download/release-${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install X11-Basic cross-platform Basic interpreter with graphics support from Debian package
APP_NAME=x11basic
APP_GUI_NAME="Cross-platform Basic interpreter with graphics support."
APP_VERSION=1.27-57
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/x11-basic/${FILE_NAME}.${APP_EXT}
curl -o /tmp/libreadline6.${APP_EXT} -J -L http://launchpadlibrarian.net/236282832/libreadline6-dev_6.3-8ubuntu2_${KERNEL_TYPE}.${APP_EXT}
curl -o /tmp/libreadline6.${APP_EXT} -J -L http://launchpadlibrarian.net/236282834/libreadline6_6sudo ln -s /opt/${APP_NAME,,}/bin/${APP_NAME,,}.sh /usr/local/bin/${APP_NAME,,}.3-8ubuntu2_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/libreadline6.${APP_EXT}
sudo gdebi -n /tmp/libreadline6.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install FriCAS computer algebra system from package
APP_NAME=FriCAS
APP_GUI_NAME="Computer algebra system."
APP_VERSION=1.3.3
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}.${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo tar -C / -xvjf /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install LinSSID Qt-based GUI wireless network scanner from Debian package
APP_NAME=LinSSID
APP_GUI_NAME="Qt-based GUI wireless network scanner."
APP_VERSION=3.6-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Devdom shell script to automate generating Apache virtual hosts from Debian package
APP_NAME=Devdom
APP_GUI_NAME="Shell script to automate generating Apache virtual hosts."
APP_VERSION=N/A
APP_EXT=deb
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/angela-d/${APP_NAME,,}/raw/master/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install PDF Chain graphical user interface for the PDF Toolkit (PDFtk) from source
APP_NAME=PDFChain
APP_GUI_NAME="Graphical user interface for the PDF Toolkit (PDFtk)."
APP_VERSION=0.4.4.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtkmm-3.0-dev
# Install PDFtk
# PDFtk removed from repositories for Ubuntu 18.04 (Bionic Beaver), so we must install from Ubunutu 17.10 (Artful Aardvark) files in that case.  See these articles for details:
# https://ubuntuforums.org/showthread.php?t=2390293
# https://askubuntu.com/questions/1028522/how-can-i-install-pdftk-in-ubuntu-18-04-bionic
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(bi)$ ]]; then
	sudo apt-get install -y gcc-6-base
	cd /tmp
	curl -o /tmp/libgcj-common.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/g/gcc-defaults/libgcj-common_6.4-3ubuntu1_all.deb
	sudo gdebi -n /tmp/libgcj-common.deb
	curl -o /tmp/libgcj17.deb -J -L http://mirrors.kernel.org/ubuntu/pool/main/g/gcc-6/libgcj17_6.4.0-8ubuntu1_amd64.deb
	sudo gdebi -n /tmp/libgcj17.deb
	curl -o /tmp/pdftk.deb -J -L http://mirrors.kernel.org/ubuntu/pool/universe/p/pdftk/pdftk_2.02-4build1_amd64.deb
	sudo gdebi -n /tmp/pdftk.deb
else
	sudo apt-get install -y pdftk
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd ${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install MindForger notepad and Markdown editor/IDE with built-in preview from Debian package
APP_NAME=MindForger
APP_GUI_NAME="Notepad and Markdown editor/IDE with built-in preview."
APP_VERSION=1.49.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install MindRaider cross-platform, Java-based notepad, PIM, and outliner from package
APP_NAME=MindRaider
APP_GUI_NAME="Cross-platform, Java-based notepad, PIM, and outliner."
APP_VERSION=15.0
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-allplatforms-release
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}/* /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/bin/${APP_NAME,,}.sh
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/bin
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/bin:\$PATH; export PATH
/opt/${APP_NAME,,}/bin/${APP_NAME,,}.sh "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/bin
Exec=/usr/local/bin/${APP_NAME,,} "\$1"
Icon=/opt/${APP_NAME,,}/programIcon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories
Keywords=Editor;PIM;Outliner;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install BackDrop Java-based image editor for multi-monitor wallpaper creation from package
APP_NAME=BackDrop
APP_GUI_NAME="Cross-platform, Java-based image editor for multi-monitor wallpaper creation."
APP_VERSION=v1-0
APP_EXT=jar
FILE_NAME=${APP_NAME}-Linux-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}.${APP_EXT} "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.${APP_EXT} "\$1"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;Accessories;
Keywords=Editor;Wallpaper;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Battle for Wesnoth high-fantasy themed adventure game from source
APP_NAME=Wesnoth
APP_GUI_NAME="High-fantasy themed adventure game."
APP_VERSION=1.14.7
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y cmake libboost-all-dev libsdl2-dev libsdl2-ttf-dev libsdl2-mixer-dev libsdl2-image-dev libfontconfig1-dev libcairo2-dev libpango1.0-dev libpangocairo-1.0-0 libvorbis-dev libvorbisfile3 libbz2-dev libssl-dev libreadline-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local/bin -DENABLE_NLS=0 && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install WAV Audio Compressor from source
APP_NAME=Compressor
APP_GUI_NAME="Command-line WAV audio compressor."
APP_VERSION=0.30
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
gcc compress.c -o compress && sudo mv compress /usr/local/bin
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Piskvorky cross-platform, Qt-based Gomoku game from package
APP_NAME=Piskvorky
APP_GUI_NAME="Cross-platform, Qt-based Gomoku game."
APP_VERSION=N/A
APP_EXT=zip
FILE_NAME=${APP_NAME}Linux
sudo apt-get install -y qt5-default
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}2/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/*${APP_NAME,,}*/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}2
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
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}2
Icon=/opt/${APP_NAME,,}/data/img/xo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Gomoku;Puzzle;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install bashj utility to allow use of native Java code in Bash shell scripts from package
# http://fil.gonze.org/wikiPG/index.php/Project_bashj_:_a_bash_mutant_with_java_support
APP_NAME=bashj
APP_GUI_NAME="Utility to allow use of native Java code in Bash shell scripts."
APP_VERSION=0.999
APP_EXT=jar
FILE_NAME=${APP_NAME,,}Install-${APP_VERSION}
sudo apt-get install -y openjdk-9-jdk  # Java 9 or later required!
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -m=777 /var/lib/bashj/
mv /tmp/${FILE_NAME}.${APP_EXT} /var/lib/bashj/
cd /var/lib/bashj/
jar xvf ./${FILE_NAME}.${APP_EXT}
chmod +x ./bashjInstall
sudo ./bashjInstall
# Add configuration settings to .bashrc
echo '# Initialize bashj extensions' >> $HOME/.bashrc
echo '. jsbInit && jsbStart' >> $HOME/.bashrc
source $HOME/.bashrc	# Reload Bash configuration
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Query Light Java/JDBC-based Oracle database client from package
# https://github.com/milind-brahme/query-light
APP_NAME=QueryLight
APP_GUI_NAME="Java/JDBC-based Oracle database client."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=runsql_anony
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/query-light-light-orcl-client/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} "\$1"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;Accessories;
Keywords=Database;Oracle;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Zippy IP Scanner cross-platform Python/Qt-based GUI IP scanner from package
# https://github.com/swprojects/Zippy-Ip-Scanner
APP_NAME=Zippy-IP-Scanner
APP_GUI_NAME="Cross-platform Python/Qt-based GUI IP scanner."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=N/A
sudo pip3 install ${APP_NAME,,}

# Install RecordEditor Java-based, GUI CSV/XML file editor from package
# https://github.com/milind-brahme/query-light
APP_NAME=RecordEditor
APP_GUI_NAME="Java-based, GUI CSV/XML file editor."
APP_VERSION=0.98.5
APP_EXT=zip
FILE_NAME=${APP_NAME}_USB_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/record-editor/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}_USB/* /opt/${APP_NAME}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:\$PATH; export PATH
sh /opt/${APP_NAME}/${APP_NAME}.sh "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}
Exec=/usr/local/bin/${APP_NAME,,} "\$1"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;Accessories;
Keywords=Database;Java;CSV;XML
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install tmount minimalist block device/removable media mounting utility from source
APP_NAME=tmount
APP_GUI_NAME="Minimalist block device/removable media mounting utility."
APP_VERSION=0.0.7
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y qtbase5-dev qt5-qmake qt5-default qttools5-dev-tools udevil libudev-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/abwaldner/${APP_NAME}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
qtchooser -run-tool=qmake -qt=5 ${APP_NAME}.pro && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Y PPA Manager GUI management utility of PPA repositories from PPA
APP_NAME=Y-PPA-Manager
sudo add-apt-repository -y ppa:webupd8team/${APP_NAME,,}
sudo apt-get update
sudo apt-get install -y ${APP_NAME,,}

# Install OpenTodoList cross-platform, Qt-based "To Do" list and task management from AppImage
APP_NAME=OpenTodoList
APP_GUI_NAME="Cross-platform, Qt-based \"To Do\" list and task management."
APP_VERSION=3.8.0
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/mhoeher/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=ToDo;Productivity;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install WordPress Desktop application from package
APP_NAME=WordPress-Desktop
APP_GUI_NAME="Desktop editor for blogging on WordPress.com."
APP_VERSION=3.3.0
APP_EXT=deb
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://public-api.wordpress.com/rest/v1.1/desktop/linux/download?type=${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ElCalc minimalist cross-platform desktop calculator built with Electron from package
APP_NAME=ElCalc
APP_GUI_NAME="Minimalist cross-platform desktop calculator built with Electron."
APP_VERSION=5.0.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Enpass cross-platform desktop password manager from PPA
APP_NAME=Enpass
curl -sL https://dl.sinew.in/keys/enpass-linux.key | sudo apt-key add -
echo "deb http://repo.sinew.in/ stable main" | sudo tee /etc/apt/sources.list.d/enpass.list
sudo apt-get update && sudo apt-get install -y enpass

# Install Waterfox web browser from package
APP_NAME=Waterfox
APP_GUI_NAME="Cross-platform web browser."
APP_VERSION=56.2.1
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}.en-US.linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://storage-waterfox.netdna-ssl.com/releases/linux64/installer/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/* /opt
sudo ln -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/browser/icons/mozicon128.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Network;Networking;
Keywords=Firefox;Browser;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Pixelitor cross-platform, Java-based image editor from package
APP_NAME=Pixelitor
APP_GUI_NAME="Cross-platform, Java-based image editor."
APP_VERSION=4.2.0
APP_EXT=jar
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.${APP_EXT} "\$1"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;Accessories;
Keywords=Graphics;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Vidiot cross-platform non-linear video editor from package
APP_NAME=Vidiot
APP_GUI_NAME="Cross-platform non-linear video editor."
APP_VERSION=0.3.24
APP_EXT=deb
FILE_NAME=${APP_NAME}-${APP_VERSION}-win64
source /etc/lsb-release
# If Ubuntu version is above 17.10 (Artful), then we install 17.04 version of libva1.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(bi)$ ]]; then
	curl -o /tmp/libva1.deb -J -L http://mirrors.cat.pdx.edu/ubuntu/pool/universe/libv/libva/libva1_1.8.3-2_amd64.deb
	sudo gdebi -n /tmp/libva1.deb
else
	sudo apt-get install -y libva1
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Java Open Chess cross-platform, Java-based chess client/engine from package
APP_NAME=jChess
APP_GUI_NAME="Cross-platform, Java-based chess client/engine."
APP_VERSION=1.5
APP_EXT=zip
FILE_NAME=joChess-${APP_VERSION}
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://downloads.sourceforge.net/javaopenchess/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${APP_NAME,,}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}/${APP_NAME}-${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}-${APP_VERSION}.jar
Icon=/opt/${APP_NAME,,}/theme/default/images/King-W100.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Chess;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Modules environment variable configuration/management utility from source
APP_NAME=Modules
APP_GUI_NAME="Environment variable configuration/management utility."
APP_VERSION=4.1.3
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y tcl8.6-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Project GoldStars Calculator cross-platform, Java-based command-line and GUI calculators from package
APP_NAME="Project GoldStars Calculator"
APP_GUI_NAME="Cross-platform, Java-based command-line and GUI calculators."
APP_VERSION="2.4 Final Version"
APP_EXT=jar
FILE_NAME=${APP_NAME// /.}.S.${APP_VERSION// /.}
DIR_NAME=${APP_NAME,,// /}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/ShakeelAlibhai/${APP_NAME// /}S/releases/download/v${APP_VERSION// Update /.}/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${DIR_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${DIR_NAME,,}
cat > /tmp/${DIR_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${DIR_NAME,,}
Exec=java -jar /opt/${DIR_NAME,,}/${FILE_NAME}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Education;
Keywords=Math;Calculator;
EOF
sudo mv /tmp/${DIR_NAME,,}.desktop /usr/share/applications/
FILE_NAME=${FILE_NAME//.S./.C.}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/ShakeelAlibhai/${APP_NAME// /}S/releases/download/v${APP_VERSION// Update /.}/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${DIR_NAME,,}
cat > /tmp/${DIR_NAME,,} << EOF
#! /bin/sh
cd /opt/${DIR_NAME,,}
PATH=/opt/${DIR_NAME,,}:\$PATH; export PATH
java -jar /opt/${DIR_NAME,,}/${FILE_NAME}.jar "\$1"
cd $HOME
EOF
sudo mv /tmp/${DIR_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install dred fast, minimalist cross-platform, GTK+-based text editor from source
APP_NAME=dred
APP_GUI_NAME="Environment variable configuration/management utility."
APP_VERSION=0.4.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtk-3-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/dr-soft/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
cc ./source/dred/dred_main.c -o dred `pkg-config --cflags --libs gtk+-3.0` -lm -ldl
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
sudo mv /tmp/${FILE_NAME}/resources/images/logo.png /usr/local/share/pixmaps/${APP_NAME,,}.png
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
Categories=Accessories;Development;Programming;
Keywords=Text;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Crosswire SWORD Bible research and study platform from source
APP_NAME=SWORD
APP_GUI_NAME="Bible research and study platform."
APP_VERSION=1.8.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y automake libtool libclucene-dev libqt5clucene5 libcurl4-openssl-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://crosswire.org/ftpmirror/pub/sword/source/v1.8/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./autogen.sh && ./usrinst.sh && make && sudo make install && sudo make install_config
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Bibletime cross-platform Bible study software using Crosswire SWORD toolkit from source
# Crosswire SWORD toolkit must be install FIRST; see above.
APP_NAME=Bibletime
APP_GUI_NAME="Cross-platform Bible study software using Crosswire SWORD toolkit."
APP_VERSION=2.11.2
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y qt5-default cmake libclucene-dev libqt5svg5-dev libqt5webkit5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
# Update minimum version of Qt library to 5.5 for CMake
UPDATE_STRING=s/REQUIRED_QT_VERSION 5.9/REQUIRED_QT_VERSION 5.5/g
sudo sed -i ${UPDATE_STRING} /tmp/${FILE_NAME}/CMakeLists.txt
mkdir -p ./build && cd ./build
cmake -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr/local ..
make clean && make && sudo make -j4 install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install CloudFiler cross-platorm, Python-based Amazon S3/Google Cloud client from package
APP_NAME=CloudFiler
APP_GUI_NAME="Cross-platform, Python-based Amazon S3/Google Cloud client."
APP_VERSION=1.3
APP_EXT=zip
FILE_NAME=${APP_NAME}Source_${APP_VERSION}
sudo apt-get install -y python-wxgtk3.0 python-wxtools wx3.0-i18n python-boto python-keyring python-passlib
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/cloud-filer/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo ./install.sh
sudo rm -rf $HOME/.local/share/applications/${APP_NAME,,}.desktop
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /usr/local/${APP_NAME}
PATH=/usr/local/${APP_NAME}:\$PATH; export PATH
python /usr/local/${APP_NAME}/python/${APP_NAME}.py
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${DIR_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/${APP_NAME}
Exec=python /usr/local/${APP_NAME}/python/${APP_NAME}.py
Icon=/usr/local/${APP_NAME}/python/images/${APP_NAME}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Amazon;S3;Google;Cloud;
EOF
sudo mv /tmp/${DIR_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Pomolectron cross-platform, Electron-based desktop Pomodoro application from package
APP_NAME=Pomolectron
APP_GUI_NAME="Cross-platform, Electron-based desktop Pomodoro application."
APP_VERSION=1.1.0
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
FILE_NAME=${APP_NAME}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/amitmerchant1990/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${APP_NAME}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Pomodoro;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install aclh Python-based asynchronous command-line HTTP client via PIP
APP_NAME=aclh
APP_GUI_NAME="Cross-platform, Python-based asynchronous command-line HTTP client."
APP_VERSION=N/A
APP_EXT=N/A
sudo pip3 install git+https://github.com/kanishka-linux/aclh.git

# Install WebComics minimalist PyQt-based desktop tool for reading web comics from package
APP_NAME=WebComics
APP_GUI_NAME="Minimalist PyQt-based desktop tool for reading web comics."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install python3-pyqt5
sudo pip3 install pillow bs4
sudo pip3 install git+https://github.com/kanishka-linux/vinanti.git
cd /tmp
git clone https://github.com/kanishka-linux/${APP_NAME}
cd /tmp/${APP_NAME}
python3 setup.py sdist
cd /tmp/${APP_NAME}/dist
sudo pip3 install ${APP_NAME}*
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Yosoro cross-platform, Electron-based desktop notepad with Markdown support and One Drive cloud backup from package
APP_NAME=Yosoro
APP_GUI_NAME="Cross-platform, Electron-based desktop notepad with Markdown support and One Drive cloud backup."
APP_VERSION=1.0.6
APP_EXT=zip
FILE_NAME=${APP_NAME}-linux-x64-deb-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/IceEnd/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}/${APP_NAME,,}*.deb
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Meld GUI file diff/merge utility from source
APP_NAME=Meld
APP_GUI_NAME="Cross-platform, file diff/merge utility."
APP_VERSION=3.18.2
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get build-dep -y meld python3-cairo-dev libgtksourceview-3.0-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download.gnome.org/sources/${APP_NAME,,}/${APP_VERSION//.2/}/${FILE_NAME}.${APP_EXT}
https://download.gnome.org/sources/meld//meld-3.18.2.tar.xz
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo python3 setup.py install --prefix=/usr/local
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Orange Calculator minimalist Java-based calculator from Debian package
# http://www.wagemaker.co.uk/
APP_NAME=OrangeCalc
APP_GUI_NAME="Minimalist Java-based calculator."
APP_VERSION=1.5.8
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/orangecalculator/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Small Text Pad minimalist Java-based notepad from Debian package
# http://www.wagemaker.co.uk/
APP_NAME=SmallTextPad
APP_GUI_NAME="Minimalist Java-based notepad."
APP_VERSION=1.3.5
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install UnNetHack Roguelike adventure game forked from NetHack from source
APP_NAME=UnNetHack
APP_GUI_NAME="Roguelike adventure game forked from NetHack."
APP_VERSION=5.1.0-20131208
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y flex bison libncursesw5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make -j4 install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install lf cross-platform, Go-based file manager for the shell/console from package
APP_NAME=lf
APP_GUI_NAME="Cross-platform, Go-based file manager for the shell/console."
APP_VERSION=r6
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=386
fi
FILE_NAME=${APP_NAME,,}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/gokcehan/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Mokomaze SDL-based ball labyrinth puzzle game from source
APP_NAME=Mokomaze
APP_GUI_NAME="SDL-based ball labyrinth puzzle game."
APP_VERSION=0.7.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libjson-glib-dev libode-dev libsdl-gfx1.2-dev libsdl-ttf2.0-dev libsdl-image1.2-dev xsltproc autoconf libsdl1.2-dev librsvg2-dev libargtable2-dev libguichan-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./autogen.sh && ./configure && make && sudo make -j4 install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Semantik Python-based mind-mapping tool from Debian package
# https://waf.io/semantik.html
APP_NAME=Semantik
APP_GUI_NAME="Python-based mind-mapping tool."
APP_VERSION=1.0.4-24
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://waf.io/rpms/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install PDFBox Java-based, cross-platform command-line PDF manipulation application from package
APP_NAME=PDFBox
APP_GUI_NAME="Java-based, cross-platform command-line PDF manipulation application."
APP_VERSION=2.0.10
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-app-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://apache.osuosl.org/${APP_NAME,,}/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install MagiTerm cross-platform SDL2-based BBS SSH terminal from Debian package
# https://magickabbs.com/index.php/magiterm/
APP_NAME=MagiTerm
APP_GUI_NAME="Cross-platform SDL2-based BBS SSH terminal."
APP_VERSION=0.9.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
source /etc/lsb-release
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download.opensuse.org/repositories/home:/apamment/xUbuntu_${DISTRIB_RELEASE}/${KERNEL_TYPE}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Ket cross-platform, Java-based interactive math editor with LaTeX and HTML export from package
APP_NAME=Ket
APP_GUI_NAME="Cross-platform, Java-based interactive math editor with LaTeX and HTML export."
APP_VERSION=0.6.03
APP_EXT=jar
FILE_NAME=${APP_NAME,,}${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Development;Programming;
Keywords=Math;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install gcdemu GTK+-based CD emulation utility from PPA
APP_NAME=gcdemu
APP_GUI_NAME="GTK+-based CD emulation utility."
APP_VERSION=3.2.1
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo add-apt-repository -y ppa:cdemu/ppa
sudo apt-get update
sudo apt-get install -y gcdemu cdemu-daemon cdemu-client 

# Install Fresh Memory cross-platform flash card learning tool with Spaced Repetition method from Debian package
# http://fresh-memory.com/
APP_NAME=FreshMemory
APP_GUI_NAME="Cross-platform flash card learning tool with Spaced Repetition method."
APP_VERSION=1.5.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Sohag Developer cross-platform tool for generating Qt C++ classes for data management in PostgreSQL databases from package
# http://sohag-developer.com/
APP_NAME=Sohag-Developer
APP_GUI_NAME="Cross-platformtool for generating Qt C++ classes for data management in PostgreSQL databases."
APP_VERSION=V2
APP_EXT=tar.xz
FILE_NAME=sohagDeveloper${APP_VERSION}Linux64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/sohag*/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Qt;PostgreSQL;C++;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Clippy cross-platform, Electron-based clipboard manager with persistent history from AppImage
APP_NAME=Clippy
APP_GUI_NAME="Cross-platform, Electron-based clipboard manager with persistent history."
APP_VERSION=1.2.0
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/ikouchiha47/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Clipboard;Productivity;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Parlatype GTK+-based audio player for transcription from source
APP_NAME=Parlatype
APP_GUI_NAME="GTK+-based audio player for transcription."
APP_VERSION=1.5.5
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y build-essential automake autoconf intltool libgirepository1.0-dev libgladeui-dev gtk-doc-tools yelp-tools libgtk-3-dev libgtk-3-0 libgstreamer1.0-dev libgstreamer1.0-0 libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly libreoffice-script-provider-python itstool
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/gkarsay/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make -j4 install
echo '/usr/local/lib' | sudo tee -a /etc/ld.so.conf.d/${APP_NAME,,}.conf > /dev/null && sudo ldconfig
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Klein minimalist console-based text editor from source
APP_NAME=Klein
APP_GUI_NAME="Minimalist console-based text editor."
APP_VERSION=1.1-src-11-2018
APP_EXT=tar
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libncurses-dev libpth-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/mycced/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}
make && sudo make -j4 install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install gcsf FUSE file system based on Google Drive from package
APP_NAME=gcsf
APP_GUI_NAME="FUSE file system based on Google Drive."
APP_VERSION=0.1.6
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}-${ARCH_TYPE}-unknown-linux-gnu
sudo apt-get install -y fuse
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/harababurel/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Keepboard cross-platform, Java-based clipboard manager from package
APP_NAME=Keepboard
APP_GUI_NAME="Cross-platform, Java-based clipboard manager."
APP_VERSION=5.2
APP_EXT=zip
FILE_NAME=${APP_NAME}_Linux_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/jar.jar
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
Exec=java -jar /opt/${APP_NAME,,}/jar.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Clipboard;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install NumericalChameleon cross-platform, Java-based unit converter/calculator from Debian package
# http://numericalchameleon.net/en/index.html
APP_NAME=NumericalChameleon
APP_GUI_NAME="Cross-platform, Java-based unit converter/calculator."
APP_VERSION=2.1.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/numchameleon/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install TreeSheets Free-Form Data Organizer (Hierarchical Spreadsheet) from package
APP_NAME=TreeSheets
APP_GUI_NAME="Free-Form Data Organizer (Hierarchical Spreadsheet)."
APP_VERSION=N/A
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux64
fi
FILE_NAME=${APP_NAME,,}_${ARCH_TYPE}
curl -o /tmp/libpng12.deb -J -L http://ftp.osuosl.org/pub/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/libpng12.deb
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://strlen.com/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/TS/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/treesheets
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
Exec=/opt/${APP_NAME,,}/treesheets "\$1"
Icon=/opt/${APP_NAME,,}/images/icon32.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=Spreadsheet;Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Reversee Electron-based reverse-proxy web debugger from package
APP_NAME=Reversee
APP_GUI_NAME="Electron-based reverse-proxy web debugger."
APP_VERSION=0.0.16
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download.reversee.ninja/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=HTTP;Proxy;Testing;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install IceHRM web-based Human Resources Management (HRM) tool
APP_NAME=IceHRM
APP_GUI_NAME="Web-based Human Resources Management (HRM)"
APP_VERSION=24.0.0
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}_v${APP_VERSION}.OS
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n ${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+x ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+r ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/app/install/index.php &
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php &
Icon=${WWW_HOME}/${APP_NAME,,}/web/images/logo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=HRM;Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/

# Install ODrive cross-platform, Electron-based GUI for Google Drive from Debian package
APP_NAME=ODrive
APP_GUI_NAME="Cross-platform, Electron-based GUI for Google Drive."
APP_VERSION=0.2.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/liberodark/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install TEA Qt-based text editor from source
APP_NAME=TEA
APP_GUI_NAME="Cross-platform Qt-based text editor."
APP_VERSION=47.1.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y qt5-default qt5-qmake
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/psemiletov/tea-qt/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}-qt-${APP_VERSION}
qtchooser -run-tool=qmake -qt=5 src.pro && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Sielo Qt- and WebEngine-based web browser from AppImage
APP_NAME=SieloBrowser
APP_GUI_NAME="Qt- and WebEngine-based web browser."
APP_VERSION=1.16.07
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/sielo-browser.AppImage
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=Web;Browser;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Slap Sublime Text-style JavaScript-based console text editor from source
APP_NAME=Slap
APP_GUI_NAME="Sublime Text-style JavaScript-based console text editor."
APP_VERSION=N/A
APP_EXT=tar.gz
curl -sL https://raw.githubusercontent.com/slap-editor/slap/master/install.sh | sh
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Universal Tag Finder cross-platform, Java-based HTML tag file search utility from Debian package
APP_NAME=Universal-Tag-Finder
APP_GUI_NAME="Cross-platform, Java-based HTML tag file search utility."
APP_VERSION=1.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Gopherus cross-platform console-mode gopher client from source
APP_NAME=Gopherus
APP_GUI_NAME="Cross-platform console-mode gopher client."
APP_VERSION=1.1
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libsdl2-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
cp ./Makefile.lin ./Makefile
make
# No 'make install' target, so copy files manually.
sudo cp ./${APP_NAME,,} /usr/local/bin
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Elegant Calculator Java Swing-based minimalist calculator from package
APP_NAME=Calculator
APP_GUI_NAME="Java Swing-based minimalist calculator."
APP_VERSION=V3.5
APP_EXT=jar
FILE_NAME=${APP_NAME}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/vasilivich0/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Elegant Calculator
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Calculator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Mindmapp Electron-based desktop mind mapping tool from Debian package
APP_NAME=Mindmapp
APP_GUI_NAME="Electron-based desktop mind mapping tool."
APP_VERSION=0.7.9
APP_EXT=deb
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install PharTools PHP CLI utility for managing phar (PHP ARchive) files from source
APP_NAME=PharTools
APP_GUI_NAME="PHP CLI utility for managing phar (PHP ARchive) files."
APP_VERSION=v2.1
APP_EXT=zip
FILE_NAME=${APP_NAME}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/EvolSoft/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp /tmp/${FILE_NAME}/${APP_NAME}/${APP_NAME,,}.sh /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}.sh
sudo ln -f -s /usr/local/bin/${APP_NAME,,}.sh /usr/local/bin/${APP_NAME,,}
sudo sed -i 's@;phar.readonly = On@phar.readonly = Off@g' /etc/php/5.6/cli/php.ini
sudo sed -i 's@;phar.readonly = On@phar.readonly = Off@g' /etc/php/7.0/cli/php.ini
sudo sed -i 's@;phar.readonly = On@phar.readonly = Off@g' /etc/php/7.1/cli/php.ini
sudo sed -i 's@;phar.readonly = On@phar.readonly = Off@g' /etc/php/7.2/cli/php.ini
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install MyPGP Java Swing-based GUI for PGP encrypting/signing from package
APP_NAME=MyPGP
APP_GUI_NAME="Java Swing-based GUI for PGP encrypting/signing."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
sudo apt-get install -y libbcprov-java libbcpg-java 
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/my-pgp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=PGP;Security;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Virtual Celestial Globe Java-based planetarium software from package
APP_NAME="Virtual Celestial Globe"
APP_GUI_NAME="Java-based planetarium software."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME// /}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${FILE_NAME,,}/VirutalCelestialGlobe.${APP_EXT}
sudo mkdir -p /opt/${FILE_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${FILE_NAME,,}
cat > /tmp/${FILE_NAME,,} << EOF
#! /bin/sh
cd /opt/${FILE_NAME,,}
PATH=/opt/${FILE_NAME,,}:\$PATH; export PATH
java -Xms128m -Xmx512m -classpath /opt/${FILE_NAME,,}/${FILE_NAME}.${APP_EXT} com.main.GlobeFrame
cd $HOME
EOF
sudo mv /tmp/${FILE_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${FILE_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${FILE_NAME,,}
Exec=java -Xms128m -Xmx512m -classpath /opt/${FILE_NAME,,}/${FILE_NAME}.${APP_EXT} com.main.GlobeFrame
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Science;
Keywords=Stars;Planetarium;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${FILE_NAME}*

# Install Safe File Manager Java-based minimalist file manager from package
APP_NAME=SafeFileManager
APP_GUI_NAME="Java-based minimalist file manager."
APP_VERSION=1.1
APP_EXT=jar
FILE_NAME=${APP_NAME}_v${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://www.mindbytez.com/sfm/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install browsh cross-platform modern browser for shell/console from Debian package
APP_NAME=browsh
APP_GUI_NAME="Cross-platform modern browser for shell/console."
APP_VERSION=1.2.2
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_linux_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/browsh-org/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install ZDT (Zhongwen Development Tool) Java-based flash card utility for learning Mandarin Chinese from package
APP_NAME=ZDT
APP_GUI_NAME="Java-based flash card utility for learning Mandarin Chinese."
APP_VERSION=1.0.3
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/icon.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;
Keywords=Language;Chinese;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install eLogSim digital circuit simulator from package
APP_NAME=eLogSim
APP_GUI_NAME="Digital circuit simulator."
APP_VERSION=2.2.0
APP_EXT=zip
FILE_NAME=My${APP_NAME}_${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo mv /opt/${APP_NAME,,}/${APP_NAME} /opt/${APP_NAME,,}/${APP_NAME}.app
sudo mv /opt/${APP_NAME,,}/${APP_NAME}.app/* /opt/${APP_NAME,,}
sudo rm -rf /opt/${APP_NAME,,}/${APP_NAME}.app /opt/${APP_NAME,,}/${APP_NAME}.exe
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/${APP_NAME}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Electronics;
Keywords=Electronics;Digital;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Rodent GTK+-based GUI file manager from source
APP_NAME=Rodent
APP_GUI_NAME="GTK+-based GUI file manager."
APP_VERSION=5.3.16.3
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtk2.0-dev libgtk-3-dev automake libzip-dev librsvg2-dev libxml2-dev libmagic-dev
TEMP_FILE_NAME=libdbh2-5.0.22
TEMP_APP_EXT=tar.gz
curl -o /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT} -J -L https://downloads.sourceforge.net/dbh/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
cd /tmp
dtrx -n /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
cd /tmp/${TEMP_FILE_NAME}
./autogen.sh && ./configure && make && sudo make install
TEMP_FILE_NAME=libtubo0_5.0.14-1_${KERNEL_TYPE}
TEMP_APP_EXT=deb
curl -o /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT} -J -L https://downloads.sourceforge.net/xffm/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
sudo gdebi -n /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
TEMP_FILE_NAME=libtubo0-dev_5.0.14-1_${KERNEL_TYPE}
TEMP_APP_EXT=deb
curl -o /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT} -J -L https://downloads.sourceforge.net/xffm/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
sudo gdebi -n /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
TEMP_FILE_NAME=librfm5-5.3.16.4
TEMP_APP_EXT=tar.bz2
curl -o /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT} -J -L https://downloads.sourceforge.net/xffm/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
cd /tmp
dtrx -n /tmp/${TEMP_FILE_NAME}.${TEMP_APP_EXT}
cd /tmp/${TEMP_FILE_NAME}
./autogen.sh && ./configure && make && sudo make install && sudo ldconfig
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/xffm/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./autogen.sh && ./configure && make && sudo make install
sudo cp /tmp/${FILE_NAME}/apps/rodent-fm/${APP_NAME}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install fre:ac audio converter and CD ripper from package
APP_NAME="fre:ac"
APP_GUI_NAME="Audio converter and CD ripper."
APP_VERSION=1.1-alpha-20180716
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux-x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux
fi
FILE_NAME=${APP_NAME//:/}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/bonkenc/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME//:/}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME//:/}
sudo ln -f -s /opt/${APP_NAME//:/}/${APP_NAME//:/} /usr/local/bin/${APP_NAME//:/}
sudo ln -f -s /opt/${APP_NAME//:/}/${APP_NAME//:/}cmd /usr/local/bin/${APP_NAME//:/}cmd
cat > /tmp/${APP_NAME//:/}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME//:/}
Exec=/usr/local/bin/${APP_NAME//:/}
Icon=/opt/${APP_NAME//:/}/icons/${APP_NAME//:/}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Multimedia;Audio;
Keywords=Audio;Converter;
EOF
sudo mv /tmp/${APP_NAME//:/}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install PMan desktop media player and media management tool from Debian package
APP_NAME=PMan
APP_GUI_NAME="Desktop media player and media management tool."
APP_VERSION=0.8.9
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/pman-player/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install OpenProject from PPA
APP_NAME=OpenProject
APP_VERSION=N/A
APP_EXT=N/A
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
sudo apt-get install -y apt-transport-https
# If Ubuntu version is above 16.04 (Xenial), then we need to install some packages from 16.04.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(ya|ze|ar|bi)$ ]]; then
    curl -o /tmp/libreadline6.deb -J -L http://ftp.osuosl.org/pub/ubuntu/pool/main/r/readline6/libreadline6_6.3-8ubuntu2_amd64.deb
    sudo gdebi -n /tmp/libreadline6.deb
    curl -o /tmp/libevent-core.deb -J -L http://security.ubuntu.com/ubuntu/pool/main/libe/libevent/libevent-core-2.0-5_2.0.21-stable-2ubuntu0.16.04.1_amd64.deb
    sudo gdebi -n /tmp/libevent-core.deb
    curl -o /tmp/libevent.deb -J -L http://security.ubuntu.com/ubuntu/pool/main/libe/libevent/libevent-2.0-5_2.0.21-stable-2ubuntu0.16.04.1_amd64.deb
    sudo gdebi -n /tmp/libevent.deb
    curl -o /tmp/libevent-extra.deb -J -L http://security.ubuntu.com/ubuntu/pool/main/libe/libevent/libevent-extra-2.0-5_2.0.21-stable-2ubuntu0.16.04.1_amd64.deb
    sudo gdebi -n /tmp/libevent-extra.deb
fi
wget -qO- https://dl.packager.io/srv/opf/openproject-ce/key | sudo apt-key add -
sudo wget -O /etc/apt/sources.list.d/openproject-ce.list https://dl.packager.io/srv/opf/openproject-ce/stable/7/installer/ubuntu/16.04.repo
sudo apt-get install -y openproject
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
sudo openproject configure

# Install Rachota Java-based minimalist desktop time-tracking tool from package
APP_NAME=Rachota
APP_GUI_NAME="Java-based minimalist desktop time-tracking tool."
APP_VERSION=2.4
APP_EXT=jar
FILE_NAME=${APP_NAME,,}_${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Time;Tracking;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Password Safe cross-platform password manager from Debian package
APP_NAME=PasswordSafe
APP_GUI_NAME="Cross-platform password manager."
APP_VERSION=1.07.0-BETA
APP_EXT=deb
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(bi|co)$ ]]; then
	APP_DISTRO=ubuntu18
else
	APP_DISTRO=ubuntu16
fi
FILE_NAME=${APP_NAME,,}-${APP_DISTRO}-${APP_VERSION}.${KERNEL_TYPE}
# If Ubuntu version is above 16.04 (Xenial), then we need to install some packages from 16.04.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(ya|ze|ar|bi)$ ]]; then
    curl -o /tmp/libicu55.deb -J -L http://security.ubuntu.com/ubuntu/pool/main/i/icu/libicu55_55.1-7ubuntu0.4_amd64.deb
    sudo gdebi -n /tmp/libicu55.deb
    curl -o /tmp/libxerces-c3.1.deb -J -L http://ftp.osuosl.org/pub/ubuntu/pool/universe/x/xerces-c/libxerces-c3.1_3.1.3+debian-1_${KERNEL_TYPE}.deb
    sudo gdebi -n /tmp/libxerces-c3.1.deb
    curl -o /tmp/libqrencode3.deb -J -L http://ftp.debian.org/debian/pool/main/q/qrencode/libqrencode3_3.4.4-1+b2_amd64.deb
    sudo gdebi -n /tmp/libqrencode3.deb
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Paperboy shell/console-based PDF management utility from package
APP_NAME=PBoy
APP_GUI_NAME="Shell/console-based PDF management utility."
APP_VERSION=1.0.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/2mol/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Anki flash card utility from package
APP_NAME=Anki
APP_GUI_NAME="Flash card utility."
APP_VERSION=2.0.52
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://apps.ankiweb.net/downloads/current/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}
sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install BWPing network ping utility based on ICMP echo request/echo reply mechanism from source
APP_NAME=BWPing
APP_GUI_NAME="Network ping utility based on ICMP echo request/echo reply mechanism."
APP_VERSION=1.9
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Ngraph-GTK tool for creating 2D graphs with support for exporting to PostScript, SVG, PNG or PDF from source
APP_NAME=Ngraph-GTK
APP_GUI_NAME="Tool for creating 2D graphs with support for exporting to PostScript, SVG, PNG or PDF."
APP_VERSION=6.07.07
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtk-3-dev automake libzip-dev librsvg2-dev libxml2-dev libmagic-dev libgtksourceview-3.0-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install && sudo ldconfig
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install XFE GUI file manager from source
APP_NAME=XFE
APP_GUI_NAME="GUI file manager."
APP_VERSION=1.43.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libcups2-dev libcupsimage2-dev libfox-1.6-0 libfox-1.6-dev libjbig-dev libjpeg-dev libjpeg-turbo8-dev libjpeg8-dev liblzma-dev libtiff-dev libtiff5-dev libtiffxx5 libxcb-util-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install && sudo ldconfig
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install WordTsar GTK-based WordStar text editor clone from package
APP_NAME=WordTsar
APP_GUI_NAME="GTK-based WordStar text editor clone."
APP_VERSION=0.1.1572
APP_EXT=zip
FILE_NAME=${APP_NAME}-gtk2-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Word;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install QtFM lightweight desktop-independent GUI file manager from source
APP_NAME=QtFM
APP_GUI_NAME="Lightweight desktop-independent GUI file manager."
APP_VERSION=6.1.9
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/rodlie/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
mkdir build && cd build
qtchooser -run-tool=qmake -qt=5 CONFIG+=release PREFIX=/usr/local .. && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install myAgilePomodoro Java-based Pomodoro timer from package
APP_NAME=myAgilePomodoro
APP_GUI_NAME="Java-based Pomodoro timer."
APP_VERSION=4.2.0
APP_EXT=jar
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/mypomodoro/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;Accessories;
Keywords=Time;Tracking;Agile;Pomodoro;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Mu Editor Python text editor via Pip
APP_NAME=mu-editor
sudo pip3 install shortcut
sudo pip3 install ${APP_NAME}

# Install NoteCase GTK-based hierarchical notepad/outliner from Debian package
APP_NAME=NoteCase
APP_GUI_NAME="GTK-based hierarchical notepad/outliner."
APP_VERSION=1.9.8
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
sudo apt-get install -y libgnomevfs2-0 libgtksourceview2.0-0
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install BOUML Java-based UML modeling and code generation tool from PPA
APP_NAME=BOUML
APP_GUI_NAME="Java-based UML modeling and code generation tool."
APP_VERSION=N/A
APP_EXT=N/A
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ (tr|ut|vi|wi)$ ]]; then  # 14.04, 14.10, 15.04, 15.10
	DISTRIB_CODENAME=trusty
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ (pr|qu|ra|sa)$ ]]; then  # 13.10, 13.04, 12.10, 12.04
	DISTRIB_CODENAME=precise
fi
wget -q https://www.bouml.fr/bouml_key.asc -O- | sudo apt-key add -
echo "deb https://www.bouml.fr/apt/"${DISTRIB_CODENAME}" "${DISTRIB_CODENAME}" free" | sudo tee -a /etc/apt/sources.list
sudo apt-get update -y
sudo apt-get install -y bouml

# Install Cmajor C#-style programming language and IDE from package
APP_NAME=Cmajor
APP_GUI_NAME="C#-style programming language and IDE."
APP_VERSION=3.1.0
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-ubuntu-14.04-x86_64-binaries
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.bz2
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.tar/${APP_NAME,,}-${APP_VERSION}/* /opt/${APP_NAME,,}
sudo ln -s /usr/lib/x86_64-linux-gnu/libboost_filesystem.so.1.6* /usr/lib/x86_64-linux-gnu/libboost_filesystem.so.1.64.0
sudo ln -s /usr/lib/x86_64-linux-gnu/libboost_system.so.1.6* /usr/lib/x86_64-linux-gnu/libboost_system.so.1.64.0
echo 'CMAJOR_ROOT=/opt/'${APP_NAME,,}'; export CMAJOR_ROOT;' >> $HOME/.bashrc
echo 'PATH=$PATH:$CMAJOR_ROOT/bin' >> $HOME/.bashrc
echo 'LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CMAJOR_ROOT/lib' >> $HOME/.bashrc
source $HOME/.bashrc
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install MicroPad Electron-based notepad with MarkDown support from Debian package
APP_NAME=MicroPad
APP_GUI_NAME="Electron-based notepad with MarkDown support."
APP_VERSION=3.8.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/Electron/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install TimeSlotTracker Java-based minimalist time tracking tool from Debian package
APP_NAME=TimeSlotTracker
APP_GUI_NAME="Java-based minimalist time tracking tool."
APP_VERSION=1.3.21
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install HHDB SQL Admin Java-based GUI PostgreSQL client from package
APP_NAME="HHDB SQL Admin"
APP_GUI_NAME="Java-based GUI PostgreSQL client."
APP_VERSION=4.5.1
APP_EXT=tar.gz
FILE_NAME=hhdb_csadmin_Linux_v${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/hhdb-admin/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/hhdb_csadmin /opt
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/hhdb_csadmin << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/hhdb_csadmin:\$PATH; export PATH
/opt/hhdb_csadmin/start_csadmin.sh
cd $HOME
EOF
sudo mv /tmp/hhdb_csadmin /usr/local/bin
sudo chmod a+x /usr/local/bin/hhdb_csadmin
cat > /tmp/hhdb_csadmin.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/hhdb_csadmin
Exec=/opt/hhdb_csadmin/start_csadmin.sh
Icon=/opt/hhdb_csadmin/etc/icon/manage.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Database;PostgreSQL;
EOF
sudo mv /tmp/hhdb_csadmin.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/hhdb_csadmin*

# Install TabuVis Java-based interactive visualization of tabular data tool from package
APP_NAME=TabuVis
APP_GUI_NAME="Java-based interactive visualization of tabular data tool."
APP_VERSION=N/A
APP_EXT=zip
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME} /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:\$PATH; export PATH
java -jar /opt/${APP_NAME}/${APP_NAME}.jar
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
Exec=java -jar /opt/${APP_NAME}/${APP_NAME}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;Science;
Keywords=Data;Science;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install FromScratch Electron-based simple note-taking and "to do" tool from Debian package
APP_NAME=FromScratch
APP_GUI_NAME="Electron-based simple note-taking and \"to do\" tool."
APP_VERSION=1.4.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/Kilian/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install VNote Vim-inspired note-taking application with MarkDown support from App Image
APP_NAME=VNote
APP_GUI_NAME="Vim-inspired note-taking application with MarkDown support."
APP_VERSION=2.4
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=i386
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86_64
fi
FILE_NAME=${APP_NAME}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/tamlok/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s -f /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Notepad;MarkDown;Vim;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Open Visual Traceroute Java-based GUI traceroute utility from Debian package
APP_NAME=OVTR
APP_GUI_NAME="Java-based GUI traceroute utility."
APP_VERSION=1.7.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ (bi|bi)$ ]]; then  # 18.04
    # Install gksu package from 17.10 (Artful)
    # https://askubuntu.com/questions/1030054/how-to-install-an-application-that-requires-gksu-package-on-ubuntu-18-04
    curl -o /tmp/libgksu2-0.${APP_EXT} -J -L http://ftp.osuosl.org/pub/ubuntu/pool/universe/libg/libgksu/libgksu2-0_2.0.13~pre1-9ubuntu2_${KERNEL_TYPE}.${APP_EXT}
    sudo gdebi -n /tmp/libgksu2-0.${APP_EXT}
    curl -o /tmp/gksu.${APP_EXT} -J -L http://ftp.osuosl.org/pub/ubuntu/pool/universe/g/gksu/gksu_2.0.2-9ubuntu1_${KERNEL_TYPE}.${APP_EXT}
    sudo gdebi -n /tmp/gksu.${APP_EXT}
fi
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/openvisualtrace/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Golden Scrabble multi-language GUI Scrabble crossword game from package
APP_NAME=GScrabble
APP_GUI_NAME="Multi-language GUI Scrabble crossword game."
APP_VERSION=0.1.2
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo python3 ./setup.py install
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install FullSync Java-based data synchronization tool with support for S/FTP and scheduling from package
APP_NAME=FullSync
APP_GUI_NAME="Java-based data synchronization tool with support for S/FTP and scheduling."
APP_VERSION=0.10.4
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}-linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}-${APP_VERSION}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Backup;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install MiniPacman minimalist console Pacman using ASCII characters built with SFML from package
APP_NAME=MiniPacman
APP_GUI_NAME="Minimalist console Pacman using ASCII characters built with SFML."
APP_VERSION=30jul18
APP_EXT=tar.gz
FILE_NAME=mpac${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/pacman/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/pacman_gnu /usr/bin/${APP_NAME,,}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Elastic Notepad Java-based text editor with "intelligent" tab stops from package
APP_NAME=ElasticNotepad
APP_GUI_NAME="Java-based text editor with \"intelligent\" tab stops."
APP_VERSION=1.3.0
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/nickgravgaard/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Accessories;Development;Science;
Keywords=Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Wipe Free Space utility to securely erase free space from source
APP_NAME=WipeFreeSpace
APP_GUI_NAME="Utility to securely erase free space."
APP_VERSION=2.2.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libext2fs-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install && sudo ldconfig
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install meo geo-aware journal and personal information manager (PIM) from AppImage
APP_NAME=meo
APP_GUI_NAME="Geo-aware journal and personal information manager (PIM)."
APP_VERSION=N/A
APP_EXT=AppImage
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://rebrand.ly/meo-release-linux
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=PIM;Journal;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install ao elegant cross-platform desktop "to do" application from Debian package
APP_NAME=ao
APP_GUI_NAME="Elegant cross-platform desktop \"to do\" application."
APP_VERSION=5.6.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/klauscfhq/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
sudo rm -rf /tmp/${APP_NAME}*

# Install Too Many Files Python script to delete files based on date from source
APP_NAME=TooManyFiles
APP_GUI_NAME="Python script to delete files based on date."
APP_VERSION=0.1.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo pip3 install cx_Freeze
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/too-many-files/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo python3 ./setup.py install
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install gdcalc console and GTK+ financial, statistics, scientific and programmer's calculator from source
APP_NAME=gdcalc
APP_GUI_NAME="Console and GTK+ financial, statistics, scientific and programmer's calculator."
APP_VERSION=2.17
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgnomeui-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./autogen.sh && ./configure --prefix=/usr/local && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Programming;
Keywords=Calculator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Timeline Project Python-based GUI timeline tool from source
APP_NAME=Timeline
APP_GUI_NAME="Python-based GUI timeline tool."
APP_VERSION=1.19.0
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
# Due to dependencies, we use Python 2.x
sudo apt-get install -y python-wxgtk4.0 python-pip python-pip-whl python-wxgtk-media4.0 python-wxtools python-wxversion python-wxgtk-webview4.0
sudo pip2 install git+https://github.com/thetimelineproj/humblewx.git
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/thetimelineproj/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}/source
PATH=/opt/${APP_NAME,,}/source:\$PATH; export PATH
python2 /opt/${APP_NAME,,}/source/${APP_NAME,,}.py
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}/source
Exec=python2 /opt/${APP_NAME,,}/source/${APP_NAME,,}.py
Icon=/opt/${APP_NAME,,}/icons/${APP_NAME}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=Timeline;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Linux Task Manager (LTM) Java-based GUI/console task viewer/manager from package
APP_NAME=LTM
APP_GUI_NAME="Java-based GUI/console task viewer/manager."
APP_VERSION=4.0
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/dist/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/LinuxTaskMan.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Linux Task Manager (LTM)
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=java -jar /opt/${APP_NAME,,}/LinuxTaskMan.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Task Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SQLiteStudio Qt-based SQLite database GUI client from package
APP_NAME=SQLiteStudio
APP_GUI_NAME="Qt-based SQLite database GUI client."
APP_VERSION=3.2.1
APP_EXT=tar.xz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux32
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux64
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://sqlitestudio.pl/files/sqlitestudio3/complete/${ARCH_TYPE}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/sqlitestudio/sqlitestudio /usr/local/bin/sqlitestudio
sudo ln -f -s /opt/sqlitestudio/sqlitestudiocli /usr/local/bin/sqlitestudiocli
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=Linux Task Manager (LTM)
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/app_icon/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Database;SQLite;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Wexond React/Electron-based minimalist web browser from Debian package
APP_NAME=Wexond
APP_GUI_NAME="React/Electron-based minimalist web browser."
APP_VERSION=1.0.0-beta.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Lyrebird Java-based desktop Twitter client from Debian package
APP_NAME=Lyrebird
APP_GUI_NAME="Java-based desktop Twitter client."
APP_VERSION=1.1.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-DEB
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/Tristan971/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install curl-httpie curl client with HTTPie syntax from Debian package
APP_NAME=curl-httpie
APP_GUI_NAME="Curl client with HTTPie syntax."
APP_VERSION=1.0.0
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux_amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux_386
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/rs/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install YSoccer cross-platform, Java-based retro soccer game from package
APP_NAME=YSoccer
APP_GUI_NAME="Cross-platform, Java-based retro soccer."
APP_VERSION=16
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux32
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux64
fi
FILE_NAME=${APP_NAME,,}${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Soccer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install IdleX Tkinter extensions to Python IDLE IDE from package
APP_NAME=IdleX
APP_GUI_NAME="Tkinter extensions to Python IDLE IDE."
APP_VERSION=1.18
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y idle3
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo python3 ./setup.py install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Python;IDE;IDLE;IDLEX;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install LazyGit Go-based shell GUI for Git from PPA
sudo add-apt-repository -y ppa:lazygit-team/daily
sudo apt-get update -y
sudo apt-get install -y lazygit

# Install UMLet Java-based UML diagram tool from package
APP_NAME=UMLet
APP_GUI_NAME="Java-based UML diagram tool."
APP_VERSION=14.3
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-standalone-${APP_VERSION}.0
sudo apt-get install -y idle3
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://www.umlet.com/${APP_NAME,,}_${APP_VERSION//./_}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME//ML/ml}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
java -Dsun.java2d.xrender=f -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -Dsun.java2d.xrender=f -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=/opt/${APP_NAME,,}/img/${APP_NAME,,}_logo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=UML;Diagramming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Pasang Emas traditional board game from Brunei from source
APP_NAME=Pasang-Emas
APP_GUI_NAME="Traditional board game from Brunei."
APP_VERSION=6.1.0
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y itstool
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure --prefix=/usr/local && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Double Commander dual-pane canonical file manager from package
APP_NAME=DoubleCmd
APP_GUI_NAME="Dual-pane canonical file manager."
APP_VERSION=0.9.4
APP_EXT=tar.xz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}.qt5.${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/* /opt
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$(pwd)
./${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SysUsage Perl-based GUI system monitor from package
APP_NAME=SysUsage
APP_GUI_NAME="Perl-based GUI system monitor."
APP_VERSION=5.7
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y rrdtool librrds-perl sysstat
sudo cpan Proc::Queue
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
perl Makefile.PL && make && sudo make install
sudo ln -f -s /usr/local/${APP_NAME,,}/doc/${APP_NAME,,}.1 /usr/local/man/man1/${APP_NAME,,}.1
sudo chmod -R 777 /usr/local/${APP_NAME,,}/rrdfiles
sudo chmod -R 777 /usr/local/${APP_NAME,,}/etc
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R 777 ${WWW_HOME}/${APP_NAME,,}
# Add cron jobs for scripts
(crontab -l 2>/dev/null; echo "*/1 * * * * /usr/local/sysusage/bin/sysusage > /dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/sysusage/bin/sysusagejqgraph > /dev/null 2>&1") | crontab -
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /usr/local/${APP_NAME,,}
PATH=/usr/local/${APP_NAME,,}:\$PATH; export PATH
xdg-open http://localhost/${APP_NAME,,}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=CPU;Memory;Monitoring;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Converseen Qt-based bulk image converting/resizing tool from source
APP_NAME=Converseen
APP_GUI_NAME="Qt-based bulk image converting/resizing tool."
APP_VERSION=0.9.7.2
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libmagick++-dev cmake qttools5-dev-tools qttools5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
mkdir -p build && cd build
cmake -DCMAKE_INSTALL_PREFIX=/usr/local .. && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install JIVAM cross-platform Java Image Viewer And Manipulator from package
APP_NAME=JIVAM
APP_GUI_NAME="Cross-platform Java Image Viewer And Manipulator."
APP_VERSION=08-08-18
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_bin
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;Accessories;
Keywords=Image Viewer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SJmp3 small Java-based MP3 player from package
APP_NAME=SJmp3
APP_GUI_NAME="Small Java-based MP3 player."
APP_VERSION=08-08-18
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_bin
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;Accessories;
Keywords=Image Viewer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install MultiTextEditor Java-based text editor/word processor from package
APP_NAME=MultiTextEditor
APP_GUI_NAME="Java-based text editor/word processor."
APP_VERSION=3.1
APP_EXT=zip
FILE_NAME=${APP_NAME//M/m}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/* /opt
sudo rm -rf /opt/${APP_NAME//M/m}/java
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME//M/m}
PATH=/opt/${APP_NAME//M/m}:/opt/${APP_NAME//M/m}/lib:\$PATH; export PATH
java -jar /opt/${APP_NAME//M/m}/${APP_NAME//M/m}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME//M/m}:/opt/${APP_NAME//M/m}/lib
Exec=java -jar /opt/${APP_NAME//M/m}/${APP_NAME//M/m}.jar
Icon=/opt/${APP_NAME//M/m}/${APP_NAME//M/m}.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Programming;Development;Accessories;
Keywords=Text Editor;Word Processor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install DaSPyMan Python-based SQLite and CSV file management tool from package
APP_NAME=DaSPyMan
APP_GUI_NAME="Python-based SQLite and CSV file management tool."
APP_VERSION=2V16
APP_EXT=zip
FILE_NAME=${APP_NAME}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/pycsvdb/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/${APP_NAME}.pyw
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
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME}.pyw
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=SQLite;CSV;Database;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install ExeQt small tool for pinning applications to system tray from source
APP_NAME=ExeQt
APP_GUI_NAME="Small tool for pinning applications to system tray."
APP_VERSION=1.2.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/AlexandruIstrate/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}/lib/qtsingleapplication
./configure
sudo ln -s -f /usr/include/x86_64-linux-gnu/qt5/QtCore/qstring.h /usr/include/x86_64-linux-gnu/qt5/QtCore/QStringLiteral
cd /tmp/${FILE_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}
mkdir build && cd build
qtchooser -run-tool=qmake -qt=5 CONFIG+=release PREFIX=/usr/local .. && make && sudo make install
sudo cp /tmp/${FILE_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}/build/TrayIcon /usr/local/bin
sudo ln -f -s /usr/local/bin/TrayIcon /usr/local/bin/${APP_NAME,,}
sudo cp /tmp/${FILE_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}/assets/images/app-icon.png /usr/share/icons/${APP_NAME,,}.png
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/share/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Tray Menu;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install nnn terminal file manager with desktop integration from Debian package
APP_NAME=nnn
APP_GUI_NAME="Terminal file manager with desktop integration."
APP_VERSION=2.2-1
APP_EXT=deb
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(bi|co)$ ]]; then
	DISTRIB_RELEASE=18.04
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(xe|ya|ze|ar|)$ ]]; then
	DISTRIB_RELEASE=16.04
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_ubuntu${DISTRIB_RELEASE}.${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/nnn-file-browser/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Lepton Electron-based Github Gist editor/viewer from Snap package
APP_NAME=Lepton
APP_GUI_NAME="Electron-based Github Gist editor/viewer."
APP_VERSION=1.6.2
APP_EXT=snap
curl -o /tmp/${APP_NAME,,}.${APP_EXT} -J -L https://github.com/hackjutsu/${APP_NAME,,}/releases/download/v${APP_VERSION}/${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo snap install --dangerous /tmp/${APP_NAME,,}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install AsciidocFX JavaFX-based book/document editor to build PDF, EPUB, Mobi and HTML books from package
APP_NAME=AsciidocFX
APP_GUI_NAME="JavaFX-based book/document editor to build PDF, EPUB, Mobi and HTML books."
APP_VERSION=1.6.9
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}_Linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/conf/public/favicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Ebook;PDF;EPUB;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install bs1770gain audio loudness scanner/normalizer from package
APP_NAME=bs1770gain
APP_GUI_NAME="Audio loudness scanner/normalizer."
APP_VERSION=0.5.0-beta-5
APP_EXT=tar.bz2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}/bin/* /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}/doc /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Haxima (a.k.a. Nazghul) retro Ultima-style RPG from Git repository
APP_NAME=Haxima
APP_GUI_NAME="Retro Ultima-style RPG."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=N/A
sudo apt-get install -y libsdl1.2-dev libsdl-image1.2-dev libsdl-mixer1.2-dev automake
cd /tmp
git clone https://git.code.sf.net/p/nazghul/git ${APP_NAME,,}
dtrx -n /tmp/${APP_NAME,,}
./autogen.sh && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/share/nazghul/${APP_NAME,,}
Exec=${APP_NAME,,}.sh
Icon=/usr/local/share/nazghul/${APP_NAME,,}/splash.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=RPG;Ultima;Haxima;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install qBittorrent Qt-based Bittorrent client from source
APP_NAME=qBittorrent
APP_GUI_NAME="Qt-based Bittorrent client."
APP_VERSION=4.1.6
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get build-dep -y ${APP_NAME,,}
sudo apt-get install -y libtorrent-dev libtorrent-rasterbar-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=${APP_NAME,,}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=Bittorrent;P2P;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install UkrChess chess game with historical aspects from package
APP_NAME=UkrChess
APP_GUI_NAME="Chess game with historical aspects."
APP_VERSION=0.22
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=lin64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=lin32
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$(pwd)
./${APP_NAME,,}
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
Exec=export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/opt/${APP_NAME,,}; /opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/assets/pics/title.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Chess;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install GladivsSC Java-based lightweight screen capture tool from package
APP_NAME=GladivsSC
APP_GUI_NAME="Java-based lightweight screen capture tool."
APP_VERSION=0.7c
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux-x86-64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux-x86-32
fi
FILE_NAME=${APP_NAME}-${ARCH_TYPE}
sudo apt-get install -y openjfx
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/gladivs-simple-screen-capture/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/lib/libjnscreencapture.so /usr/lib/x86_64-linux-gnu/libjnscreencapture.so
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$(pwd)/lib
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
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/opt/${APP_NAME,,}/lib; java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Screen Capture;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Vema Python-based minimalist GUI text editor from package
APP_NAME=Vema
APP_GUI_NAME="Python-based minimalist GUI text editor."
APP_VERSION=v1.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}%20-%20${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/vemac/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/vemac*/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/main.py
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
Exec=python3 /opt/${APP_NAME,,}/main.py
Icon=/opt/${APP_NAME,,}/favicon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Accessories;
Keywords=Text Editor;Python;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install iMath LibreOffice extension for numeric and symbolic calculations inside a Writer document from Debian package
APP_NAME=iMath
APP_GUI_NAME="LibreOffice extension for numeric and symbolic calculations inside a Writer document."
APP_VERSION=2.2.6
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/ooo-imath/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install SC-IM ncurses spreadsheet program for terminal from source
APP_NAME=SC-IM
APP_GUI_NAME="Ncurses spreadsheet program for terminal."
APP_VERSION=0.7.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libzip-dev libxml2-dev bison  libncurses5-dev libncursesw5-dev cmake
# Install libxlsxwriter for support of importing Excel XLSX files.
curl -o /tmp/libxlsxwriter-RELEASE_0.7.7.tar.gz -J -L https://github.com/jmcnamara/libxlsxwriter/archive/RELEASE_0.7.7.tar.gz
cd /tmp
dtrx -n /tmp/libxlsxwriter-RELEASE_0.7.7.tar.gz
cd /tmp/libxlsxwriter-RELEASE_0.7.7
mkdir build && cd build
cmake .. && make && sudo make install
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/andmarti1424/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/src
make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install jRCalc Java-based resistor calculator from package
APP_NAME=jRCalc
APP_GUI_NAME="Java-based resistor calculator."
APP_VERSION=0.3
APP_EXT=tgz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y openjfx
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,}.sh /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/icons/icon-${APP_NAME,,}32.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Electronics;Engineering;
Keywords=Resistor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Manuskript editing tool for book writers from Debian package
APP_NAME=Manuskript
APP_GUI_NAME="Editing tool for book writers."
APP_VERSION=0.8.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Gisto Github Gist code snippet management tool from Debian package
APP_NAME=Gisto
APP_GUI_NAME="Github Gist code snippet management tool."
APP_VERSION=1.11.2
APP_EXT=deb
FILE_NAME=${APP_NAME}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Pext Python/Qt-based productivity tool from AppImage
APP_NAME=Pext
APP_GUI_NAME="Python/Qt-based productivity tool."
APP_VERSION=0.23
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Productivity;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install jNPad Java-based minimalist text editor/notepad from package
APP_NAME=jNPad
APP_GUI_NAME="Java-based minimalist text editor/notepad."
APP_VERSION=0.4
APP_EXT=tgz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.jar "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}-${APP_VERSION}.jar "\$1"
Icon=/opt/${APP_NAME,,}/icons/icon-jnpad48.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Accessories;
Keywords=Text Editor;Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Robopages PHP-based, no-database CMS with XML configuration from package
APP_NAME=Robopages
APP_GUI_NAME="PHP-based, no-database CMS  with XML configuration."
APP_VERSION=Aug_20_2018
APP_EXT=zip
FILE_NAME=${APP_NAME}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd ${WWW_HOME}/${APP_NAME,,}
PATH=${WWW_HOME}/${APP_NAME,,}:\$PATH; export PATH
xdg-open http://localhost/${APP_NAME,,}/index.php
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=${WWW_HOME}/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;
Keywords=CMS;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Capa Chess Java-based chess program from package
APP_NAME="Capa chess"
APP_GUI_NAME="Java-based chess program."
APP_VERSION=1.0.3
APP_EXT=jar
FILE_NAME=${APP_NAME// /%20}-${APP_VERSION}-installer
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/capa/${FILE_NAME}.${APP_EXT}
sudo java -jar /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Dos9 cross-platform command prompt from source
APP_NAME=Dos9
APP_GUI_NAME="Cross-platform command prompt."
APP_VERSION=218.3
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make config && make all bin
sudo mkdir -p /usr/local/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/bin/* /usr/local/${APP_NAME,,}
sudo ln -f -s /usr/local/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
sudo rm -rf /tmp/*${APP_NAME,,}*

# Install CiteSpace scientific literature visual exploration tool from package
APP_NAME=CiteSpace
APP_GUI_NAME="Scientific literature visual exploration tool."
APP_VERSION=5.3.R5.10.23.2018
APP_EXT=7z
FILE_NAME=${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -Dfile.encoding=UTF-8 -Duser.country=US -Duser.language=en -Xms1g -Xmx4g -Xss5m -jar CiteSpaceV.jar
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
Exec=java -Dfile.encoding=UTF-8 -Duser.country=US -Duser.language=en -Xms1g -Xmx4g -Xss5m -jar CiteSpaceV.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Science;Other
Keywords=Visualization;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install GitGet Java-based tool to download a portion of Git repository from package
APP_NAME=GitGet
APP_GUI_NAME="Java-based tool to download a portion of Git repository."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} "\$1"
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Photo Manager Java-based GUI image organizer from Debian package
APP_NAME=Photo-Manager
APP_GUI_NAME="Java-based GUI image organizer."
APP_VERSION=1.2.4-0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/photo-man/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install SQLAdmin Java/JDBC-based database management tool from package
APP_NAME=SQLAdmin
APP_GUI_NAME="Java/JDBC-based database management tool."
APP_VERSION=2.6
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}-all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/sql-admin/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar "\$1"
Icon=/opt/${APP_NAME,,}/src/gpl/fredy/images/database.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Accessories;
Keywords=Database;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install FreeJ2ME J2ME emulator for desktop OSes from source
APP_NAME=FreeJ2ME
APP_GUI_NAME="J2ME emulator for desktop OSes."
APP_VERSION=2018-09-07
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y ant
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}
ant build.xml
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}/build/* /opt/${APP_NAME,,}
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,}/resources/org/recompile/icon.png /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar "\$1"
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar "\$1"
Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Games;Emulator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SQLite Editor Compiler from AppImage
APP_NAME=SQLite-Editor-Compiler
APP_GUI_NAME="SQLite Editor Compiler."
APP_VERSION=1.0.1
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i386
fi
FILE_NAME=${APP_NAME}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/sqliteeditorcompiler/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Database;SQLite;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Me and My Shadow SDL2 puzzle arcade game from source
APP_NAME=MeandMyShadow
APP_GUI_NAME="SDL2 puzzle arcade game."
APP_VERSION=0.5-rc
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-src
sudo apt-get install -y libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libsdl2-mixer-dev libcurl4-gnutls-dev liblua5.3-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${FILE_NAME//-src/}
mkdir -p build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Todoyu web-based (PHP/MySQL) project and task management tool from package
APP_NAME=Todoyu
APP_GUI_NAME="Web-based (PHP/MySQL) project and task management tool."
APP_VERSION=3.0.1
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://sourceforge.net/projects/todoyu-php7-x/files/${APP_VERSION}/Bugfixes%20Finalized.${APP_EXT}/download
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/*${APP_NAME}*/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Task Management;Project Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install MicroTerm wxWidgets/GTK-based serial port terminal from source
APP_NAME=MicroTerm
APP_GUI_NAME="wxWidgets/GTK-based serial port terminal."
APP_VERSION=0.97
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libvte-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/*${APP_NAME,,}*
./configure && make && sudo make install
sudo mv res/${APP_NAME,,}.png /usr/local/share/icons
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Networking;Development;Programming;
Keywords=TTY;Terminal;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SystemArchitect Qt-based GUI data modeling tool from package
APP_NAME=SystemArchitect
APP_GUI_NAME="Qt-based GUI data modeling tool."
APP_VERSION=4.0.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}-linux-x86-64bit
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
LD_LIBRARY_PATH=/opt/${APP_NAME,,}:\$LD_LIBRARY_PATH; export LD_LIBRARY_PATH
/opt/${APP_NAME,,}/${APP_NAME}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=opt/${APP_NAME,,}
Exec=LD_LIBRARY_PATH=/opt/${APP_NAME,,}:\$LD_LIBRARY_PATH; /opt/${APP_NAME,,}/${APP_NAME}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;Modeling;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Joplin cross-platform notepad and "To Do" list tool from AppImage
APP_NAME=Joplin
APP_GUI_NAME="Cross-platform notepad and \"To Do\" list tool."
APP_VERSION=1.0.107
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-${APP_VERSION}-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/laurent22/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=ToDo;Productivity;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Markdown Explorer Electron-based markdown viewer/editor from package
APP_NAME=Markdown-Explorer
APP_GUI_NAME="Markdown Explorer Electron-based markdown viewer/editor."
APP_VERSION=0.1.1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
FILE_NAME=${APP_NAME//-/}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/jersou/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
LD_LIBRARY_PATH=/opt/${APP_NAME,,}:\$LD_LIBRARY_PATH; export LD_LIBRARY_PATH
/opt/${APP_NAME,,}/${APP_NAME//-/}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=opt/${APP_NAME,,}
Exec=LD_LIBRARY_PATH=/opt/${APP_NAME,,}:\$LD_LIBRARY_PATH; /opt/${APP_NAME,,}/${APP_NAME//-/}
Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=Markdown;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install MagicCube 3-D Rubik's cube visualization from Debian package
APP_NAME=MagicCube3
APP_GUI_NAME="3-D Rubik's cube visualization."
APP_VERSION=1.3
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_amd64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install D-rkstar Java-based galactic civilization game from source
APP_NAME=DrkStar
APP_GUI_NAME="Java-based galactic civilization game."
APP_VERSION=0.7.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -cp derbyclient.jar -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
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
Exec=java -cp derbyclient.jar -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Adventure;Space;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install xonsh alternative, cross-platform Python-based console shell from package
APP_NAME=xonsh
APP_GUI_NAME="Alternative, cross-platform Python-based console shell."
APP_VERSION=0.7.8
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/${APP_VERSION}/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo python3 ./setup.py install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Rukovoditel web-based (PHP/MySQL) project management tool from package
APP_NAME=Rukovoditel
APP_GUI_NAME="Web-based (PHP/MySQL) project management tool."
APP_VERSION=2.5.1
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Task Management;Project Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Master Password cross-platform Java GUI password management tool from package
APP_NAME=MasterPassword
APP_GUI_NAME="Cross-platform Java GUI password management tool."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-gui
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://masterpassword.app/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Internet;System;
Keywords=Password;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Digital Logic Simulator (DiLoSim) cross-platform Java GUI logic simulator from package
APP_NAME=Digital-Logic-Simulator
APP_GUI_NAME="Cross-platform Java GUI logic simulator."
APP_VERSION=1.0.0
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Engineering;Electronics;
Keywords=Logic;Electronics;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install JWordProcessor cross-platform Java Swing RTF editor from package
APP_NAME=JWordProcessor
APP_GUI_NAME="Cross-platform Java Swing RTF editor."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Editor;RTF;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Password Keeper-Generator (PKG) Java-based password generator and manager from package
APP_NAME=PKG
APP_GUI_NAME="Java-based password generator and manager."
APP_VERSION=18-09-18
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_bin
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/j-${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Accessories;
Keywords=Password;Generator;Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Ninja IDE Qt-based Python editor/IDE from Debian package
APP_NAME=Ninja-IDE
APP_GUI_NAME="Qt-based Python editor/IDE."
APP_VERSION=2.3%2Br597~saucy1_all
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://www.dropbox.com/s/qwxvndlrtzdstpx/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install MP3Gain MP3 file volume normalizer from source
APP_NAME=MP3Gain
APP_GUI_NAME="MP3 file volume normalizer."
APP_VERSION=1.6.2
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION//./_}-src
sudo apt-get install -y libmpg123-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make && sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Hashrat file hash tool with support for many hash algorithms from source
APP_NAME=Hashrat
APP_GUI_NAME="File hash tool with support for many hash algorithms."
APP_VERSION=1.9
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/ColumPaget/${APP_NAME}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/libUseful-3
./configure && make && sudo make install
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Videomass2 GUI front-end for FFmpeg from Debian package
APP_NAME=Videomass2
APP_GUI_NAME="GUI front-end for FFmpeg."
APP_VERSION=1.2.0-1
APP_EXT=deb
FILE_NAME=python-${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Chronometer stopwatch and countdown timer from package
APP_NAME=Chrono
APP_GUI_NAME="Stopwatch and countdown timer."
APP_VERSION=1.1.1
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-gui_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-gui/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,}-gui/${APP_NAME,,}-linux64 /usr/local/bin/${APP_NAME,,}
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,}-gui/source/main.ico /usr/share/icons/${APP_NAME,,}.ico
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/share/icons/${APP_NAME,,}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Stopwatch;Timer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install GNU Spice GUI wxWidgets GUI for NG-Spice and GNU-Cap electronic circuit emulation tools from source
APP_NAME=gSpiceUI
APP_GUI_NAME="wxWidgets GUI for NG-Spice and GNU-Cap electronic circuit emulation tools."
APP_VERSION=1.1.00
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}
sudo apt-get install libpangox-1.0-dev libwxgtk3.0-dev gwave
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/${APP_NAME,,}/icons/${APP_NAME,,}-32x32.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Engineering;Electronics;Programming;Development;
Keywords=Electronics;Spice;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Violet UML Editor Java-based UML modeling tool from package
APP_NAME=VioletUMLEditor
APP_GUI_NAME="Java-based UML modeling tool."
APP_VERSION=3.0.0
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/violet/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=UML;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SueIDE minimalist Java IDE from package
APP_NAME=SueIDE
APP_GUI_NAME="Minimalist Java IDE."
APP_VERSION=1.01
APP_EXT=zip
FILE_NAME=${APP_NAME}-all-in-one-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/suei/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/bin/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
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
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=IDE;Java;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install DocSearcher cross-platform indexed search tool for documents from package
APP_NAME=DocSearcher
APP_GUI_NAME="Cross-platform indexed search tool for documents."
APP_VERSION=3.94.0-rc1
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME//er/}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME//er/}.jar
Icon=/opt/${APP_NAME,,}/icons/ds.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Search;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install TurboVNC remote desktop tool from Debian package
APP_NAME=TurboVNC
APP_GUI_NAME="remote desktop tool."
APP_VERSION=2.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install fiets cross-platform, Java-based opinionated RSS feed reader and filter from package
APP_NAME=fiets
APP_GUI_NAME="Cross-platform, Java-based opinionated RSS feed reader and filter."
APP_VERSION=0.9
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/ondy/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=RSS;News;Aggregator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install FreshRSS web-based (PHP/MySQL), self-hosted RSS news aggregator from package
APP_NAME=FreshRSS
APP_GUI_NAME="Web-based (PHP/MySQL), self-hosted RSS news aggregator."
APP_VERSION=1.11.2
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Task Management;Project Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install official OpenJDK 11 along with OpenJDK from repositories with alternatives
APP_NAME=OpenJDK
APP_GUI_NAME="Official OpenJDK 11."
APP_VERSION=11+28
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}_linux-x64_bin
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download.java.net/java/GA/jdk11/28/GPL/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/* /usr/lib/jvm
sudo sh -c 'for bin in /usr/lib/jvm/jdk-11/bin/*; do update-alternatives --install /usr/bin/$(basename $bin) $(basename $bin) $bin 100; done'
sudo sh -c 'for bin in /usr/lib/jvm/jdk-11/bin/*; do update-alternatives --set $(basename $bin) $bin; done'
echo "To change JDK version, run 'sudo update-alternatives --config java'."
cd $HOME
sudo rm -rf /tmp/${FILE_NAME}*

# Install 2048 Java/JavaFX-based puzzle game from package
APP_NAME=Game2048
APP_GUI_NAME="Java/JavaFX-based puzzle game."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}bmsr/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment
Keywords=Puzzle;2048;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Logisim Evolution Java-based digital logic designer and simulator from package
APP_NAME=Logisim-Evolution
APP_GUI_NAME="Java-based digital logic designer and simulator."
APP_VERSION=2.14.6
APP_EXT=jar
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/reds-heig/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Electronics;
Keywords=Logic;Simulator;Electronics;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Jet File Transfer Java/JavaFX-based LAN file transfer tool from package
APP_NAME=Jet-File-Transfer
APP_GUI_NAME="Java/JavaFX-based LAN file transfer tool."
APP_VERSION=1.0
APP_EXT=rar
FILE_NAME=JetF_leTransferAll
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/Linux/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME//-}-v${APP_VERSION}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME//-}-v${APP_VERSION}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Network;
Keywords=LAN;Transfer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install JPasswords Java-based password manager from package
APP_NAME=JPWS
APP_GUI_NAME="Java-based password manager."
APP_VERSION=1.2.0
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-${APP_VERSION//./-}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Internet;
Keywords=Password;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Syncped wxWidgets-based text editor from Github repository
APP_NAME=Syncped
APP_GUI_NAME="wxWidgets-based text editor."
APP_VERSION=N/A
APP_EXT=N/A
sudo apt-get install -y cmake
cd /tmp
git clone --recursive https://github.com/antonvw/wxExtension.git
cd wxExtension
mkdir build && cd build   
cmake .. && make && sudo make install

# Install Namely Java/JavaFX-based multi-file renamer from package
APP_NAME=Namely
APP_GUI_NAME="Java/JavaFX-based multi-file renamer."
APP_VERSION=1.0
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://download1495.mediafire.com/dp60t6hu96lg/8dpfz3x0b4ea2nd/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Renamer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Deer React/Electron-based note-taking application from Debian package
APP_NAME=Deer
APP_GUI_NAME="React/Electron-based note-taking application."
APP_VERSION=0.1.0
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/abahmed/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Sudoku-Tk Python 3 Tkinter-based Sudoku puzzle generator and solver from package
APP_NAME=Sudoku-Tk
APP_GUI_NAME="Python 3 Tkinter-based Sudoku puzzle generator and solver."
APP_VERSION=1.2.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y python3-tk python3-pil python3-numpy tcl8.6 tk8.6
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-j4321/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/*${APP_NAME}*/
sudo python3 ./setup.py install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Google-Drive-Electron cross-platform, Electron-based desktop tool for Google Drive from package
APP_NAME=Google-Drive-Electron
APP_GUI_NAME="Cross-platform, Electron-based desktop tool for Google Drive."
APP_VERSION=v.funky-duck/0.0.2
APP_EXT=zip
FILE_NAME=${APP_NAME//-/.}-linux-x64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/alexkim205/Google-Drive-Electron/releases/download/${APP_VERSION////%2F}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv "/tmp/${FILE_NAME}/${FILE_NAME//./\ }"/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
"/opt/${APP_NAME,,}/${APP_NAME//-/\ }"
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
Exec="/opt/${APP_NAME,,}/${APP_NAME//-/\ }"
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Accessories;System;
Keywords=Google;Storage;Drive;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Leibnitz 3D graphing calculator from package
APP_NAME=Leibnitz
APP_GUI_NAME="3D graphing calculator."
APP_VERSION=2.1.0
APP_EXT=tgz
FILE_NAME=${APP_NAME}_${APP_VERSION}_tar_RHFC27
sudo apt-get install -y libjpeg62 
sudo ln -s /lib/x86_64-linux-gnu/libpcre.so.3 /lib/x86_64-linux-gnu/libpcre.so.1
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}-${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/opt/${APP_NAME,,}/desktop/${APP_NAME,,}.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Accessories;
Keywords=Calculator;Graphing;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install System G minimalist GUI file manager from package
APP_NAME=System-G
APP_GUI_NAME="Minimalist GUI file manager."
APP_VERSION=2.7.0
APP_EXT=tgz
FILE_NAME=${APP_NAME//-/_}_${APP_VERSION}_tar_RHFC27
sudo apt-get install -y libjpeg62 
sudo ln -s /lib/x86_64-linux-gnu/libpcre.so.3 /lib/x86_64-linux-gnu/libpcre.so.1
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/nps-systemg/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME//-/_}-${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/systemg
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
Exec=/opt/${APP_NAME,,}/systemg
Icon=/opt/${APP_NAME,,}/desktop/systemg.xpm
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Docker from official repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-cache policy docker-ce
sudo apt-get install -y docker-ce
sudo systemctl status docker
sudo usermod -aG docker ${USER}  # Add user account to 'docker' group to run commands without sudo.
su ${USER}
id -nG  # Confirm user account added to 'docker' group.
docker run hello-world  # Confirm Docker installation.

# Install Dark Chess (Banqi) Python-based chess variant game from package
APP_NAME=DarkChess
APP_GUI_NAME="Python-based chess variant game."
APP_VERSION=086
APP_EXT=tar.gz
FILE_NAME=p_${APP_NAME,,}_${APP_VERSION}
sudo pip3 install pygame
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
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
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
Icon=/opt/${APP_NAME,,}/Image/${APP_NAME,,}_default.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Chess;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Polar Bookshelf personal document management/ebook reader tool from Debian package
APP_NAME=Polar-Bookshelf
APP_GUI_NAME="Personal document management/ebook reader tool."
APP_VERSION=1.0.9
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/burtonator/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install php4dvd PHP/MySQL personal movie management tool with IMDB integration from package
APP_NAME=php4dvd
APP_GUI_NAME="PHP/MySQL personal movie management tool with IMDB integration."
APP_VERSION=3.8.0
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/jreklund/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;
Keywords=Movies;IMDB;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install GraphQL Playground Electron-based IDE/client for GraphQL development and testing from Debian package
APP_NAME=GraphQL-Playground
APP_GUI_NAME="Electron-based IDE/client for GraphQL development and testing."
APP_VERSION=1.8.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-electron_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/prisma/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install glparchis OpenGL-based Parchis (Parcheesi) game from package
APP_NAME=glparchis
APP_GUI_NAME="OpenGL-based Parchis (Parcheesi) game."
APP_VERSION=20181020
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-linux-${APP_VERSION}.x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/opt/${APP_NAME,,}/ficharoja.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=Parcheesi;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install imgp image resizer and rotator from Debian package
APP_NAME=imgp
APP_GUI_NAME="Image resizer and rotator."
APP_VERSION=2.6-1
APP_EXT=deb
source /etc/lsb-release
# If Ubuntu version is above 16.04 (Xenial), then we use 16.04.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(xe|ya|ze|ar)$ ]]; then
	DISTRIB_RELEASE=16.04
else 
    DISTRIB_RELEASE=18.04
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_ubuntu${DISTRIB_RELEASE}.${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install JFootball Java 2D football (soccer) game from package
APP_NAME=JFootball
APP_GUI_NAME="Java 2D football (soccer) game."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -Xms128m -Xmx1024m -classpath ${FILE_NAME}.${APP_EXT} com.loading.GameLoader
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
Exec=java -Xms128m -Xmx1024m -classpath ${FILE_NAME}.${APP_EXT} com.loading.GameLoader
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Football;Soccer;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install nuTetris minimalist Java Tetris puzzle game from package
APP_NAME=nuTetris
APP_GUI_NAME="Minimalist Java Tetris puzzle game."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
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
Exec=java -jar ${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Tetris;Puzzle;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Autoplot Java-based automatic data visualization and management tool from package
APP_NAME=Autoplot
APP_GUI_NAME="Java-based automatic data visualization and management tool."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
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
Exec=java -jar ${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Data;Visualization;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Hallo Northern Sky (HNSky) planetarium program from Debian package
APP_NAME=HNSky
APP_GUI_NAME="Hallo Northern Sky (HNSky) planetarium program."
APP_VERSION=N/A
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Tor Browser self-contained secure web browser from package
APP_NAME=Tor-Browser
APP_GUI_NAME="Self-contained secure web browser."
APP_VERSION=8.0.3
APP_EXT=tar.xz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
FILE_NAME=${APP_NAME,,}-${ARCH_TYPE}-${APP_VERSION}_${LANGUAGE//_/-}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}.mirror/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}_${LANGUAGE//_/-}/Browser/* /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/start-${APP_NAME,,}
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
Exec=/opt/${APP_NAME,,}/start-${APP_NAME,,}
Icon=web-browser
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Tor;Web;Browser;Privacy;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Kilua small, extensible, Lua-powered text editor from source
APP_NAME=Kilua
APP_GUI_NAME="Small, extensible, Lua-powered text editor."
APP_VERSION=N/A
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-master
sudo apt-get install -y libncursesw5-dev liblua5.2-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/skx/${APP_NAME,,}/archive/master.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=true
Categories=Programming;Development;
Keywords=Editor;Lua;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install AWGG (Advanced Wget GUI) Qt front-end for wget, aria2, youtube-dl, curl, etc. from package
APP_NAME=AWGG
APP_GUI_NAME="Qt front-end for wget, aria2, youtube-dl, curl, etc.."
APP_VERSION=N/A
APP_EXT=tar.xz
FILE_NAME=${APP_NAME}_x86_64_QT5
sudo apt-get install -y libqt5pas1
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=Wget;Curl;P2P;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install EmACT minimalist terminal Emacs clone from source
APP_NAME=EmACT
APP_GUI_NAME="Minimalist terminal Emacs clone."
APP_VERSION=2.58.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libtinfo-dev libncurses5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install ShareBlogs minimalist PHP/MySQL-based blogging platform from package
APP_NAME=ShareBlogs
APP_GUI_NAME="Minimalist PHP/MySQL-based blogging platform."
APP_VERSION=1.3
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/blogsinphp/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
#sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;
Keywords=Movies;IMDB;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}/install.php
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Pennywise Electron-based utility to open any application or web site in floating, stay-on-top window from Debian package
APP_NAME=Pennywise
APP_GUI_NAME="Electron-based utility to open any application or web site in floating, stay-on-top window."
APP_VERSION=0.1.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/kamranahmedse/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install HTML Notepad minimalist WYSIWG HTML editor from package
APP_NAME=HTML-Notepad
APP_GUI_NAME="Minimalist WYSIWG HTML editor."
APP_VERSION=N/A
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-dist
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://${APP_NAME,,}.com/dist/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=HTML;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install GXemul full-system computer emulator that emulates processors (ARM, MIPS, M88K, PowerPC, and SuperH) and peripherals from source
APP_NAME=GXemul
APP_GUI_NAME="Full-system computer emulator that emulates processors (ARM, MIPS, M88K, PowerPC, and SuperH) and peripherals."
APP_VERSION=0.6.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libtinfo-dev libncurses5-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Code Notes simple code snippet/Github Gist manager built with Electron and Vue.JS from AppImage
APP_NAME=Code-Notes
APP_GUI_NAME="Simple code snippet/Github Gist manager built with Electron and Vue.JS."
APP_VERSION=1.2.1
APP_EXT=AppImage
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/lauthieb//${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Snippets;Gist;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Batch Audio Converter command-line audio file converter from package
APP_NAME=BAC
APP_GUI_NAME="Command-line audio file converter."
APP_VERSION=N/A
APP_EXT=sh
FILE_NAME=${APP_NAME,,}
sudo apt-get install -y ffmpeg
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/batchaudiocvt/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /usr/local/bin
sudo chmod a+x /usr/local/bin/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /usr/local/bin/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ChurchInfo web-based (PHP/MySQL) church management system from package
APP_NAME=ChurchInfo
APP_GUI_NAME="Web-based (PHP/MySQL) church management system."
APP_VERSION=1.3.0
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
#sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
#sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} < ${WWW_HOME}/${APP_NAME,,}/SQL/Install.sql
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}/index.html
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=Church;Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}/index.html
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Rachota Java-based personal time-tracking tool from package
APP_NAME=Rachota
APP_GUI_NAME="Java-based personal time-tracking tool."
APP_VERSION=2.4
APP_EXT=jar
FILE_NAME=${APP_NAME,,}_${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
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
Exec=java -jar ${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;
Keywords=Time;Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install JumpFM Electron-based dual-pane file manager from AppImage
APP_NAME=JumpFM
APP_GUI_NAME="Electron-based dual-pane file manager."
APP_VERSION=1.0.5
APP_EXT=AppImage
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=File;Manager;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install ProcDump Linux version of Sysinternals ProcDump tool Debian package
APP_NAME=ProcDump
APP_GUI_NAME="Linux version of Sysinternals ProcDump tool."
APP_VERSION=1.0.1
APP_EXT=deb
source /etc/lsb-release
# If Ubuntu version is above 16.04 (Xenial), then we use 16.04.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(xe|ya|ze|ar|bi|co)$ ]]; then
	DISTRIB_CODENAME=xenial
else 
    DISTRIB_CODENAME=trusty
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://packages.microsoft.com/repos/microsoft-ubuntu-${DISTRIB_CODENAME}-prod/pool/main/p/procdump/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install SQL Workbench Java-based GUI and console database client from package
APP_NAME=SQLWorkbench
APP_GUI_NAME="Java-based GUI and console database client."
APP_VERSION=124
APP_EXT=zip
FILE_NAME=${APP_NAME//SQL/}-Build${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://www.sql-workbench.eu/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
#sudo chmod -R a+w /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/sqlwbconsole.sh /opt/${APP_NAME,,}/${APP_NAME,,}.sh
sudo ln -s -f /opt/${APP_NAME,,}/sqlwbconsole.sh /usr/local/bin/sqlwbconsole
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.sh
Icon=/opt/${APP_NAME,,}/workbench32.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=SQL;Database;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install Archiver Golang-based multi-format archiver/extractor from package
APP_NAME=Archiver
APP_GUI_NAME="Golang-based multi-format archiver/extractor."
APP_VERSION=3.0.0
APP_EXT=N/A
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=amd64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=386
fi
FILE_NAME=arc_linux_${ARCH_TYPE}
curl -o /tmp/arc -J -L https://github.com/mholt/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}
sudo mv /tmp/arc /usr/local/bin
sudo chmod a+x /usr/local/bin/arc
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Conky-Easy customized Conky system monitor configuration from package
APP_NAME=Conky-Easy
APP_GUI_NAME="Customized Conky system monitor configuration."
APP_VERSION=1.0.9
APP_EXT=7z
FILE_NAME=${APP_NAME}-${APP_VERSION}
sudo apt-get install -y conky-all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://dl.opendesktop.org/api/files/download/id/1541941778/s/e6e6b0063ee171a6a3084f47badceb928031b4b7dab9020ff0ba591f207a2d43678ebe4d5662b6ac0486a4ba4044e908b7c56ab75cf136dc94a7fe9e0d167fb5/t/1542063859/u//${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}/conky.png /usr/share/icons # For start notification
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}/'zekton rg.ttf' /usr/share/fonts  # For clock font
cp -R /tmp/${FILE_NAME}/${APP_NAME}/.conkybasic_c110 $HOME
cp -R /tmp/${FILE_NAME}/${APP_NAME}/.lua $HOME
cp -R /tmp/${FILE_NAME}/${APP_NAME}/.icons $HOME
sed -i 's@ .conkybasic_c110@ $HOME/.conkybasic_c110@g' /tmp/${FILE_NAME}/${APP_NAME}/startconky.sh
sudo cp /tmp/${FILE_NAME}/${APP_NAME}/startconky.sh /usr/local/bin
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install MineBlog minimalist blogging platform built with BunnyPHP framework from package
APP_NAME=MineBlog
APP_GUI_NAME="Minimalist blogging platform built with BunnyPHP framework."
APP_VERSION=1.0beta
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/*${APP_NAME}*/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} < ${WWW_HOME}/${APP_NAME,,}/SQL/Install.sql
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=Blogging;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}/install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install sysget universal package manager for Linux from repository
APP_NAME=sysget
APP_GUI_NAME="Universal package manager for Linux."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=N/A
sudo wget -qO - https://apt.emilengler.com/signkey.asc | sudo apt-key add
echo "deb [arch=all] https://apt.emilengler.com/ stable main" | sudo tee /etc/apt/sources.list.d/emilengler.list
sudo apt update 
sudo apt install -y sysget
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Qomp Quick (Qt) Online Music Player from Debian package
APP_NAME=Qomp
APP_GUI_NAME="Quick (Qt) Online Music Player."
APP_VERSION=1.3.1
APP_EXT=deb
source /etc/lsb-release
# If Ubuntu version is above 16.04 (Xenial), then we use 16.04.
if [[ "${DISTRIB_CODENAME:0:2}" =~ ^(ar|bi|co)$ ]]; then
	DISTRIB_CODENAME=artful
else 
    DISTRIB_CODENAME=zesty
fi
FILE_NAME=${APP_NAME,,}_${APP_VERSION}-0ubuntu1~0ppa1~${DISTRIB_CODENAME}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://launchpad.net/~${APP_NAME,,}/+archive/ubuntu/ppa/+files/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Safe Clock multi-panel clock from package
APP_NAME=safe-clock
APP_GUI_NAME="Safe Clock multi-panel clock."
APP_VERSION=1.2.0
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME//-/_}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/source/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=Clock;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install JPhotoTagger Java-based GUI photo tag/metadata editor from package
APP_NAME=JPhotoTagger
APP_GUI_NAME="Java-based GUI photo tag/metadata editor."
APP_VERSION=0.42.6
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME} /opt
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME}
PATH=/opt/${APP_NAME}:/opt/${APP_NAME}/lib:\$PATH; export PATH
java -jar ${APP_NAME}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME}:/opt/${APP_NAME}/lib
Exec=java -jar ${APP_NAME}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;Accessories;Graphics;
Keywords=Photo;Tagger;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install ptop Python-based Linux task manager for shell from package
APP_NAME=ptop
APP_GUI_NAME="Python-based Linux task manager for shell."
APP_VERSION=1.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/darxtrix/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo pip3 install -r requirements.txt
sudo python3 setup.py install

# Install fre:ac audio converter and CD ripper from package
APP_NAME="fre:ac"
APP_GUI_NAME="Audio converter and CD ripper."
APP_VERSION=1.1-alpha-20181201
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux-x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux
fi
FILE_NAME=${APP_NAME//:/}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/bonkenc/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME//:/}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME//:/}
sudo ln -f -s /opt/${APP_NAME//:/}/${APP_NAME//:/} /usr/local/bin/${APP_NAME//:/}
sudo ln -f -s /opt/${APP_NAME//:/}/${APP_NAME//:/}cmd /usr/local/bin/${APP_NAME//:/}cmd
cat > /tmp/${APP_NAME//:/} << EOF
#! /bin/sh
cd /opt/${APP_NAME//:/}
LD_LIBRARY_PATH=/opt/${APP_NAME//:/}:${LD_LIBRARY_PATH}; export LD_LIBRARY_PATH
PATH=/opt/${APP_NAME//:/}:\$PATH; export PATH
/opt/${APP_NAME//:/}/${APP_NAME//:/}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME//:/} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME//:/}
cat > /tmp/${FILE_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME//:/}
Exec=/opt/${APP_NAME//:/}/${APP_NAME//:/}
Icon=/opt/${APP_NAME//:/}/icons/${APP_NAME//:/}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Audio;Multimedia;
Keywords=Audio;Converter;
EOF
sudo mv /tmp/${FILE_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Trilium Notes Electron-based hierarchical note taking application from package
APP_NAME=Trilium
APP_GUI_NAME="Electron-based hierarchical note taking application."
APP_VERSION=0.27.3
APP_EXT=7z
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
FILE_NAME=${APP_NAME,,}-linux-${ARCH_TYPE}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/zadam/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}-linux-${ARCH_TYPE}/* /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME

# Install JUL Designer RAD tool for JavaScript development from App Image
APP_NAME=JUL-Designer
APP_GUI_NAME="RAD tool for JavaScript development."
APP_VERSION=2.5.0
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=i386
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86_64
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s -f /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=JavaScript;Web;Development;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install E.R.A simple Java UML diagramming tool from package
APP_NAME=Era
APP_GUI_NAME="Simple Java UML diagramming tool."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/era-simple-uml/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
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
Exec=java -jar ${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=UML;Diagramming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Qubist GTK2 3-D 4x4x4 Tic-Tac-Toe puzzle game from package
APP_NAME=Qubist
APP_GUI_NAME="GTK2 3-D 4x4x4 Tic-Tac-Toe puzzle game."
APP_VERSION=0.6
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libgtk2.0-dev help2man
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/qubic/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
sudo ln -f -s /usr/local/games/${APP_NAME,,}-gtk2 /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/games
Exec=/usr/local/games/${APP_NAME,,}-gtk2
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Tic-Tac-Toe;Puzzle;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Direnv environment switcher for the shell from package
APP_NAME=Direnv
APP_GUI_NAME="Environment switcher for the shell."
APP_VERSION=2.18.2
APP_EXT=N/A
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=386
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=amd64
fi
FILE_NAME=${APP_NAME,,}.linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}
sudo mv /tmp/${FILE_NAME} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
sudo ln -f -s /usr/local/bin/${FILE_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install NextFractal Java-based fractal explorer from package
APP_NAME=NextFractal
APP_GUI_NAME="Java-based fractal explorer."
APP_VERSION=2.1.1
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_debian_x86_64_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME} /opt
sudo ln -s -f /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Math;Science;
Keywords=Fractal;Math
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install pcaprunner shell-based PCAP IP packet analyzer from source
APP_NAME=pcaprunner
APP_GUI_NAME="Shell-based PCAP IP packet analyzer."
APP_VERSION=0.8
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_v${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make
sudo mkdir /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${APP_NAME,,}
sudo ln -f -s /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME,,}_gui.py
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Networking;
Keywords=PCAP;Networking
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install Netsurf minimalist GTK web browser from source
APP_NAME=Netsurf
APP_GUI_NAME="Minimalist GTK web browser."
APP_VERSION=3.8
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-all-${APP_VERSION}
sudo apt-get install -y build-essential pkg-config gperf libcurl3-dev libpng-dev libjpeg-dev libgtk-3-dev librsvg2-dev libssl-dev bison flex
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://download.netsurf-browser.org/${APP_NAME,,}/releases/source-full/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/bin
Exec=/bin/netsurf-gtk
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=Web;Browser;GTK;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME,,}*

# Install RTextDoc Java-based editor for structured text, such as LaTeX from package
APP_NAME=RTextDoc
APP_GUI_NAME="Java-based editor for structured text, such as LaTeX."
APP_VERSION=2.3
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME,,}.sh
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
Exec=/opt/${APP_NAME,,}/${APP_NAME,,}.sh
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=Editor;LaTeX;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Jcow social networking tool
APP_NAME=Jcow
APP_VERSION=12
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}.ce.${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/install.php &
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php &
Icon=${WWW_HOME}/${APP_NAME,,}/themes/default/ico.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=Social;Media;Networking;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/

# Install Custom Linux Creator fork of Remastersys for creating Live CD from Ubuntu 17.04 and later installation from Debian package
APP_NAME=CustomLinuxCreator
APP_GUI_NAME="Fork of Remastersys for creating Live CD from Ubuntu 17.04 and later installation."
APP_VERSION=1.2
APP_EXT=deb
FILE_NAME=${APP_NAME}${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/custom-linux-creator/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Tag Inspector GUI MP3 tag viewer/editor from package
APP_NAME=TagInspector
APP_GUI_NAME="GUI MP3 tag viewer/editor."
APP_VERSION=N/A
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=32bit
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=64bit
fi
FILE_NAME=${APP_NAME,,}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Multimedia;
Keywords=MP3;Tags;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install FreeDoko cross-platform version of Doppelkopf German card game from package
APP_NAME=FreeDoko
APP_GUI_NAME="Cross-platform version of Doppelkopf German card game."
APP_VERSION=0.7.20
APP_EXT=zip
FILE_NAME=${APP_NAME}_${APP_VERSION}.Linux
sudo apt-get install -y libalut0
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/free-doko/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}_${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Icon=/opt/${APP_NAME,,}/icon.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;Other;
Keywords=Cards;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Streamtuner Python-based Internet radio directory browser from Debian package
APP_NAME=Streamtuner2
APP_GUI_NAME="Python-based Internet radio directory browser."
APP_VERSION=2.2.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install go-t cross-platform command line Twitter client from package
APP_NAME="go-t"
APP_GUI_NAME="Cross-platform command line Twitter client."
APP_VERSION=0.1
APP_EXT=N/A
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux-386
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux-amd64
fi
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME} -J -L https://github.com/cbrgm/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}
sudo mv /tmp/${FILE_NAME} /usr/local/bin/${APP_NAME,,}
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Hexyl Rust-based hex viewer for the terminal from Debian package
APP_NAME=Hexyl
APP_GUI_NAME="Rust-based hex viewer for the terminal."
APP_VERSION=0.5.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_amd64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/sharkdp/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install StarCalendar Python-based simple calendar tool from package
# Note: Install shell script creates Debian package used for installation.
APP_NAME=StarCal
APP_GUI_NAME="Python-based simple calendar tool."
APP_VERSION=3.0.7
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo /tmp/${FILE_NAME}/install-ubuntu
cd $HOME
sudo rm -rf /tmp/${FILE_NAME}*

# Install ImLab cross-platform scientific image processing tool from package
APP_NAME=ImLab
APP_GUI_NAME="Cross-platform scientific image processing tool."
APP_VERSION=3.1
APP_EXT=tar.gz
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(vi|wi)$ ]]; then
	DISTRIB_RELEASE=15
	sudo apt-get install -y libpng12* libglu1-mesa
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(tr|ut)$ ]]; then
	DISTRIB_RELEASE=14
	sudo apt-get install -y libpng12* libglu1-mesa
else
	DISTRIB_RELEASE=16
	sudo apt-get install -y libglu1-mesa
	curl -o /tmp/libpng12-0.deb -J -L http://security.ubuntu.com/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_amd64.deb
	sudo gdebi -n /tmp/libpng12-0.deb
fi
FILE_NAME=${APP_NAME,,}-${APP_VERSION}_Ubuntu${DISTRIB_RELEASE}_x64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp -R /tmp/${FILE_NAME}/* /usr/local/bin
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/bin/${APP_NAME}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;System;
Keywords=Image;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${FILE_NAME}*

# Install Linux Reminders GUI periodic and one-time reminder tool from Debian package
APP_NAME=Linux-Reminders
APP_GUI_NAME="GUI periodic and one-time reminder tool."
APP_VERSION=2.3.1
APP_EXT=deb
FILE_NAME=reminders_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Vido Python GUI video/audio downloader frontend for youtube-dl from Debian package
APP_NAME=Vido
APP_GUI_NAME="Python GUI video/audio downloader frontend for youtube-dl."
APP_VERSION=1.0.5
APP_EXT=deb
FILE_NAME=${APP_NAME,,}%20${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Grip GTK-based CD player, CD ripper, and MP3 encoder from source
APP_NAME=Grip
APP_GUI_NAME="GTK-based CD player, CD ripper, and MP3 encoder."
APP_VERSION=3.10.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libssl-dev libssh2-1-dev libvte-dev libcurl4-openssl-dev libgnomeui-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install TkCVS cross-platform Tcl/Tk client for CVS, RCS, SVN, and Git
APP_NAME=TkCVS
APP_GUI_NAME="Cross-platform Tcl/Tk client for CVS, RCS, SVN, and Git."
APP_VERSION=9.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}_${APP_VERSION}
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls  # Install required packages
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
sudo wish ./doinstall.tcl /usr/local
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/lib/${APP_NAME,,}/bitmaps/ticklefish48.gif
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Git;SVN;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Headset cross-platform Electron-based Youtube/Reddit desktop music player from Debian package
# https://www.linuxlinks.com/headset-youtube-reddit-desktop-music-player/
APP_NAME=Headset
APP_GUI_NAME="Cross-platform Electron-based Youtube/Reddit desktop music player."
APP_VERSION=2.1.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
sudo apt-get install -y libgconf2-4
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/headsetapp/headset-electron/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install orng Java Markdown-based journal editor from package
APP_NAME=orng
APP_GUI_NAME="Java Markdown-based journal editor."
APP_VERSION=1.1.16
APP_EXT=zip
FILE_NAME=${APP_NAME,,}j_${APP_VERSION}_gnu_linux_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}

# Install Kitchen Garden Aid Java-based garden/small farm planning/layout tool from package
APP_NAME="Kitchen Garden Aid"
APP_GUI_NAME="Java-based garden/small farm planning/layout tool."
APP_VERSION=1.8.2
APP_EXT=jar
FILE_NAME=${APP_NAME// /}.${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/kitchengarden/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME// /}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME// /}
cat > /tmp/${APP_NAME// /} << EOF
#! /bin/sh
cd /opt/${APP_NAME// /}
PATH=/opt/${APP_NAME// /}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
cd $HOME
EOF
sudo mv /tmp/${APP_NAME// /} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME// /}
cat > /tmp/${APP_NAME// /}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME// /}
Exec=java -jar ${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;Other;
Keywords=Garden;
EOF
sudo mv /tmp/${APP_NAME// /}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME// /}*

# Install Nuclear cross-platform Electron-based desktop music player focused on streaming from free sources from Debian package
APP_NAME=Nuclear 
APP_GUI_NAME="Cross-platform Electron-based desktop music player focused on streaming from free sources."
APP_VERSION=0.4.3
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/nukeop/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install SQLeo Java-based visual SQL query builder tool from package
APP_NAME=SQLeoVQB
APP_GUI_NAME="Java-based visual SQL query builder tool."
APP_VERSION=2017.09.rc1
APP_EXT=zip
FILE_NAME=${APP_NAME}.${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/sqleo/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}*/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -Dfile.encoding=UTF-8 -jar ${APP_NAME}.jar
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
Exec=java -Dfile.encoding=UTF-8 -jar ${APP_NAME}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Database;SQL;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install cfiles ncurses file manager with Vim keybindings from source
APP_NAME=cfiles
APP_GUI_NAME="Ncurses file manager with Vim keybindings."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=N/A
sudo apt-get install -y libncurses5-dev cmake 
cd /tmp
git clone https://github.com/mananapr/${APP_NAME,,}
cd /tmp/${APP_NAME,,}
mkdir build && cd build
cmake .. && make
sudo mv ${APP_NAME,,} /usr/local/bin
sudo rm -rf /tmp/${APP_NAME,,}*

# Install BitchX console IRC client from source
APP_NAME=BitchX
APP_VERSION=N/A
APP_EXT=N/A
git clone https://git.code.sf.net/p/${APP_NAME,,}/git /tmp/${APP_NAME,,}
cd /tmp/${APP_NAME,,}
./configure && make && sudo make install
sudo ln -s /usr/bin/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install OmniDB Django/Python-based web database administration tool from Debian package
APP_NAME=OmniDB 
APP_GUI_NAME="Django/Python-based web database administration tool."
APP_VERSION=2.13.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-app_${APP_VERSION}-debian-${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://omnidb.org/dist/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Arena UCI and Winboard-compatible chess GUI from package
APP_NAME=Arena
APP_GUI_NAME="UCI and Winboard-compatible chess GUI."
APP_VERSION=1.1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=64bit
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=32bit
fi
FILE_NAME=${APP_NAME,,}linux_${ARCH_TYPE}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://www.playwitharena.de/downloads/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/Arena_x86_64_linux
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
Exec=/opt/${APP_NAME,,}/Arena_x86_64_linux
Icon=/opt/${APP_NAME,,}/${APP_NAME}.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Chess;UCI;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Configure Mono Project build environment for C#/.NET
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(bi|co)$ ]]; then
	VERSION_NUMBER=18.04
	VERSION_NAME=bionic
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(xe|ya|ze|ar)$ ]]; then
	VERSION_NUMBER=16.04
	VERSION_NAME=xenial
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(tr|ut|vi|wi)$ ]]; then
	VERSION_NUMBER=14.04
	VERSION_NAME=trusty
fi
# Add appropriate repository
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
sudo apt-get install -y apt-transport-https
echo "deb https://download.mono-project.com/repo/ubuntu stable-"${VERSION_NAME}" main" | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
sudo apt-get update
sudo apt-get install -y mono-devel monodevelop
# Build example file to test installation
# https://www.mono-project.com/docs/getting-started/mono-basics/
cd /tmp
cat > /tmp/hello_mono.cs << EOF
using System;
 
public class HelloWorld
{
    static public void Main ()
    {
        Console.WriteLine ("Hello, Mono World!");
    }
}
EOF
csc /tmp/hello_mono.cs
mono hello_mono.exe
cat > /tmp/hello_mono_winforms.cs << EOF
using System;
using System.Windows.Forms;

public class HelloWorld : Form
{
    static public void Main ()
    {
        Application.Run (new HelloWorld ());
    }

    public HelloWorld ()
    {
        Text = "Hello, Mono World";
    }
}
EOF
csc /tmp/hello_mono_winforms.cs -r:System.Windows.Forms.dll
mono hello_mono_winforms.exe

# Install Spez custom web browser from Debian package
APP_NAME=Spez
APP_GUI_NAME=""
APP_VERSION=9.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}brow_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/libgranite5-common.deb -J -L https://code.launchpad.net/~philip.scott/+archive/ubuntu/spice-up-daily/+files/libgranite-common_5.2.3+r201901160601-1355+pkg106~ubuntu5.0.1_all.deb
curl -o /tmp/libgranite5.deb -J -L https://code.launchpad.net/~philip.scott/+archive/ubuntu/spice-up-daily/+files/libgranite5_5.2.3+r201901160601-1355+pkg106~ubuntu5.0.1_${KERNEL_TYPE}.deb
sudo gdebi -n libgranite5-common.deb
sudo gdebi -n libgranite5.deb
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/spez-browser-mirrors/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install JIBS (Java Image Browser Sorter) image viewer focused on image sorting from package
APP_NAME=JIBS
APP_GUI_NAME="Image viewer focused on image sorting."
APP_VERSION=3.2.1
APP_EXT=jar
FILE_NAME=${APP_NAME}-legacy-Java8-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/img-browse-sort/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Graphics;
Keywords=Image;Viewer;Java;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install zBoy classic Gameboy emulator from source
APP_NAME=zBoy
APP_GUI_NAME="Classic Gameboy emulator."
APP_VERSION=0.70
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libsdl2-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
cp Makefile.linux Makefile
make
sudo mv ${APP_NAME,,} /usr/local/bin
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install phpBlueDragon PassWeb web-based password manager
APP_NAME=PassWeb
APP_VERSION=1.0.0
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=phpBlueDragon_${APP_NAME}_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/phpbluedragon-passweb/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/*${APP_NAME}*/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/install.php &
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php &
Icon=${WWW_HOME}/${APP_NAME,,}/favicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=Password;Security;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/

# Install TestLink web-based (PHP/MySQL) test and requirements management tool
APP_NAME=TestLink
APP_GUI_NAME="Web-based (PHP/MySQL) test and requirements management tool"
APP_VERSION=1.9.19
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo mkdir -p /var/${APP_NAME,,}/logs/
sudo mkdir -p /var/${APP_NAME,,}/upload_area/
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data /var/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/install/index.php &
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php &
Icon=${WWW_HOME}/${APP_NAME,,}/gui/themes/default/images/tl-logo-transparent.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Testing;Requirements;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/

# Install fnm (Fast Node Manager) Node.js package version manager from package
APP_NAME=fnm 
APP_GUI_NAME="Node.js package version manager."
APP_VERSION=1.0.0
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/Schniz/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${FILE_NAME} /usr/local/bin
sudo chmod a+x /usr/local/bin/${FILE_NAME}
sudo ln -s -f /usr/local/bin/${FILE_NAME} /usr/local/bin/${APP_NAME,,}
echo 'eval `fnm env`' >> $HOME/.bashrc
sudo rm -rf /tmp/${APP_NAME,,}*

# Install RedisView GUI management tool for Redis databases from package
APP_NAME=RedisView
APP_GUI_NAME="GUI management tool for Redis databases."
APP_VERSION=1.6.4
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/default.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Redis;Database;Cache;NoSQL;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install QFutureBuilder Qt-based desktop goal tracker from Debian package	
APP_NAME=QFutureBuilder
APP_GUI_NAME="Qt-based desktop goal tracker"
APP_VERSION=N/A
APP_EXT=tar.gz
FILE_NAME=linux_deb
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/futurbuilder/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}/${APP_NAME,,}.deb

# Install Notable Markdown-based note-taking tool from Debian package
APP_NAME=Notable
APP_GUI_NAME="Markdown-based note-taking tool."
APP_VERSION=1.2.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_amd64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/fabiospampinato/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}/${APP_NAME,,}.deb

# Install Klavaro GTK3-based Touch Typing Tutor from source
APP_NAME=Klavaro
APP_GUI_NAME="GTK3-based Touch Typing Tutor."
APP_VERSION=3.09
APP_EXT=tar.bz2
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y intltool libgtk-3-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install NitsLoch Java-based classic RPG from package
APP_NAME=NitsLoch
APP_GUI_NAME="Java-based classic RPG."
APP_VERSION=2.2.1
APP_EXT=zip
FILE_NAME=${APP_NAME}${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Entertainment;Games;
Keywords=RPG;Retro;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Web Contact Manager (WCM) web-based (PHP/MySQL) contact management tool
APP_NAME=WCM
APP_GUI_NAME="Web-based (PHP/MySQL) contact management tool."
APP_VERSION=1.4.1
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}.${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/webcontactmanag/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cp /tmp/${FILE_NAME}/${APP_NAME,,}/inc/Config.Sample.inc.php /tmp/${FILE_NAME}/${APP_NAME,,}/inc/Config.inc.php
sed -i 's@wcmpass@wcm@g' /tmp/${FILE_NAME}/${APP_NAME,,}/inc/Config.inc.php
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}/Uploads
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}/Images
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data /var/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/index.php &
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php &
Icon=${WWW_HOME}/${APP_NAME,,}/SiteLogo.jpg
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Contacts;Address;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install A Text Editor inspired by Sam and Acme text editors for the Plan 9 operating system from package
APP_NAME=A
APP_GUI_NAME="Text Editor inspired by Sam and Acme text editors for the Plan 9 operating system."
APP_VERSION=0.7.3
APP_EXT=zip
FILE_NAME=a-linux-amd64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/as/a/files/2135664/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
chmod a+x /tmp/${FILE_NAME}/a
sudo mv /tmp/${FILE_NAME}/* /usr/local/bin
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/a
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Text;Editor;Acme;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/

# Install FRequest Qt-based desktop HTTP(S) request tool from AppImage
APP_NAME=FRequest
APP_VERSION=1.1c
APP_EXT=AppImage
FILE_NAME=${APP_NAME}${APP_VERSION//./}_linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/fabiobento512/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment="Qt-based desktop HTTP(S) request tool."
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=HTTP;Web;Services
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install PHP My Family web-based (PHP/MySQL) genealogy tool with GEDCOM support
APP_NAME=PHPMyFamily
APP_GUI_NAME="Web-based (PHP/MySQL) genealogy tool with GEDCOM support."
APP_VERSION=v2.1.0-alpha-2
APP_EXT=tar.gz
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=pmf${APP_VERSION//./-}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cp /tmp/${FILE_NAME}/inc/database.inc /tmp/${FILE_NAME}/inc/database.inc.php
sed -i 's@""@"'${APP_NAME,,}'"@g' /tmp/${FILE_NAME}/inc/database.inc.php
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
xdg-open http://localhost/${APP_NAME,,}/admin/install.php &
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=
Exec=xdg-open http://localhost/${APP_NAME,,}/index.php &
Icon=${WWW_HOME}/${APP_NAME,,}/images/favicon.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Education;
Keywords=Genealogy;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Universal Password Manager (UPM) Java-based password manager from package
APP_NAME=UPM
APP_GUI_NAME="Java-based password manager."
APP_VERSION=1.15.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Internet;
Keywords=Password;Security;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Ghost Desktop Electron-based blog management tool from Debian package
APP_NAME=Ghost-Desktop
APP_GUI_NAME="Electron-based blog management tool."
APP_VERSION=1.7.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-debian
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/tryghost/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Gede Qt-based GUI front-end to GDB from source
APP_NAME=Gede
APP_GUI_NAME="Qt-based GUI front-end to GDB."
APP_VERSION=2.12.3
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y qt5-default exuberant-ctags
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://gede.acidron.com/uploads/source/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;
Keywords=GDB;Debugger;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install GEDKeeper cross-platform personal genealogical database tool from Debian package
APP_NAME=GEDKeeper
APP_GUI_NAME="Cross-platform personal genealogical database tool."
APP_VERSION=2.15.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}-1_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Kevora cross-platform Qt-based database management/query tool with support for MySQL, Oracle, PostgreSQL, and SQLite from source
APP_NAME=Kevora
APP_GUI_NAME="Cross-platform Qt-based database management/query tool with support for MySQL, Oracle, PostgreSQL, and SQLite."
APP_VERSION=nightly-qt5.12
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-src-${APP_VERSION}
sudo apt-get install -y qt5-default qt5-qmake
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}
mkdir -p build && cd build && qtchooser -run-tool=qmake -qt=5 .. && make
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,}/build/${APP_NAME,,} /usr/local/bin  # No 'install' target for make
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,}/ui/svg/${APP_NAME,,}.svg /usr/local/share/pixmaps/${APP_NAME,,}.svg
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;System;
Keywords=Database;SQL;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install YouTube-DL-PyTK simple Python/Tkinter GUI for downloading videos from YouTube from package
APP_NAME=YouTube-DL-PyTK
APP_GUI_NAME="Simple Python/Tkinter GUI for downloading videos from YouTube."
APP_VERSION=19.2.17
APP_EXT=tar.xz
FILE_NAME=${APP_NAME}_${APP_VERSION}
sudo apt-get install -y python3-tk menu
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/youtube-dl-gtk/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME}
sudo /tmp/${FILE_NAME}/${APP_NAME}/install.sh
cd $HOME
sudo -rm -rf /tmp/${APP_NAME}*

# Install Muse Qt-based digital audio workstation (DAW) and MIDI/sudio sequencer with recording and editing capabilities from source
APP_NAME=Muse
APP_GUI_NAME="Qt-based digital audio workstation (DAW) and MIDI/sudio sequencer with recording and editing capabilities."
APP_VERSION=3.0.2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y build-essential cmake libsndfile1-dev libsamplerate0-dev libjack-jackd2-dev ladspa-sdk qt5-default qttools5-dev qttools5-dev-tools liblo-dev dssi-dev lv2-dev libsamplerate0-dev libsndfile1-dev git libfluidsynth-dev libgtkmm-2.4-dev librtaudio-dev libqt5svg5-dev libinstpatch-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/l${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
mkdir -p build && cd build 
cmake -DCMAKE_BUILD_TYPE=release .. && make clean all && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Hypercube Qt-based graph visualization tool from Debian package
APP_NAME=Hypercube
APP_VERSION=1.7.0
APP_EXT=deb
source /etc/lsb-release
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://download.opensuse.org/repositories/home:/tumic:/${APP_NAME}/xUbuntu_${DISTRIB_RELEASE}/${KERNEL_TYPE}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Colon Electron-based flexible text editor and hybrid IDE from AppImage
APP_NAME=Colon
APP_GUI_NAME="Electron-based flexible text editor and hybrid IDE."
APP_VERSION=1.4.2
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-${APP_VERSION}-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/Chhekur/colon-ide/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=IDE;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install ff Rust-based, cross-platform CLI file finder from package
APP_NAME=ff
APP_GUI_NAME="Rust-based, cross-platform CLI file finder."
APP_VERSION=0.1.1
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i686
fi
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}-${ARCH_TYPE}-unknown-linux-gnu
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/vishaltelangre/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install Dr. Geo cross-platform interactive geometry package from package
APP_NAME=DrGeo
APP_GUI_NAME="Cross-platform interactive geometry package."
APP_VERSION=19.03a
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	sudo dpkg --add-architecture i386  # Add libraries for 32-bit architecture
	sudo apt-get update -y 
	sudo apt-get dist-upgrade -y
	sudo apt-get install -y libcairo2:i386 libgl1-mesa-glx:i386
else    # Otherwise use version for 32-bit kernel
	sudo apt-get install -y libcairo2 libgl1-mesa-glx
fi
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}-${ARCH_TYPE}-unknown-linux-gnu
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/vishaltelangre/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install REDasm interactive, multiarchitecture, Qt-based disassembler from package
APP_NAME=REDasm
APP_GUI_NAME="Interactive, multiarchitecture, Qt-based disassembler."
APP_VERSION=2.0
APP_EXT=zip
FILE_NAME=${APP_NAME}_${APP_VERSION}_Linux_x86_64
sudo apt-get install -y qt5-default libqt5webengine5 libqt5webenginewidgets5
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://redasm.io/download/1/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Assembly;Debugging;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo -rm -rf /tmp/${APP_NAME}*

# Install Raven Reader Electron-based RSS news reader from AppImage
APP_NAME=Raven-Reader
APP_GUI_NAME="Electron-based RSS news reader."
APP_VERSION=0.4.4
APP_EXT=AppImage
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/mrgodhani/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;
Keywords=RSS;News;Aggregator;Reader;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install SmallPassKeeper Java-based password manager from Debian package
APP_NAME=SmallPassKeeper
APP_VERSION=0.9.8
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/smallpasskepper/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install GPT fdisk (gdisk) disk partitioning tool for GUID Partition Table (GPT) disks from Debian package
APP_NAME=gdisk
APP_VERSION=1.0.4-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/gptfdisk/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install fixparts Master Boot Record (MBR) repair tool for GUID Partition Table (GPT) disks from Debian package
APP_NAME=fixparts
APP_VERSION=1.0.4-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/gptfdisk/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install Filetto cross-platform FTP client & server from package
APP_NAME=Filetto
APP_GUI_NAME="Cross-platform FTP client & server."
APP_VERSION=1.0
APP_EXT=tar.gz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=i686
fi
FILE_NAME=${APP_NAME,,}-linux-${ARCH_TYPE}-${APP_VERSION}
sudo apt-get install -y libicu63
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Exec=/opt/${APP_NAME,,}/${APP_NAME}
Icon=/opt/${APP_NAME,,}/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=FTP;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo -rm -rf /tmp/${APP_NAME}*

# Install Lush Lisp dialect with extensions for object-oriented and array-oriented programming from source
APP_NAME=Lush
APP_GUI_NAME="Lisp dialect with extensions for object-oriented and array-oriented programming."
APP_VERSION=2.0.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y binutils-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/l${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make clean all && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}*

# Install pyFileSearcher cross-platform Python/Qt GUI file search tool from package
APP_NAME=pyFileSearcher
APP_GUI_NAME="Cross-platform Python/Qt GUI file search tool."
APP_VERSION=1.1.1
APP_EXT=tgz
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME}-${APP_VERSION}_linux_qt5_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/${APP_NAME}
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
Exec=/opt/${APP_NAME,,}/${APP_NAME}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;System;
Keywords=File;Search;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo -rm -rf /tmp/${APP_NAME}*

# Install ArgoUML Java-based UML diagram editor/modeling tool from package
APP_NAME=ArgoUML
APP_GUI_NAME="Java-based UML diagram editor/modeling tool."
APP_VERSION=0.34
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L http://argouml-downloads.tigris.org/nonav/${APP_NAME,,}-${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}-${APP_VERSION}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=/opt/${APP_NAME,,}/icon/${APP_NAME,,}2.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=UML;Diagramming;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install NoSQLBooster cross-platform GUI manager for MongoDB from AppImage
APP_NAME=NoSQLBooster
APP_GUI_NAME="Cross-platform GUI manager for MongoDB."
APP_VERSION=5.1.5
APP_EXT=AppImage
FILE_NAME=${APP_NAME,,}4mongo-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://nosqlbooster.com/s3/download/releasesv5/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -f -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;NoSQL;MongoDB;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Inboxer cross-platform, Electron-based Gmail desktop client from Debian package
APP_NAME=Inboxer
APP_GUI_NAME="Cross-platform, Electron-based Gmail desktop clienti."
APP_VERSION=1.3.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/denysdovhan/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Etcher cross-platform, Electron-based tool for writing ISO images to SD cards/USB drives from Debian package
APP_NAME=Etcher
APP_GUI_NAME="Cross-platform, Electron-based tool for writing ISO images to SD cards/USB drives."
APP_VERSION=1.5.19
APP_EXT=deb
FILE_NAME=balena-${APP_NAME,,}-electron_${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/balena-io/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install SQLite-New cross-platform Qt-based SQLite GUI manager from source
APP_NAME=SQLite-New
APP_GUI_NAME="Cross-platform Qt-based SQLite GUI manager."
APP_VERSION=N/A
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-master
sudo apt-get install -y qt5-default libsqlite3-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/srgank/${APP_NAME,,}/archive/master.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME}-master
mkdir build && cd build
qtchooser -run-tool=qmake -qt=5 CONFIG+=release PREFIX=/usr/local .. && make && sudo make install
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Space Faring 2D single-player turn-based 4X space conquest strategy game from package
APP_NAME=Space-Faring
APP_GUI_NAME="2D single-player turn-based 4X space conquest strategy game."
APP_VERSION=0.1.0
APP_EXT=jar
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar ${FILE_NAME}.${APP_EXT}
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
Exec=java -jar ${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Games;Simulation;Space;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Radio Player Forte Plus cross-platform Internet radio player from package
APP_NAME=RadioPlayer
APP_GUI_NAME="Cross-platform Internet radio player."
APP_VERSION=6.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/radio-player-forte-plus/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
/opt/${APP_NAME,,}/radio-player
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
Exec=/opt/${APP_NAME,,}/radio-player
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Multimedia;Entertainment;
Keywords=Audio;Radio;Player;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install QElectroTech electronic diagraming tool from PPA
sudo add-apt-repository -y ppa:scorpio/ppa
sudo apt-get update -y
sudo apt-get install -y qelectrotech

# Install SQLTabs cross-platform, multi-database (MySQL, PostgreSQL, SQL Server, etc.) GUI database management/client tool from package
APP_NAME=SQLTabs
APP_GUI_NAME="Cross-platform, multi-database (MySQL, PostgreSQL, SQL Server, etc.) GUI database management/client tool."
APP_VERSION=1.0.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}.linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/sasha-alias/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,}*/* /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=/opt/${APP_NAME,,}/logo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Moeditor cross-platform, Electron-based Markdown editor from Debian package
APP_NAME=Moeditor
APP_GUI_NAME="Cross-platform, Electron-based Markdown editor."
APP_VERSION=0.2.0-1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME}/${APP_NAME}/releases/download/v0.2.0-beta/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Persepolis Python-based GUI for aria2 download manager from Debian package
APP_NAME=Persepolis
APP_GUI_NAME="Python-based GUI for aria2 download manager."
APP_VERSION=3.1.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}.0_all
sudo apt-get install -y aria2
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/persepolisdm/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install NSBase cross-platform database alternative to MS Access from Debian package
APP_NAME=NSBase
APP_GUI_NAME="Cross-platform database alternative to MS Access."
APP_VERSION=V1.0.9
APP_EXT=deb
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32-i386
fi
FILE_NAME=${APP_NAME,,}-${ARCH_TYPE}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Apricot Java-based database ERD, design, and reverse-engineering tool from package
APP_NAME=ApricotDB
APP_GUI_NAME="Java-based database ERD, design, and reverse-engineering tool."
APP_VERSION=0.4
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-all-bin
sudo apt-get install -y openjdk-11-jre openjfx
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/apricot-db/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/* /opt
sudo chmod -R a+w /opt/${APP_NAME,,}
sudo chmod a+x /opt/${APP_NAME,,}/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development
Keywords=Database;SQL;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install VSCodium open-source version of Visual Studio Code (VSCode) from repository
# https://www.fossmint.com/vscodium-clone-of-visual-studio-code-for-linux/
wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | sudo apt-key add -
echo 'deb https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/repos/debs/ vscodium main' | sudo tee --append /etc/apt/sources.list.d/vscodium.list
sudo apt-get update
sudo apt-get install -y vscodium

# Install Coffee minimalist news and weather widget from Debian package
# https://www.fossmint.com/coffee-news-and-weather-app-for-linux/
APP_NAME=Coffee
APP_GUI_NAME="Minimalist news and weather widget."
APP_VERSION=1.1.0
source /etc/lsb-release
if [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(ar|bi|co|di)$ ]]; then
	VERSION_NUMBER=17.10
	VERSION_NAME=artful
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(ze)$ ]]; then
	VERSION_NUMBER=17.04
	VERSION_NAME=zesty
elif [[ ! "${DISTRIB_CODENAME:0:2}" =~ ^(xe|ya)$ ]]; then
	VERSION_NUMBER=16.10
	VERSION_NAME=xenial
fi
APP_EXT=deb
FILE_NAME=com.github.nick92.${APP_NAME,,}_${APP_VERSION}~ubuntu${VERSION_NUMBER}_${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://launchpad.net/~coffee-team/+archive/ubuntu/${APP_NAME,,}/+files/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Mattermost cross-platform, Electron-based workplace messaging alternative to Slack from Debian package
APP_NAME=Mattermost
APP_GUI_NAME="Cross-platform, Electron-based workplace messaging alternative to Slack."
APP_VERSION=4.2.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-desktop-${APP_VERSION}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://releases.mattermost.com/desktop/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Doffen SSH Tunnel cross-platform SSH terminal, file transfer, and tunnelling tool from AppImage
APP_NAME=DoffenSSHTunnel
APP_GUI_NAME="Cross-platform SSH terminal, file transfer, and tunnelling tool."
APP_VERSION=0.9.36
APP_EXT=AppImage
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x86_64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
FILE_NAME=${APP_NAME}-v${APP_VERSION}-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;
Keywords=SSH;Networking;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}

# Install Yet Another Python Sudoku (YAPySudoku) puzzle game built with wxPython and Pygame from package
APP_NAME=YAPySudoku
APP_GUI_NAME="Puzzle game built with wxPython and Pygame."
APP_VERSION=4.0.2
APP_EXT=tar.xz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y python3-pygame python3-wxgtk4.0
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
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
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME,,}.py
Icon=/opt/${APP_NAME,,}/icons/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Sudoku;Puzzle;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Entity Relationship Designer Java-based database design tool from Debian package
APP_NAME=ERDesignerNG
APP_GUI_NAME="Java-based database design tool."
APP_VERSION=3.1.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y openjdk-11-jre
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/mogwai/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Taskboard PHP/SQLite-based Kanban-style task management tool from package
APP_NAME=TaskBoard
APP_GUI_NAME="PHP/SQLite-based Kanban-style task management tool."
APP_VERSION=N/A
APP_EXT=zip
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/kiswa/TaskBoard/archive/master.zip
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME}-master/* ${WWW_HOME}/${APP_NAME,,}
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
sudo chmod -R a+w ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
cd ${WWW_HOME}/${APP_NAME,,}
./build/composer.phar install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=xdg-open http://localhost/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Development;Programming;
Keywords=Task Management;Project Management;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
xdg-open http://localhost/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install CutePy Qt-based interactive Python console with with variable explorer, command history, and syntax highlighting from package
APP_NAME=CutePy
APP_GUI_NAME="Qt-based interactive Python console with with variable explorer, command history, and syntax highlighting."
APP_VERSION=1.1
APP_EXT=zip
FILE_NAME=${APP_NAME}_v${APP_VERSION}
sudo apt-get install -y python3-pyqt5
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/${APP_NAME}.pyw
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
Exec=python3 /opt/${APP_NAME,,}/${APP_NAME}.py
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Editor;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install MDyna React- and Electron-based Markdown editor from Debian package
APP_NAME=MDyna
APP_GUI_NAME="React- and Electron-based Markdown editor."
APP_VERSION=0.5.3
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}-app/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install SQLite3 Page Explorer Electron-based tool for exploring internal organization of SQLite 3 databases from package
APP_NAME=SQLite3-Page-Explorer
APP_GUI_NAME="Electron-based tool for exploring internal organization of SQLite 3 databases."
APP_VERSION=1.0-linux
APP_EXT=zip
FILE_NAME=${APP_NAME,,}-linux-x64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/siara-cc/sqlite3_page_explorer/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;SQLite;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install jMathPaper Java-based notepad calculator from package
APP_NAME=jMathPaper
APP_GUI_NAME="Java-based notepad calculator."
APP_VERSION=1.3
APP_EXT=jar
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-full
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://gitlab.com/RobertZenz/${APP_NAME}/uploads/ac8f51c915d564128d9c1692f05db101/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Education;
Keywords=Calculator
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install ripgrep command-line file search tool that recursively traverses directory structure from Debian package
APP_NAME=ripgrep
APP_GUI_NAME="Command-line file search tool that recursively traverses directory structure."
APP_VERSION=11.0.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/BurntSushi/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Encryptic Electron-based encryption-focused Markdown note-taking tool from package
APP_NAME=Encryptic
APP_GUI_NAME="Electron-based encryption-focused Markdown note-taking tool."
APP_VERSION=0.0.4
APP_EXT=zip
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=ia32
fi
FILE_NAME=${APP_NAME}-${APP_VERSION}-linux-${ARCH_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/encryptic-team/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Notepad;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install PotatoSQL Java-based database design and learning tool from package
# https://github.com/x-jrga/potatosql
APP_NAME=PotatoSQL
APP_GUI_NAME="Java-based database design and learning tool."
APP_VERSION=0.4
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION//./}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.jar
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.jar
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Database;SQL;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install SOFA Statistics simple statistics, analysis, and reporting tool from Debian package
APP_NAME=SOFAStatistics
APP_GUI_NAME="Simple statistics, analysis, and reporting."
APP_VERSION=1.5.2-1
APP_EXT=deb
FILE_NAME=sofastats-${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Knobjex wxPython personal information manager (PIM) from package
APP_NAME=Knobjex
APP_GUI_NAME="wxPython personal information manager (PIM)."
APP_VERSION=4.07
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_source
sudo apt-get install -y python3-wxgtk4.0
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}-info-manager/${FILE_NAME}.${APP_EXT}
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
python3 /opt/${APP_NAME,,}/main_startup.py
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
Exec=python3 /opt/${APP_NAME,,}/main_startup.py
Icon=/opt/${APP_NAME,,}/icons/kjx_logo.ico
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;Office;
Keywords=PIM;Calendar;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Gaphor simple Python UML modeling tool from package
APP_NAME=Gaphor
APP_GUI_NAME="Simple Python UML modeling tool."
APP_VERSION=1.0.1
APP_EXT=whl
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-py3-none-any
sudo apt-get install -y python3-setuptools python3-pip python3-wheel
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo pip3 install /tmp/${FILE_NAME}.${APP_EXT}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=UML;Modeling;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Q Vault Electron-based password manager from Snap package
APP_NAME=QVault
APP_GUI_NAME="Electron-based password manager."
APP_VERSION=0.0.31
APP_EXT=snap
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/Q-Vault/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo snap install --dangerous /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install LSD (LSDeluxe) Rust-based next-generation 'ls' command from Debian package
APP_NAME=LSD
APP_GUI_NAME="Rust-based next-generation 'ls' command."
APP_VERSION=0.14.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/Peltoche/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Hypernomicon Java-based research tracking database with built-in PDF viewer from package
APP_NAME=Hypernomicon
APP_GUI_NAME="Java-based research tracking database with built-in PDF viewer."
APP_VERSION=1.14
APP_EXT=sh
FILE_NAME=${APP_NAME}_linux_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo sh /tmp/${FILE_NAME}.${APP_EXT} -c -q -dir /opt/${APP_NAME,,} -overwrite

# Install Maxit Qt/OpenGL-based math puzzle game from source
APP_NAME=Maxit
APP_GUI_NAME="Qt/OpenGL-based math puzzle game."
APP_VERSION=1.04
APP_EXT=tar.gz
FILE_NAME=${APP_NAME}.d
sudo apt-get install -y qt5-default qt5-qmake
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${FILE_NAME,,}
mkdir -p build && cd build
qtchooser -run-tool=qmake -qt=5 ../${APP_NAME,,}.pro && make
sudo cp /tmp/${FILE_NAME}/${FILE_NAME,,}/build/${APP_NAME} /usr/local/bin  # No 'install' target for make
sudo cp /tmp/${FILE_NAME}/${FILE_NAME,,}/images.d/${APP_NAME,,}.png /usr/local/share/pixmaps/${APP_NAME,,}.png
sudo ln -s -f /usr/local/bin/${APP_NAME} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME}
Icon=/usr/local/share/pixmaps/${APP_NAME,,}.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;Education;
Keywords=Puzzle;Game;Math;Education;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Motrix Electron-based GUI download manager (aria wrapper) from Debian package
APP_NAME=Motrix
APP_GUI_NAME="Electron-based GUI download manager (aria wrapper)."
APP_VERSION=1.3.8
APP_EXT=deb
FILE_NAME=${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/agalwood/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Praxis Live Java hybrid visual live programming environment based on Netbeans from Debian package
APP_NAME=Praxis-Live
APP_GUI_NAME="Java hybrid visual live programming environment based on Netbeans."
APP_VERSION=4.3.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}-1_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install sslh protocol multiplexer that allows sharing SSL/HTTPS and SSH on same port from source
# http://rutschle.net/tech/sslh/README.html
APP_NAME=sslh
APP_GUI_NAME="Protocol multiplexer that allows sharing SSL/HTTPS and SSH on same port."
APP_VERSION=1.20
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libwrap0-dev libconfig-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/yrutschle/${APP_NAME,,}/archive/v${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make && sudo make install
sudo cp basic.cfg /etc/sslh.cfg
sudo cp scripts/etc.init.d.sslh /etc/init.d/sslh
sudo update-rc.d sslh defaults

# Install Rats on the Boat P2P BitTorrent search engine desktop client with integrated BitTorrent client from Debian package
APP_NAME=Rats-Search
APP_GUI_NAME="P2P BitTorrent search engine desktop client with integrated BitTorrent client."
APP_VERSION=1.2.2
APP_EXT=deb
FILE_NAME=${APP_NAME,,}-${APP_VERSION}-${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/DEgITx/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install pstoedit PostScript/PDF converter to other vector formats from source
APP_NAME=pstoedit
APP_GUI_NAME="PostScript/PDF converter to other vector formats."
APP_VERSION=3.74
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y ghostscript
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure.sh && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install mtCellEdit lightweight Qt-based spreadsheet program from AppImage
APP_NAME=mtCellEdit
APP_GUI_NAME="Lightweight Qt-based spreadsheet program."
APP_VERSION=3.3
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-${APP_VERSION}-qt4-x86_64
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/matyler/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Office;
Keywords=Spreadsheet;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Arronax Python/GTK GUI for creating/editing starter (.desktop) files from Debian package
APP_NAME=Arronax
APP_GUI_NAME="Python/GTK GUI for creating/editing starter (.desktop) files."
APP_VERSION=0.7.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://www.florian-diesch.de/software/${APP_NAME,,}/dist/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install mtag command-line media tagging utility from source
APP_NAME=mtag
APP_GUI_NAME="Command-line media tagging utility."
APP_VERSION=2.2.4
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libtag1-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/psemiletov/${APP_NAME,,}/archive/${APP_VERSION}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
make && sudo make install

# Install Dnote cross-platform lightweight encrypted console notebook for developers from package
APP_NAME=Dnote
APP_GUI_NAME="Cross-platform lightweight encrypted console notebook for developers."
APP_VERSION=0.8.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_linux_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/cli-v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Gis Weather desktop weather widget from Debian package
APP_NAME=Gis-Weather
APP_GUI_NAME="Desktop weather widget."
APP_VERSION=0.8.4.1
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Fractal Zoomer Java-based fractal generator and explorer tool from package
# https://github.com/x-jrga/potatosql
APP_NAME=FractalZoomer
APP_GUI_NAME="Java-based fractal generator and explorer tool."
APP_VERSION=1.0.7.4
APP_EXT=jar
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/Fractal%20Zoomer.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod -R a+w /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Science;
Keywords=Graphics;Fractal;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Iso2Usb utility to create bootable USB drive from ISO image from Debian package
APP_NAME=Iso2Usb
APP_GUI_NAME="Utility to create bootable USB drive from ISO image."
APP_VERSION=0.1.5.0
APP_EXT=deb
FILE_NAME=${APP_NAME}-${APP_VERSION}-${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/KaustubhPatange/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}

# Install Tute Java-based Spanish playing card game from package
APP_NAME=Tute
APP_GUI_NAME="Java-based Spanish playing card game."
APP_VERSION=N/A
APP_EXT=jar
FILE_NAME=${APP_NAME}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}-cardgame/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
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
Exec=java -jar /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;
Keywords=Cards;Games;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Topgrade cross-platform/cross-distribution upgrade manager from package
# https://www.ostechnix.com/how-to-upgrade-everything-using-a-single-command-in-linux/
APP_NAME=Topgrade
APP_GUI_NAME="Cross-platform/cross-distribution upgrade manager."
APP_VERSION=2.3.1
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}-x86_64-unknown-linux-gnu
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/r-darwish/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mv /tmp/${FILE_NAME}/${APP_NAME,,} /usr/local/bin
cd $HOME
rm -rf /tmp/*${APP_NAME}* /tmp/*${APP_NAME,,}*

# Install Race Into Space SDL-based remake of classic Interplay game from source
APP_NAME=RaceIntoSpace
APP_GUI_NAME="SDL-based remake of classic Interplay game."
APP_VERSION=N/A
APP_EXT=N/A
FILE_NAME=N/A
sudo apt-get install -y cmake libsdl-dev libboost-dev libpng-dev libjsoncpp-dev libogg-dev libvorbis-dev libtheora-dev libprotobuf-dev protobuf-compiler
cd /tmp
git clone git://github.com/${APP_NAME,,}/${APP_NAME,,}.git
mkdir ${APP_NAME,,}-build
cd ${APP_NAME,,}-build
cmake ../${APP_NAME,,} && make && sudo make install
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/usr/local/share/${APP_NAME,,}/images/aprog.0.6.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Games;Entertainment;Education;
Keywords=Space;Simulation;Retro;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install IP Calculator Java-based IP subnet calculator from package
APP_NAME=IP-Calculator
APP_GUI_NAME="Java-based IP subnet calculator."
APP_VERSION=28-06-2019
APP_EXT=zip
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_bin
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=java -jar /opt/${APP_NAME,,}/${APP_NAME,,}.jar
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Network;System;Accessories;
Keywords=Networking;Calculator;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install GitApp cross-platform Electron-based desktop GitHub client from AppImage
APP_NAME=GitApp
APP_GUI_NAME="Cross-platform Electron-based desktop GitHub client."
APP_VERSION=3.0.3
APP_EXT=AppImage
FILE_NAME=${APP_NAME}-linux-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/dan-online/${APP_NAME}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Development;Programming;
Keywords=Git;GitHub;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Scratux Linux binaries for Scatch Desktop visual programming tool from Debian package
APP_NAME=Scratux
APP_GUI_NAME="Linux binaries for Scatch Desktop visual programming tool."
APP_VERSION=1.1.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/${APP_NAME,,}/${APP_NAME,,}/releases/download/v1.1/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install minuteProject Java-based reverse-engineering tool from package
APP_NAME=minuteProject
APP_GUI_NAME="Java-based reverse-engineering tool."
APP_VERSION=0.9.10
APP_EXT=zip
FILE_NAME=${APP_NAME}-${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/bin/start-console.sh
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib:\$PATH; export PATH
/opt/${APP_NAME,,}/bin/start-console.sh
cd $HOME
EOF
sudo mv /tmp/${APP_NAME,,} /usr/local/bin
sudo chmod a+x /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}:/opt/${APP_NAME,,}/lib
Exec=/opt/${APP_NAME,,}/bin/start-console.sh
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Programming;Development;
Keywords=Hacking;Reversing;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install phpIPAM open-source PHP/MySQL-based IP address management tool (manual installation)
APP_NAME=phpIPAM
APP_VERSION=1.4
APP_EXT=tar
DB_NAME=${APP_NAME,,}
DB_USER=${APP_NAME,,}
DB_PASSWORD=${APP_NAME,,}admin
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libwbxml2-utils tnef
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir ${WWW_HOME}/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/${APP_NAME,,}/* ${WWW_HOME}/${APP_NAME,,}
sudo cp ${WWW_HOME}/${APP_NAME,,}/config.dist.php ${WWW_HOME}/${APP_NAME,,}/config.php
sudo sed -i.bak "s@define('BASE', \"/\");@define('BASE', \"/phpipam\");@g" ${WWW_HOME}/${APP_NAME,,}/config.php
sudo chown -R www-data:www-data ${WWW_HOME}/${APP_NAME,,}
# Create database
mysql -u root -proot -Bse "CREATE DATABASE ${DB_NAME};"
mysql -u root -proot -Bse "GRANT ALL ON ${DB_USER}.* TO ${DB_NAME}@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -proot -Bse "FLUSH PRIVILEGES;"
mysql -u root -proot phpipam < ${WWW_HOME}/${APP_NAME,,}/db/SCHEMA.sql
xdg-open http://localhost/${APP_NAME,,}/ &
cd $HOME
rm -rf /tmp/${APP_NAME,,}*

# Install k3rmit VTE-based minimal terminal emulator from source
APP_NAME=k3rmit
APP_GUI_NAME="VTE-based minimal terminal emulator."
APP_VERSION=1.5
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y libvte-2.91-dev libgtk-3-dev cmake
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://codeload.github.com/keylo99/${APP_NAME,,}/${APP_EXT}/${APP_VERSION}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
mkdir -p build && cd build
cmake ../ -DCMAKE_INSTALL_PREFIX=/usr/local && make && sudo make install && sudo ldconfig
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/usr/local/bin
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=System;Accessories;
Keywords=Terminal;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Cloaker cross-platform GUI password-based file encryption tool from package
APP_NAME=Cloaker
APP_GUI_NAME="Cross-platform GUI password-based file encryption tool."
APP_VERSION=2.0
APP_EXT=zip
FILE_NAME=${APP_NAME,,}Linux
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/spieglt/${APP_NAME}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME}.run /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/usr/local/bin/${APP_NAME,,}
Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Accessories;
Keywords=Encryption;Security;Privacy;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Kiwix offline Wikipedia downloader/reader desktop client from AppImage
APP_NAME=Kiwix
APP_GUI_NAME="Offline Wikipedia downloader/reader desktop client."
APP_VERSION=2.0-beta5
APP_EXT=AppImage
FILE_NAME=${APP_NAME,,}-desktop_x86_64_${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT,,}
sudo mkdir -p /opt/${APP_NAME,,}
sudo mv /tmp/${FILE_NAME}.${APP_EXT} /opt/${APP_NAME,,}
sudo chmod +x /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
sudo ln -s /opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,}.desktop << EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_GUI_NAME}
GenericName=${APP_NAME}
Path=/opt/${APP_NAME,,}
Exec=/opt/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Education;Office;
Keywords=Wikipedia;Reader;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install ProtoGraphQL Electron-based cross-platform GraphQL schema prototyping tool from Debian package
APP_NAME=ProtoGraphQL
APP_GUI_NAME="Electron-based cross-platform GraphQL schema prototyping tool."
APP_VERSION=1.0.0
APP_EXT=deb
FILE_NAME=${APP_NAME,,}_${APP_VERSION}_${KERNEL_TYPE}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/oslabs-beta/${APP_NAME,,}/releases/download/v1.0.0-beta/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Tartube PyGTK GUI frontend for youtube-dl for video download from package
APP_NAME=Tartube
APP_GUI_NAME="PyGTK GUI frontend for youtube-dl for video download."
APP_VERSION=0.7.0
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}_v${APP_VERSION}
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo cp -R /tmp/${FILE_NAME}/* /opt
sudo ln -s -f /opt/${APP_NAME,,}/${APP_NAME,,} /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Exec=/usr/local/bin/${APP_NAME,,}
Icon=/opt/${APP_NAME,,}/icons/win/system_icon_32.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Multimedia;
Keywords=YouTube;Video;Audio;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Easy Cloud Shell Java-based web file manager with built-in text editor, terminal, image viewer and video player from package
APP_NAME=Easy-Cloud-Shell
APP_GUI_NAME="Java-based web file manager with built-in text editor, terminal, image viewer and video player."
APP_VERSION=0.5
APP_EXT=tar.gz
FILE_NAME=cloud-shell-bin
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/subhra74/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
sudo mkdir -p /opt/${APP_NAME,,}
sudo cp -R /tmp/${FILE_NAME}/* /opt/${APP_NAME,,}
sudo ln -s -f /opt/${APP_NAME,,}/start-cloud-shell.sh /usr/local/bin/${APP_NAME,,}
cat > /tmp/${APP_NAME,,} << EOF
#! /bin/sh
cd /opt/${APP_NAME,,}
PATH=/opt/${APP_NAME,,}:\$PATH; export PATH
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
Exec=/opt/${APP_NAME,,}/start-cloud-shell.sh && xdg-open https://localhost:8055/
#Icon=
Type=Application
StartupNotify=true
Terminal=false
Categories=Internet;Networking;
Keywords=File;Manager;
EOF
sudo mv /tmp/${APP_NAME,,}.desktop /usr/share/applications/
cd $HOME
rm -rf /tmp/*${APP_NAME}*

# Install Cicada bash-like shell implemented in Rust from package
APP_NAME=Cicada
APP_GUI_NAME="bash-like shell implemented in Rust."
APP_VERSION=0.9.8
APP_EXT=N/A
FILE_NAME=${APP_NAME,,}-linux-${APP_VERSION}
curl -o /tmp/${FILE_NAME} -J -L https://github.com/mitnk/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}
sudo cp -R /tmp/${FILE_NAME} /usr/local/bin/${APP_NAME,,}
sudo chmod +x /usr/local/bin/${APP_NAME,,}

# Install Foliate simple Javascript-based modern GTK ebook reader from Debian package
APP_NAME=Foliate
APP_GUI_NAME="Simple Javascript-based modern GTK ebook reader."
APP_VERSION=1.4.0
APP_EXT=deb
FILE_NAME=com.github.johnfactotum.${APP_NAME,,}_${APP_VERSION}_all
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://github.com/johnfactotum/${APP_NAME,,}/releases/download/${APP_VERSION}/${FILE_NAME}.${APP_EXT}
sudo gdebi -n /tmp/${FILE_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*

# Install Pista bash/zsh shell prompt implemented in Rust from package
APP_NAME=Pista
APP_GUI_NAME="bash/zsh shell prompt implemented in Rust."
APP_VERSION=0.1.1
APP_EXT=N/A
FILE_NAME=${APP_NAME,,}-v${APP_VERSION}
curl -o /tmp/${FILE_NAME} -J -L https://github.com/NerdyPepper/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}
sudo cp -R /tmp/${FILE_NAME} /usr/local/bin/${APP_NAME,,}
sudo chmod +x /usr/local/bin/${APP_NAME,,}

# Install Eva shell/command-line calculator REPL implemented in Rust from package
APP_NAME=Eva
APP_GUI_NAME="Shell/command-line calculator REPL implemented in Rust."
APP_VERSION=0.2.5
APP_EXT=N/A
FILE_NAME=${APP_NAME,,}
curl -o /tmp/${FILE_NAME} -J -L https://github.com/NerdyPepper/${APP_NAME,,}/releases/download/v${APP_VERSION}/${FILE_NAME}
sudo cp -R /tmp/${FILE_NAME} /usr/local/bin/${APP_NAME,,}
sudo chmod +x /usr/local/bin/${APP_NAME,,}

# Install Phlipple 3D SDL-based puzzle game from source
APP_NAME=Phlipple
APP_GUI_NAME="3D SDL-based puzzle game."
APP_VERSION=0.8.5
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y pkg-config libsdl1.2-dev libvorbis-dev libglew-dev libsdl-image1.2-dev libsdl-mixer1.2-dev
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}
./configure && make && sudo make install
cd $HOME
sudo rm -rf /tmp/${APP_NAME,,}* /tmp/${APP_NAME}*
