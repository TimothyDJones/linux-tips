#!/bin/bash

# Determine if this is 32-bit or 64-bit version of kernel.
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	KERNEL_TYPE=amd64
else    # Otherwise use version for 32-bit kernel
	KERNEL_TYPE=i386
fi


# Add some necessary non-default packages
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get autoremove -f -y
sudo apt-get install -y build-essential dtrx curl wget checkinstall gdebi \
	openjdk-8-jre python-software-properties software-properties-common \
	mc

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

# Add NodeJS package repository
# https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -

# Install NodeJS, Vim 8, and Git
sudo apt-get install -y vim vim-gtk3 vim-common \
	git \
	nodejs


# Install PHP 5.6, Apache 2, and MySQL Server
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'  # Set MySQL password to 'root'.
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'
sudo apt-get install -y php5.6-bcmath php5.6-bz2 php5.6-cli php5.6-common php5.6-curl php5.6-gd php5.6-json php5.6-mbstring php5.6-mcrypt php5.6-mysql php5.6-readline php5.6-sqlite3 php5.6-xml php5.6-xsl php5.6-zip php-xdebug \
libapache2-mod-php5.6 libapache2-mod-xsendfile \
mysql-server mysql-workbench

# Enable 'modrewrite' Apache module
sudo a2enmod rewrite
sudo service apache2 restart  ## Alternate command is 'sudo apachectl restart'

# Add current user to 'www-data' group
sudo usermod -a -G www-data ${USER}

# Change owner of /var/www/html directory to www-data
sudo chown -R www-data:www-data /var/www/html

# Enable PHP 5.6 as default version of PHP (if PHP 7.0+ gets installed, as well).
sudo a2dismod php7.0 ; sudo a2enmod php5.6 ; sudo service apache2 restart ; echo 1 | sudo update-alternatives --config php

# Create simple 'phpinfo' script in main web server directory
# Note: Must create file in /tmp and then move because 'sudo cat...' is allowed.
sudo cat > /tmp/phpinfo.php << EOL
<?php
	phpinfo();
?>
EOL
sudo mv /tmp/phpinfo.php /var/www/html
sudo chown www-data:www-data /var/www/html/phpinfo.php

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
cd /var/www/html
sudo php /usr/local/bin/composer create-project phpmyadmin/phpmyadmin --repository-url=https://www.phpmyadmin.net/packages.json --no-dev
sudo chown -R www-data:www-data /var/www/html/phpmyadmin
xdg-open http://localhost/phpmyadmin/setup &
cd $HOME

# Install apt-fast script for speeding up apt-get by downloading
# packages in parallel.
# https://github.com/ilikenwf/apt-fast
sudo add-apt-repository -y ppa:saiarcot895/myppa
sudo apt-get update
sudo apt-get -y install apt-fast

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
# Ubuntu does not have recent version in packages, so we build from source,
# which requires installation of GTK+2 and other libraries.
sudo apt-get install -y pkg-config libglib2.0-dev libgtk2.0-dev libvte-dev
cd $HOME/Downloads
wget -O lilyterm.tar.gz http://lilyterm.luna.com.tw/file/lilyterm-0.9.9.4.tar.gz
dtrx -n $HOME/Downloads/lilyterm.tar.gz
cd $HOME/Downloads/lilyterm/lilyterm-0.9.9.4
./configure
make
sudo make install
cd $HOME
rm -rf $HOME/Downloads/lilyterm*
ln -s /usr/local/share/applications/lilyterm.desktop $HOME/.config/autostart/

