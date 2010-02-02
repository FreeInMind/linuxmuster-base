#
# paedML upgrade from 4.0 to 4.1
# main script
#
# 30.01.2010
# 
# Thomas Schmitt
# <schmitt@lmz-bw.de>
# GPL V3
#

# environment variables
. /usr/share/linuxmuster/config/dist.conf || exit 1
. $HELPERFUNCTIONS || exit 1
DHCPDYNTPLDIR=$DYNTPLDIR/03_dhcp3-server
BINDDYNTPLDIR=$DYNTPLDIR/04_bind9
LDAPDYNTPLDIR=$DYNTPLDIR/15_ldap

PKGREPOS="ftp.de.debian.org/debian/ \
          ftp.de.debian.org/debian-volatile/ \
          security.debian.org \
          pkg.lml.support-netz.de/paedml41-testing/"

# messages for config file headers
message1="##### Do not change this file! It will be overwritten!"
message2="##### This configuration file was automatically created by paedml41-upgrade!"
message3="##### Last Modification: `date`"

echo
echo "####################################################################"
echo "# paedML/openML Linux Distributions-Upgrade auf Debian 5.0.3 Lenny #"
echo "####################################################################"
echo
echo "Startzeit: `date`"
echo

echo "Teste Internetverbindung:"
cd /tmp
for i in $PKGREPOS; do
	echo -n "  * $i ... "
	wget -q http://$i ; RC="$?"
	rm index.html &> /dev/null
	if [ "$RC" = "0" ]; then
		echo "Ok!"
	else
		echo "keine Verbindung!"
		exit 1
	fi
done
echo

