#!/bin/sh
#
# horde3 upgrade script for Lenny
#
# Thomas Schmitt
# <schmitt@lmz-bw.de>
# GPL v3
# 2010-02-25
#

echo
echo "Upgrading Horde3 ..."
HORDEUPGRADE=/usr/share/doc/horde3/examples/scripts/upgrades/3.1_to_3.2.mysql.sql
KRONOUPGRADE=/usr/share/doc/kronolith2/examples/scripts/upgrades/2.1_to_2.2.sql
MNEMOUPGRADE=/usr/share/doc/mnemo2/examples/scripts/upgrades/2.1_to_2.2.sql
NAGUPGRADE=/usr/share/doc/nag2/examples/scripts/upgrades/2.1_to_2.2.sql
TURBAUPGRADE=/usr/share/doc/turba2/examples/scripts/upgrades/2.1_to_2.2_add_sql_share_tables.sql

for i in $HORDEUPGRADE $KRONOUPGRADE $MNEMOUPGRADE $NAGUPGRADE $TURBAUPGRADE; do
 if [ ! -s "$i" ]; then
  echo "$i not found!"
  echo "Aborting Horde3 upgrade due to missing sql upgrade scripts!"
  echo "Upgrade your horde3 installation!"
  exit 1
 fi
done

# check for network
if ! ping -q -c2 pear.php.net; then
 echo "pear.php.net is not reachable! Try it again later!"
 exit 1
fi

# upgrade tables
for i in $HORDEUPGRADE $KRONOUPGRADE $MNEMOUPGRADE $NAGUPGRADE $TURBAUPGRADE; do
 mysql horde < $i
done

# upgrade pear and install necessary modules
pear upgrade-all
pear install DB MDB2 MDB2_Driver_mysql Auth_SASL Net_SMTP