# Install Google Go language
APP_NAME=go
APP_VERSION=1.8.3
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
APP_NAME=liteide
APP_VERSION=x32.2
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=linux64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=linux32
fi
curl -o /tmp/${APP_NAME}.tar.bz2 -J -L https://superb-dca2.dl.sourceforge.net/project/${APP_NAME}/X32.2/${APP_NAME}${APP_VERSION}.${ARCH_TYPE}-qt4.tar.bz2
curl -o /tmp/${APP_NAME}-system.tar.bz2 -J -L https://superb-dca2.dl.sourceforge.net/project/${APP_NAME}/X32.2/${APP_NAME}${APP_VERSION}.${ARCH_TYPE}-qt4-system.tar.bz2
cd /tmp
dtrx -n ${APP_NAME}.tar.bz2
sudo mv ${APP_NAME} /opt
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=LiteIDE
Comment=IDE for editing and building projects written in the Go programming language
GenericName=LiteIDE
Exec=/opt/${APP_NAME}/bin/${APP_NAME}
Icon=/opt/${APP_NAME}/share/${APP_NAME}/welcome/images/liteide128.xpm
Type=Application
StartupNotify=false
Terminal=false
Categories=Development;
Keywords=golang;go;ide;programming;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
sudo ln -s /opt/${APP_NAME}/bin/${APP_NAME} /usr/local/bin/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Firejail and Firetools utilities for running applications
# in isolated memory space.
cd /var/tmp
curl -o firejail.deb -A "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" -J -L https://superb-sea2.dl.sourceforge.net/project/firejail/firejail/firejail_0.9.48_1_${KERNEL_TYPE}.deb
curl -o firetools.deb -A "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" -J -L https://cytranet.dl.sourceforge.net/project/firejail/firetools/firetools_0.9.46_1_${KERNEL_TYPE}.deb
sudo gdebi -n firejail.deb   # '-n' is non-interactive mode for gdebi
sudo gdebi -n firetools.deb   # '-n' is non-interactive mode for gdebi
rm -f firejail.deb firetools.deb
cd $HOME

# Install Stacer Linux monitoring tool
# Must download specific version, because unable to get 'latest' from Sourceforge to work.
APP_NAME=stacer
APP_VERSION=1.0.7
cd /tmp
curl -o /tmp/${APP_NAME}.deb -A "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" -J -L https://pilotfiber.dl.sourceforge.net/project/${APP_NAME}/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.deb
sudo gdebi -n ${APP_NAME}.deb   # '-n' is non-interactive mode for gdebi
rm -f ${APP_NAME}.deb
cd $HOME

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
wget -O /tmp/vivaldi.deb https://downloads.vivaldi.com/stable/vivaldi-stable_1.8.770.50-1_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/vivaldi.deb
rm -f /tmp/vivaldi.deb

# Install Cudatext editor from Sourceforge
APP_NAME=cudatext
APP_VERSION=1.15.0.0-1
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
sudo apt-get install -y cmake qt4-default   # Install required packages
curl -o /tmp/ksnip.tar.gz -J -L https://superb-dca2.dl.sourceforge.net/project/ksnip/ksnip-1.3.0.tar.gz
cd /tmp
dtrx -n /tmp/ksnip.tar.gz
cd /tmp/ksnip/ksnip-1.3.0
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/ksnip*

# Install CopyQ clipboard manager from Sourceforge
APP_NAME=copyq
APP_VERSION=3.0.2
source /etc/os-release
curl -o /tmp/${APP_NAME}.deb -J -L https://ayera.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}-${APP_VERSION}/Linux/${APP_NAME}_${APP_VERSION}_Ubuntu_${VERSION_ID}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/${APP_NAME}.deb
sudo ln -s /usr/local/share/applications/${APP_NAME}.desktop $HOME/.config/autostart/  # Configure CopyQ to autostart on system launch
rm -f /tmp/${APP_NAME}*

# Install Steel Bank Common Lisp (SBLC) from Sourceforge
sudo apt-get install -y sbcl   # Current packaged version of SBCL required to build the updated version from source
curl -o /tmp/sblc.tar.gz -J -L https://superb-sea2.dl.sourceforge.net/project/sbcl/sbcl/1.3.20/sbcl-1.3.20-source.tar.bz2
cd /tmp
dtrx -n /tmp/sbcl.tar.gz
cd /tmp/sbcl/sbcl-1.3.20
sh make.sh
INSTALL_DIR=/usr/local sudo sh install.sh
cd $HOME
rm -rf /tmp/sbcl*