echo "Pruefe Setup-Variablen:"
for i in servername domainname internmask internsubrange imaging; do
    RET=`echo get linuxmuster-base/$i | debconf-communicate`
    RET=${RET#[0-9] }
    esc_spec_chars "$RET"
    if [ -z "$RET" ]; then
	if [ "$i" = "imaging" ]; then
		echo "set linuxmuster-base/imaging rembo" | debconf-communicate
		RET=rembo
		if grep -q ^imaging $NETWORKSETTINGS; then
			sed -e 's/^imaging=.*/imaging=rembo/' -i $NETWORKSETTINGS
		else
			echo "imaging=rembo" >> $NETWORKSETTINGS
		fi
	else
		echo "    Fatal! $i ist nicht gesetzt!"
		exit 1
	fi
    fi
    eval $i=$RET
    echo "  * $i=$RET"
    unset RET
done
internsub=`echo $internsubrange | cut -f1 -d"-"`
internbc=`echo $internsubrange | cut -f2 -d"-"`
serverip=10.$internsub.1.1
echo "  * serverip=$serverip"
if ! validip "$serverip"; then
	echo "    Fatal! serverip ist ungueltig!"
	exit 1
fi
ipcopip=10.$internsub.1.254
echo "  * ipcopip=$ipcopip"
if ! validip "$ipcopip"; then
	echo "    Fatal! ipcopip ist ungueltig!"
	exit 1
fi
broadcast=10.$internbc.255.255
echo "  * broadcast=$broadcast"
internalnet=10.$internsub.0.0
echo "  * internalnet=$internalnet"
basedn="dc=`echo $domainname|sed 's/\./,dc=/g'`"
echo "  * basedn=$basedn"

#######
# apt #
#######

cp /etc/apt/sources.list /etc/apt/sources.list.lenny-upgrade
cp /etc/apt/apt.conf /etc/apt/apt.conf.lenny-upgrade
cp /etc/apt/sources.list.lenny /etc/apt/sources.list
cp /etc/apt/apt.conf.lenny /etc/apt/apt.conf

# force apt to do an unattended upgrade
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export DEBCONF_TERSE=yes
export DEBCONF_NOWARNINGS=yes
echo 'DPkg::Options {"--force-confold";"--force-confdef";"--force-bad-verify";"--force-overwrite";};' > /etc/apt/apt.conf.d/99upgrade
echo 'APT::Get::AllowUnauthenticated "true";' >> /etc/apt/apt.conf.d/99upgrade
echo
echo "Aktualisiere Paketlisten ..."
aptitude update

#################
# configuration #
#################

echo
echo "Aktualisiere Konfiguration ..."

# ipcop: no more skas kernel
CONF=/etc/default/linuxmuster-ipcop
cp $CONF $CONF.lenny-upgrade
sed -e 's|^SKAS_KERNEL=.*|SKAS_KERNEL=no|' -i $CONF

# slapd
echo " slapd ..."
for i in /etc/ldap/slapd.conf /etc/default/slapd /var/lib/ldap/DB_CONFIG; do
 cp $i $i.lenny-upgrade
 if stringinstring slapd.conf $i; then
  ldapadminpw=`grep ^rootpw $i | awk '{ print $2 }'`
  sed -e "s/@@message1@@/${message1}/
	         s/@@message2@@/${message2}/
	         s/@@message3@@/${message3}/
	         s/@@basedn@@/${basedn}/g
	         s/@@ldappassword@@/${ldapadminpw}/" $LDAPDYNTPLDIR/`basename $i` > $i
  chown root:openldap ${i}*
  chmod 640 ${i}*
 else
  cp $STATICTPLDIR/$i $i
 fi
 chown openldap:openldap /var/lib/ldap -R
 chmod 700 /var/lib/ldap
 chmod 600 /var/lib/ldap/*
done

# apache2
echo " apache2 ..."
CONF=/etc/apache2/apache2.conf
cp $CONF $CONF.lenny-upgrade
cp $STATICTPLDIR/$CONF $CONF

# saslauthd
echo " saslauthd ..."
CONF=/etc/default/saslauthd
cp $CONF $CONF.lenny-upgrade
cp $STATICTPLDIR/$CONF $CONF

# dhcp
echo " dhcp ..."
CONF=/etc/dhcp3/dhcpd.conf
cp $CONF $CONF.lenny-upgrade
sed -e "s/@@servername@@/${servername}/g
        s/@@domainname@@/${domainname}/g
        s/@@serverip@@/${serverip}/g
        s/@@ipcopip@@/${ipcopip}/g
        s/@@broadcast@@/${broadcast}/g
        s/@@internmask@@/${internmask}/g
        s/@@internsub@@/${internsub}/g
        s/@@internalnet@@/${internalnet}/g" $DHCPDYNTPLDIR/`basename $CONF`.$imaging > $CONF

# bind9
echo " bind9 ..."
for i in db.10 db.linuxmuster named.conf.linuxmuster; do
 CONF=/etc/bind/$i
 cp $CONF $CONF.lenny-upgrade
 sed -e "s/@@servername@@/${servername}/g
         s/@@domainname@@/${domainname}/g
         s/@@serverip@@/${serverip}/g
         s/@@ipcopip@@/${ipcopip}/g
         s/@@internsub@@/${internsub}/g" $BINDDYNTPLDIR/$i > $CONF
done
rm /etc/bind/*.jnl

################
# dist-upgrade #
################

echo
echo "DIST-UPGRADE ..."
#SOPHOPKGS=`dpkg -l | grep sophomorix | grep ^i | awk '{ print $2 }'`
#apt-get -y remove $SOPHOPKGS
aptitude -y install apt-utils tasksel debian-archive-keyring dpkg locales
aptitude update
aptitude -y install postgresql postgresql-8.3 postgresql-client-8.3
# handle postgresql update
if ps ax | grep -q postgresql/8.3; then
 /etc/init.d/postgresql-8.3 stop
 pg_dropcluster 8.3 main
fi
if ! ps ax | grep -q postgresql/8.1; then
 /etc/init.d/postgresql-8.1 start
fi
pg_upgradecluster 8.1 main
update-rc.d -f postgresql-7.4 remove
update-rc.d -f postgresql-8.1 remove
aptitude -y dist-upgrade
aptitude -y dist-upgrade
aptitude -y dist-upgrade
aptitude -y purge avahi-daemon
#aptitude -y install $SOPHOPKGS
linuxmuster-task --unattended --install=common
linuxmuster-task --unattended --install=server
[ "$imaging" = "linbo" ] && linuxmuster-task --unattended --install=imaging-$imaging

##########
# horde3 #
##########

echo
echo "horde3 ..."
CONF=/etc/php5/conf.d/paedml.ini
cp $CONF $CONF.lenny-upgrade
cp $STATICTPLDIR/$CONF $CONF
HORDEUPGRADE=/usr/share/doc/horde3/examples/scripts/upgrades/3.1_to_3.2.mysql.sql
TURBAUPGRADE=/usr/share/doc/turba2/examples/scripts/upgrades/2.1_to_2.2_add_sql_share_tables.sql
mysql horde < $HORDEUPGRADE
mysql horde < $TURBAUPGRADE
pear upgrade-all
pear install DB MDB2 MDB2_Driver_mysql Auth_SASL Net_SMTP
aptitude -y install php5-tidy

# webmin
CONF=/etc/webmin/config
cp $CONF $CONF.lenny-upgrade
cp $STATICTPLDIR/$CONF $CONF
/etc/init.d/webmin restart

# remove stuff only needed for upgrade
rm -f /etc/apt/apt.conf.d/99upgrade

# final stuff
import_workstations

echo
echo "Beendet um `date`!"

