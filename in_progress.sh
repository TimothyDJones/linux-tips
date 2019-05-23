# Install Digital Clock 4 from Sourceforge
APP_NAME=digital_clock_4
APP_VERSION=4.5.5
if $(uname -m | grep '64'); then  # Check for 64-bit Linux kernel
	ARCH_TYPE=x64
else    # Otherwise use version for 32-bit kernel
	ARCH_TYPE=x86
fi
curl -o /tmp/${APP_NAME}.tar.xz -J -L https://superb-sea2.dl.sourceforge.net/project/digitalclock4/files/${APP_VERSION}/${APP_NAME}_${ARCH_TYPE}.tar.xz
cd /tmp
dtrx -n ${APP_NAME}.tar.xz
cd ${APP_NAME}
mv "Digital\ Clock\ 4" ${APP_NAME}
sudo mv ${APP_NAME} /opt
sudo ln -s /opt/${APP_NAME}/digital_clock.sh /usr/local/bin/digital_clock
# Create icon in menus
cat > /tmp/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Digital Clock 4
Comment=Nice desktop digital clock
GenericName=Clock
Exec=/opt/${APP_NAME}/digital_clock.sh
Icon=/opt/${APP_NAME}/digital_clock.svg
Type=Application
StartupNotify=true
Terminal=false
Categories=Utility;Clock;
Keywords=clock;time;date;
EOF
sudo mv /tmp/${APP_NAME}.desktop /usr/share/applications/
ln -s /usr/local/share/applications/digital_clock.desktop $HOME/.config/autostart/



# Install httpress HTTP response checker utility from source
APP_NAME=httpres
APP_VERSION=1.2
curl -o /tmp/${APP_NAME}.tar.bz2 -J -L https://cytranet.dl.sourceforge.net/project/${APP_NAME}/${APP_NAME}-${APP_VERSION}/${APP_NAME}-${APP_VERSION}-src.tar.bz2



sudo apt-get install -y libgtk-3-dev libgtksourceview-3.0-dev libuchardet-dev libxml2-dev
curl -o /tmp/gtef-2.0.1.tar.xz -J -L https://download.gnome.org/sources/gtef/2.0/gtef-2.0.1.tar.xz


# Install latest GTK+ and associated libraries from source
# Install prerequisite libraries
sudo apt-get install -y libmount-dev fam libfam-dev libffi-dev
cd /tmp
curl -O -J -L http://ftp.gnome.org/pub/gnome/sources/gtk+/3.22/gtk+-3.22.15.tar.xz
curl -O -J -L http://ftp.gnome.org/pub/gnome/sources/glib/2.52/glib-2.52.2.tar.xz
curl -O -J -L http://ftp.gnome.org/pub/gnome/sources/pango/1.40/pango-1.40.5.tar.xz
curl -O -J -L http://ftp.gnome.org/pub/gnome/sources/gdk-pixbuf/2.36/gdk-pixbuf-2.36.6.tar.xz
curl -O -J -L http://ftp.gnome.org/pub/gnome/sources/atk/2.24/atk-2.24.0.tar.xz
curl -O -J -L http://ftp.gnome.org/pub/gnome/sources/gobject-introspection/1.52/gobject-introspection-1.52.1.tar.xz
dtrx -n glib-2.52.2.tar.xz
cd glib-2.52.2
./configure && make && sudo make install
cd /tmp
dtrx -n gtk+-3.22.15.tar.xz
cd gtk+-3.22.15
./configure && make && sudo make install


# Install Quite Universal Circuit Simulator (QUCS) Qt-based GUI electronic circuit simulator from source
APP_NAME=QUCS
APP_GUI_NAME="Qt-based GUI electronic circuit simulator."
APP_VERSION=0.0.20-rc2
APP_EXT=tar.gz
FILE_NAME=${APP_NAME,,}-${APP_VERSION}
sudo apt-get install -y automake libtool libtool-bin gperf flex bison libqt4-dev libqt4-qt3support build-essential
# Install dependency ADMS, code generator for electronic device models
curl -o /tmp/adms-2.3.6.tar.gz -J -L https://downloads.sourceforge.net/mot-adms/adms-2.3.6.tar.gz
cd /tmp
dtrx -n /tmp/adms-2.3.6.tar.gz
cd /tmp/adms-2.3.6
./configure && make && sudo make install
curl -o /tmp/${FILE_NAME}.${APP_EXT} -J -L https://downloads.sourceforge.net/${APP_NAME,,}/${FILE_NAME}.${APP_EXT}
cd /tmp
dtrx -n /tmp/${FILE_NAME}.${APP_EXT}
cd /tmp/${FILE_NAME}/${APP_NAME,,}-0.0.20
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