# Install Otter Browser from Sourceforge (from source)
APP_NAME=otter-browser
APP_VERSION=175
sudo apt-get install -y qt5-default libqt5multimedia5 qtmultimedia5-dev libqt5xmlpatterns5-dev libqt5webkit5-dev   # Qt5 development packages needed to build from source
curl -o /tmp/${APP_NAME}.tar.gz -J -L https://iweb.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}-weekly${APP_VERSION}/otter-browser-0.9.91-dev${APP_VERSION}.tar.bz2
cd /tmp
dtrx -n /tmp/${APP_NAME}.tar.gz
cd /tmp/otter-browser/${APP_NAME}-0.9.91-dev${APP_VERSION}
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/otter-browser*

# Install MyNotes simple "sticky notes" tool
APP_NAME=mynotes
APP_VERSION=2.2.0
APP_EXT=deb
# Install python-ewmh package from Zesty Zebra distribution.
curl -o /tmp/python3-ewmh_0.1.5-1_all.deb -J -L http://ftp.osuosl.org/pub/ubuntu/pool/universe/p/python-ewmh/python3-ewmh_0.1.5-1_all.deb
sudo gdebi -n /tmp/python3-ewmh_0.1.5-1_all.deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://phoenixnap.dl.sourceforge.net/project/my-notes/${APP_VERSION}/${APP_NAME}_${APP_VERSION}-1_all.${APP_EXT}
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
sudo apt-get install -y libjbig2dec0-dev libfreetype6-dev libftgl-dev libjpeg-dev libopenjp2-7-dev zlib1g-dev xserver-xorg-dev mesa-common-dev libgl1-mesa-dev libxcursor-dev libxrandr-dev libxinerama-dev
curl -o /tmp/mupdf.tar.gz -J -L http://mupdf.com/downloads/mupdf-1.11-source.tar.gz
cd /tmp
dtrx -n /tmp/mupdf.tar.gz
cd /tmp/mupdf/mupdf-1.11-source
make
sudo make prefix=/usr/local install
sudo ln -s /usr/local/bin/mupdf-gl /usr/local/bin/mupdf
cd $HOME
rm -rf /tmp/mupdf*

# Install tke text editor
APP_NAME=tke
APP_VERSION=3.2
APP_EXT=tgz
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls  # Install required packages
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://iweb.dl.sourceforge.net/project/${APP_NAME}/${APP_VERSION}/${APP_NAME}-${APP_VERSION}.${APP_EXT}
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

# Install JOE (Joe's Own Editor) from source
APP_NAME=joe
APP_VERSION=4.4
curl -o /tmp/${APP_NAME}.tar.gz -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}-editor/JOE%20sources/${APP_NAME}-${APP_VERSION}/${APP_NAME}-${APP_VERSION}.tar.gz
cd /tmp
dtrx -n /tmp/${APP_NAME}.tar.gz
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install KeePassXC password manager from source
curl -o /tmp/keepassxc.tar.xz -J -L https://github.com/keepassxreboot/keepassxc/releases/download/2.1.4/keepassxc-2.1.4-src.tar.xz
cd /tmp
dtrx -n /tmp/keepassxc.tar.xz
cd /tmp/keepassxc/keepassxc-2.1.4
sudo apt-get install -y libgcrypt20-dev libcrypto++-dev libxi-dev libmicrohttpd-dev libxtst-dev qttools5-dev-tools
mkdir build && cd build
cmake .. -DWITH_TESTS=OFF && make && sudo make install
cd $HOME
rm -rf /tmp/keepassxc*

# Install NewBreeze file manager
# Install from packages for 64-bit Linux
if $(uname -m | grep '64'); then 
	curl -o /tmp/NewBreeze.deb -J -L https://marcusbritanicus.github.io/NewBreeze/debs/newbreeze_3.0.0a_amd64.deb
	curl -o /tmp/NewBreeze-plugins.deb -J -L https://marcusbritanicus.github.io/NewBreeze/debs/newbreeze-plugins_3.0.0a_amd64.deb
	sudo gdebi -n /tmp/NewBreeze.deb
	sudo gdebi -n /tmp/NewBreeze-plugins.deb
