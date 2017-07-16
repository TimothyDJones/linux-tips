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
