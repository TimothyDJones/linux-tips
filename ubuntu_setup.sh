#!/bin/sh

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

# Install Firejail and Firetools utilities for running applications
# in isolated memory space.
cd /var/tmp
curl -o firejail.deb -A "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" -J -L https://superb-sea2.dl.sourceforge.net/project/firejail/firejail/firejail_0.9.44.8_1_${KERNEL_TYPE}.deb
curl -o firetools.deb -A "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" -J -L https://cytranet.dl.sourceforge.net/project/firejail/firetools/firetools_0.9.46_1_${KERNEL_TYPE}.deb
sudo gdebi -n firejail.deb   # '-n' is non-interactive mode for gdebi
sudo gdebi -n firetools.deb   # '-n' is non-interactive mode for gdebi
rm -f firejail.deb firetools.deb
cd $HOME

# Install Stacer Linux monitoring tool
# Must download specific version, because unable to get 'latest' from Sourceforge to work.
cd $HOME/Downloads
curl -o stacer.deb -A "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" -J -L https://pilotfiber.dl.sourceforge.net/project/stacer/v1.0.6/Stacer_1.0.6_${KERNEL_TYPE}.deb
sudo gdebi -n stacer.deb   # '-n' is non-interactive mode for gdebi
rm -f stacer.deb
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
curl -o /tmp/cudatext.deb -J -L https://cytranet.dl.sourceforge.net/project/cudatext/release/Linux/cudatext_1.8.1.0-1_gtk2_amd64.deb
sudo gdebi -n /tmp/cudatext.deb
rm -f /tmp/cudatext.deb

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
source /etc/os-release
curl -o /tmp/copyq.deb -J -L https://ayera.dl.sourceforge.net/project/copyq/copyq-3.0.0/Linux/copyq_3.0.0_Ubuntu_${VERSION_ID}_${KERNEL_TYPE}.deb
sudo gdebi -n /tmp/copyq.deb
ln -s /usr/local/share/applications/copyq.desktop $HOME/.config/autostart/  # Configure CopyQ to autostart on system launch
rm -f /tmp/copyq.deb

# Install Steel Bank Common Lisp (SBLC) from Sourceforge
sudo apt-get install -y sbcl   # Current packaged version of SBCL required to build the updated version from source
curl -o /tmp/sblc.tar.gz -J -L https://superb-sea2.dl.sourceforge.net/project/sbcl/sbcl/1.3.16/sbcl-1.3.16-source.tar.bz2
cd /tmp
dtrx -n /tmp/sbcl.tar.gz
cd /tmp/sbcl/sbcl-1.3.16
sh make.sh
INSTALL_DIR=/usr/local sudo sh install.sh
cd $HOME
rm -rf /tmp/sbcl*

# Install Otter Browser from Sourceforge (from source)
sudo apt-get install -y qt5-default libqt5multimedia5 qtmultimedia5-dev libqt5xmlpatterns5-dev libqt5webkit5-dev   # Qt5 development packages needed to build from source
curl -o /tmp/otter-browser.tar.gz -J -L https://iweb.dl.sourceforge.net/project/otter-browser/otter-browser-weekly172/otter-browser-0.9.91-dev172.tar.bz2
cd /tmp
dtrx -n /tmp/otter-browser.tar.gz
cd /tmp/otter-browser/otter-browser-0.9.91-dev172
mkdir build && cd build
cmake .. && make && sudo make install
cd $HOME
rm -rf /tmp/otter-browser*

# Install MyNotes simple "sticky notes" tool
sudo apt-get install -y python3-tk tk-tktray  python3-pip python3-setuptools python3-wheel  # python3-ewmh
sudo -H pip3 install --upgrade pip  # Upgrade to latest version of pip for Python 3
sudo -H pip3 install ewmh
curl -o /tmp/mynotes.tar.gz -J -L https://iweb.dl.sourceforge.net/project/my-notes/1.0.0/mynotes-1.0.0.tar.gz
cd /tmp
dtrx -n /tmp/mynotes.tar.gz
cd /tmp/mynotes/mynotes-1.0.0
sudo -H python3 setup.py install
cd $HOME
rm -rf /tmp/mynotes*

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
sudo apt-get install -y tcl8.6 tk8.6 tclx8.4 tcllib tklib tkdnd expect tcl-tls  # Install required packages
curl -o /tmp/tke.tgz -J -L https://iweb.dl.sourceforge.net/project/tke/3.0/tke-3.0.tgz
cd /tmp
dtrx -n /tmp/tke.tgz
cd /tmp/tke/tke-3.0
sudo tclsh8.6 install.tcl
cd $HOME
rm -rf /tmp/tke*

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
curl -o /tmp/joe.tar.gz -J -L https://cytranet.dl.sourceforge.net/project/joe-editor/JOE%20sources/joe-4.4/joe-4.4.tar.gz
cd /tmp
dtrx -n /tmp/joe.tar.gz
cd /tmp/joe/joe-4.4
./configure && make && sudo make install
cd $HOME
rm -rf /tmp/joe*

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
APP_VERSION=3.0.9
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