else # Install from source for 32-bit Linux
	sudo apt-get install -y libmagic-dev zlib1g-dev liblzma-dev libbz2-dev libarchive-dev xdg-utils libpoppler-qt5-dev libsource-highlight-dev libpoppler-qt5-dev libdjvulibre-dev
	curl -o /tmp/NewBreeze.txz -J -L https://github.com/marcusbritanicus/NewBreeze/releases/download/v3-prealpha/NewBreeze3.txz
	cd /tmp
	dtrx -n NewBreeze.txz
	cd /tmp/NewBreeze/NewBreeze3
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
sudo mv /tmp/miniflux/miniflux-1.2.2 /var/www/html/miniflux
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 777 /var/www/html/miniflux/data
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
sudo apt-get install -y libncursesw5-dev groff sed build-essential ghostscript po4a
curl -o /tmp/wcd.tar.gz -J -L https://iweb.dl.sourceforge.net/project/wcd/wcd/6.0.0/wcd-6.0.0.tar.gz
cd /tmp
dtrx -n /tmp/wcd.tar.gz
cd /tmp/wcd/wcd-6.0.0/src
make all CURSES=ncursesw
sudo make PREFIX=/usr/local strip install
sudo ln -s /usr/local/bin/wcd.exe /usr/bin/wcd.exe	 # Create link so that shell integration works properly.
sudo make install-profile DOTWCD=1     # Set up shell integration and store configuration files under $HOME/.wcd.
cd $HOME
rm -rf /tmp/wcd*

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
APP_VERSION=2.5
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
APP_NAME=qxmledit
APP_VERSION=0.9.7
curl -o /tmp/${APP_NAME}.tgz -J -L https://superb-sea2.dl.sourceforge.net/project/qxmledit/files/QXmlEdit-${APP_VERSION}/${APP_NAME}-${APP_VERSION}-src.tgz
cd /tmp
dtrx -n ${APP_NAME}.tgz
cd /tmp/${APP_NAME}/${APP_NAME}-${APP_VERSION}/
qmake && make && sudo make install
# Create icon in menus
cat > /tmp/qxmledit.desktop << EOF
[Desktop Entry]
Name=QXmlEdit
Comment=XML Viewer and Editor
GenericName=XML Editor
Exec=/opt/wp-34s/WP-34s
Icon=/opt/wp-34s/wp34s-logo.png
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Development
Keywords=calculator;rpn;
EOF
sudo mv /tmp/wp34s.desktop /usr/share/applications/

# Install Idiomind flash card utility
APP_NAME=idiomind
APP_VERSION=0.2.9
curl -o /tmp/${APP_NAME}.deb -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/${APP_VERSION}/${APP_NAME}_${APP_VERSION}_all.deb
sudo gdebi -n /tmp/${APP_NAME}.deb   # '-n' is non-interactive mode for gdebi
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install Jailer Java database utility
APP_NAME=jailer
APP_VERSION=7.0.1
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
APP_VERSION=20170607
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=l64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=l32
fi
sudo apt-get install -y gdb
curl -o /tmp/${APP_NAME}.tgz -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}-${ARCH_TYPE}-${APP_VERSION}.tgz
dtrx -n ${APP_NAME}.tgz
sudo mv ${APP_NAME} /opt
# sudo ln -s /opt/${APP_NAME}/${APP_NAME} /usr/local/bin/${APP_NAME}
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
sudo mv ${APP_NAME} /var/www/html
sudo chown -R www-data:www-data /var/www/html/${APP_NAME}
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
APP_VERSION=2-2.2.2
curl -o /tmp/${APP_NAME}.tar.gz -J -L https://superb-sea2.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}${APP_VERSION}.tar.gz
cd /tmp
dtrx -n ${APP_NAME}.tar.gz
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
APP_VERSION=0.4.8
source /etc/os-release   # This config file contains Ubuntu version details.

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

# Install Makagiga PIM
APP_NAME=makagiga
APP_VERSION=5.8.2
curl -o /tmp/${APP_NAME}.deb -J -L https://gigenet.dl.sourceforge.net/project/${APP_NAME}/Makagiga%205.x/${APP_VERSION}/${APP_NAME}_${APP_VERSION}-1_all.deb
cd /tmp
sudo gdebi -n ${APP_NAME}.deb
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

# Install HTTP Test Tool
APP_NAME=httest
APP_VERSION_MAJOR=2.4
APP_VERSION_MINOR=21
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://ayera.dl.sourceforge.net/project/htt/htt${APP_VERSION_MAJOR}/${APP_NAME}-${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}/${APP_NAME}-${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}.${APP_EXT}

# Install ubunsys installer/tweaker
APP_NAME=ubunsys
APP_VERSION=2017.07.30
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
APP_VERSION_MINOR=3607
APP_EXT=deb
# libpasastro (Pascal astronomical library) is dependency for Skychart.
curl -o /tmp/libpasastro.deb -J -L https://superb-sea2.dl.sourceforge.net/project/libpasastro/version_1.1-19/libpasastro_1.1-19_${KERNEL_TYPE}.deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://versaweb.dl.sourceforge.net/project/${APP_NAME}/0-beta/2017-06-26/${APP_NAME}_${APP_VERSION_MAJOR}-${APP_VERSION_MINOR}_${KERNEL_TYPE}.deb
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
APP_VERSION=1.7.3
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
APP_VERSION=2.1
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://phoenixnap.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}_${APP_VERSION}.${APP_EXT}
cd /tmp
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install XML Tree Editor from Debian package
APP_NAME=xmltreeedit
APP_VERSION=0.1.0.30
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L http://cfhcable.dl.sourceforge.net/project/xmltreeeditor/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
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
APP_VERSION=0.9
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
APP_VERSION=3.11.0
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
APP_VERSION=3.2.0
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
APP_VERSION=4.5.6
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
APP_VERSION=0.18.13
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://iweb.dl.sourceforge.net/project/brave-browser.mirror/v${APP_VERSION}beta/${APP_NAME}_${APP_NAME}_${KERNEL_TYPE}.${APP_EXT}
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
APP_VERSION=9.4
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://pilotfiber.dl.sourceforge.net/project/zentao/${APP_VERSION}/${APP_NAME}_${APP_VERSION}_1_all.${APP_EXT}
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
rm -rf ${APP_NAME)*

# Install BoostNote notepad/PIM from package
APP_NAME=boostnote
APP_VERSION=0.8.12
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://github.com/BoostIO/boost-releases/releases/download/v${APP_VERSION}/${APP_NAME}_${APP_VERSION}_${KERNEL_TYPE}.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf /tmp/${APP_NAME}*

# Install QOwnNotes notepad/PIM from PPA repository
sudo add-apt-repository -y ppa:pbek/qownnotes
sudo apt-get update -y
sudo apt-get install -y qownnotes

# Install Red Notebook notepad/PIM from source
APP_NAME=rednotebook
APP_VERSION=2.1.5
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
rm -rf ${APP_NAME)*

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
APP_VERSION=2.11.2
APP_EXT=zip
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME}/${APP_NAME}-${APP_VERSION}-bin.${APP_EXT}
cd /tmp

# Install Super Productivity To Do List and task manager from package
APP_NAME=superProductivity
APP_VERSION=latest
APP_EXT=deb
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/super-productivity/${APP_NAME}_${APP_VERSION}_amd64.${APP_EXT}
sudo gdebi -n /tmp/${APP_NAME}.${APP_EXT}
cd $HOME
rm -rf ${APP_NAME)*

# Install exa, a replacement for 'ls' command
APP_NAME=exa
APP_VERSION=0.7.0
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
APP_VERSION=1.2
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
APP_VERSION=6.2.3
APP_EXT=tar.gz
curl -o /tmp/${APP_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/readthebible/${APP_NAME}${APP_VERSION}.${APP_EXT}
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
sudo mv ${APP_NAME}${APP_VERSION} /var/www/html/${APP_NAME}
sudo chown -R www-data:www-data /var/www/html/${APP_NAME}
cd $HOME
rm -rf /tmp/${APP_NAME}*
