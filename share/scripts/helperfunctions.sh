# linuxmuster shell helperfunctions

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# source network settings
[ -f "$NETWORKSETTINGS" ] && . $NETWORKSETTINGS

# lockfile
lockflag=/var/lock/.linuxmuster.lock

# date & time
[ -e /bin/date ] && DATETIME=`date +%y%m%d-%H%M%S`


####################
# common functions #
####################

# parse command line options
getopt() {
  until [ -z "$1" ]
  do
    if [ ${1:0:2} = "--" ]
    then
        tmp=${1:2}               # Strip off leading '--' . . .
        parameter=${tmp%%=*}     # Extract name.
        value=${tmp##*=}         # Extract value.
        eval $parameter=$value
#        [ -z "$parameter" ] && parameter=yes
    fi
    shift
  done
}

# cancel on error, $1 = Message, $2 logfile
cancel() {
  echo "$1"
  [ -e "$lockflag" ] && rm -f $lockflag
  [ -n "$2" ] && echo "$DATETIME: $1" >> $2
  exit 1
}

# check lockfiles, wait a minute whether it will be freed
checklock() {
  if [ -e "$lockflag" ]; then
    echo "Found lockfile!"
    n=0
    while [[ $n -lt $TIMEOUT ]]; do
      remaining=$(($(($TIMEOUT-$n))*10))
      echo "Remaining $remaining seconds to wait ..."
      sleep 1
      if [ ! -e "$lockflag" ]; then
        touch $lockflag || return 1
        echo "Lockfile released!"
        return 0
      fi
      let n+=1
    done
    echo "Timed out! Exiting!"
    return 1
  else
    touch $lockflag || return 1
  fi
  return 0
}


# test if variable is an integer
isinteger () {
  [ $# -eq 1 ] || return 1

  case $1 in
  *[!0-9]*|"") return 1;;
            *) return 0;;
  esac
} # isinteger


##########################
# check parameter values #
##########################

# check if user is teacher
check_teacher() {
  if `id $1 | grep -qw $TEACHERSGROUP`; then
    return 0
  else
    return 1
  fi
}

# check if user is teacher
check_admin() {
  if `id $1 | grep -qw $DOMADMINS`; then
    return 0
  else
    return 1
  fi
}

# check for valid group, group members and if teacher is set, for teacher membership
check_group() {
  unset RET
  group=$1
  teacher=$2

  gidnr=`smbldap-groupshow $group | grep gidNumber: | awk '{ print $2 }'`
  [ -z "$gidnr" ] && return 1
  [ "$gidnr" -lt 10000 ] && return 1

  # fetch group members
  if get_group_members $group; then
    members=$RET
  else
    return 1
  fi

  # cancel if group has no members
  [ -z "$members" ] && return 1

  # check if teacher is in group
  if [ -n "$teacher" ]; then
    if ! echo "$members" | grep -qw $teacher; then
      return 1
    fi
  fi

  return 0
}

# check valid domain name
validdomain() {
  if (expr match "$1" '\([a-z0-9-]\+\(\.[a-z0-9-]\+\)\+$\)') &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# check valid ip
validip() {
  if (expr match "$1"  '\(\([1-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)\.\([0-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)\.\([0-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)\.\([1-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)$\)') &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# test valid mac address syntax
validmac() {
  [ -z "$1" ] && return 1
  [ `expr length $1` -ne "17" ] && return 1
  if (expr match "$1" '\([a-fA-F0-9-][a-fA-F0-9-]\+\(\:[a-fA-F0-9-][a-fA-F0-9-]\+\)\+$\)') &> /dev/null; then
    return 0
  else
    return 1
  fi
}


#################
# mysql related #
#################

# create mysql database user
create_mysql_user() {
  username=$1
  password=$2
  mysql <<EOF
USE mysql;
REPLACE INTO user (host, user, password)
    VALUES (
        'localhost',
        '$username',
        PASSWORD('$password')
);
EOF
}

# removes a mysql user
drop_mysql_user() {
  username=$1
  mysql <<EOF
USE mysql;
DELETE FROM user WHERE user='$username';
DELETE FROM db WHERE user='$username';
DELETE FROM columns_priv WHERE user='$username';
DELETE FROM tables_priv WHERE user='$username';
FLUSH PRIVILEGES;
EOF
}

# create a mysql database
create_mysql_db() {
  if mysqladmin create $1; then
    return 0
  else
    return 1
  fi
}

# create a mysql database and grant privileges to a user
drop_mysql_db() {
  if mysqladmin -f drop $1; then
    return 0
  else
    return 1
  fi
}

# grant privileges to a database to a specified user
grant_mysql_privileges() {
  dbname=$1
  username=$2
  writeable=$3
  mysql <<EOF
USE mysql;
REPLACE INTO db (host, db, user, select_priv, insert_priv, update_priv, references_priv, lock_tables_priv,
                 delete_priv, create_priv, drop_priv, index_priv, alter_priv, create_tmp_table_priv)
    VALUES (
        'localhost',
        '$dbname',
        '$username',
        'Y', '$writeable', '$writeable', '$writeable', '$writeable', '$writeable',
        '$writeable', '$writeable', '$writeable', '$writeable', '$writeable'
);
FLUSH PRIVILEGES;
EOF
}

# returns 0 if $username is a mysql user
check_mysql_user() {
  username=$1
  get_dbusers || return 1
  if echo $RET | grep -qw $username; then
    return 0
  else
    return 1
  fi
}


#######################
# workstation related #
#######################

# extract ip address from file $WIMPORTDATA
get_ip() {
  unset RET
  [ -f "$WIMPORTDATA" ] || return 1
  RET=`grep -v ^# $WIMPORTDATA | grep -w -m1 $1 | awk -F\; '{ print $5 }' -` &> /dev/null
  return 0
}

# extract mac address from file $WIMPORTDATA
get_mac() {
  unset RET
  [ -f "$WIMPORTDATA" ] || return 1
  RET=`grep -v ^# $WIMPORTDATA | grep -w -m1 $1 | awk -F\; '{ print $4 }' -` &> /dev/null
  return 0
}

# extract hostname from file $WIMPORTDATA
get_hostname() {
  unset RET
  [ -f "$WIMPORTDATA" ] || return 1
  RET=`grep -v ^# $WIMPORTDATA | grep -w -m1 $1 | awk -F\; '{ print $2 }' -` &> /dev/null
  return 0
}

# extract hostname from file $WIMPORTDATA
get_room() {
  unset RET
  [ -f "$WIMPORTDATA" ] || return 1
  RET=`grep -v ^# $WIMPORTDATA | grep -m1 $1 | awk -F\; '{ print $1 }' -` &> /dev/null
  return 0
}

# needed by internet & intranet on off scripts
get_maclist() {
  # parse maclist
  if [ -n "$maclist" ]; then

    n=0
    OIFS=$IFS
    IFS=","
    for i in $maclist; do
      if validmac $i; then
        mac[$n]=$i
      else
        continue
      fi
      let n+=1
    done
    IFS=$OIFS
    nr_of_macs=$n
    [[ $nr_of_macs -eq 0 ]] && cancel "No valid mac addresses found!"

  else # parse hostlist

    n=0
    OIFS=$IFS
    IFS=","
    for i in $hostlist; do
      host[$n]=$i
      let n+=1
    done
    IFS=$OIFS
    nr_of_hosts=$n
    [[ $nr_of_hosts -eq 0 ]] && cancel "No hostnames found!"

    n=0; m=0
    while [[ $n -lt $nr_of_hosts ]]; do
      get_mac ${host[$n]} || cancel "Read failure! Cannot determine mac address!"
      if validmac $RET; then
        mac[$m]=$RET
        let m+=1
      fi
      let n+=1
    done
    nr_of_macs=$m
    [[ $nr_of_macs -eq 0 ]] && cancel "No mac addresses found!"

  fi

  return 0
}


#######################
# IPCop communication #
#######################

# check if urlfilter is active
check_urlfilter() {
  # get advanced proxy settings
  get_ipcop /var/ipcop/proxy/advanced/settings $CACHEDIR/proxy.advanced.settings || cancel "Cannot download proxy advanced settings!"
  . $CACHEDIR/proxy.advanced.settings || cancel "Cannot read $CACHEDIR/proxy.advanced.settings!"
  rm -f $CACHEDIR/proxy.advanced.settings
  [ "$ENABLE_FILTER" = "on" ] || return 1
  return 0
}

# execute a command on ipcop
exec_ipcop() {
  ssh -p 222 root@$ipcopip $* &> /dev/null || return 1
  return 0
}

# fetch file from ipcop
get_ipcop() {
  scp -P 222 root@$ipcopip:$1 $2 &> /dev/null || return 1
  return 0
}

# upload file to ipcop
put_ipcop() {
  scp -P 222 $1 root@$ipcopip:$2 &> /dev/null || return 1
  return 0
}


###############
# svn related #
###############

# create chora2 configuration
create_chora_conf() {
  check_empty_dir $SVNROOT
  if [ "$RET" = "0" ]; then
    rm -f $CHORASOURCES &> /dev/null
  else
    cd $SVNROOT
    echo "<?php" > $CHORASOURCES
    for i in *; do
      if [ -d "$i" ]; then
        echo "\$sourceroots['$i'] = array(" >> $CHORASOURCES
        echo "  'name' => '$i'," >> $CHORASOURCES
        echo "  'location' => 'file://$SVNROOT/$i'," >> $CHORASOURCES
        echo "  'title' => 'SVN Repository $i'," >> $CHORASOURCES
        echo "  'type' => 'svn'," >> $CHORASOURCES
        echo ");" >> $CHORASOURCES
      fi
    done
  fi
}


#################
# nic setup     #
#################
discover_nics() {

	n=0
	# fetch all interfaces and their macs from /sys
	for i in /sys/class/net/eth* /sys/class/net/wlan* /sys/class/net/intern /sys/class/net/extern /sys/class/net/dmz; do

		[ -e $i/address ] || continue
		address[$n]=`head -1 $i/address` || continue

		if [ `expr length ${address[$n]}` -ne "17" ]; then
			continue
		else

			toupper ${address[$n]}
			address[$n]=$RET
			id=`ls -1 -d $i/device/driver/0000:* 2> /dev/null`
			id=`echo $id | awk '{ print $1 }' -`
			id=${id#$i/device/driver/}

			if [ -n "$id" ]; then

				tmodel=`lspci | grep $id | awk -F: '{ print $4 $5 }' -`
				tmodel=`expr "$tmodel" : '[[:space:]]*\(.*\)[[:space:]]*$'`
				tmodel=${tmodel// /_}
				model[$n]=${tmodel:0:38}

			else

				model[$n]="Unrecognized Ethernet Controller Device"

			fi

		fi

		let n+=1

	done
	nr_of_nics=$n

} # discover_nics


create_nic_choices() {

	n=0
	unset NIC_CHOICES
	while [ $n -lt $nr_of_nics ]; do
		typ[$n]=""
		if [ "${address[$n]}" = "$mac_extern" ]; then
			typ[$n]=extern
		elif [ "${address[$n]}" = "$mac_intern" ]; then
			typ[$n]=intern
		elif [ "${address[$n]}" = "$mac_wlan" ]; then
			typ[$n]=wlan
		elif [ "${address[$n]}" = "$mac_dmz" ]; then
			typ[$n]=dmz
		fi
		menu[$n]="${model[$n]} ${address[$n]} ${typ[$n]}"
		strip_spaces "${menu[$n]}"
		menu[$n]="$RET"
		if [ -n "$NIC_CHOICES" ]; then
			NIC_CHOICES="${NIC_CHOICES}, ${menu[$n]}"
		else
			NIC_CHOICES="${menu[$n]}"
			NIC_DEFAULT=$NIC_CHOICES
		fi
		let n+=1
	done
	[ "$fwconfig" = "integrated" ] && NIC_CHOICES="$NIC_CHOICES, , Fertig, , Abbrechen"

} # create_nic_choices


create_if_choices() {

	n=0
	IF_CHOICES="extern,intern,wlan,dmz"
	while [ $n -lt $nr_of_nics ]; do
		if [[ -n "${typ[$n]}" && "$CURTYP" != "${typ[$n]}" ]]; then
			IF_CHOICES=${IF_CHOICES/${typ[$n]}/}
			IF_CHOICES=${IF_CHOICES%,}
			IF_CHOICES=${IF_CHOICES#,}
			IF_CHOICES=${IF_CHOICES//,,/,}
		fi
		let n+=1
	done
	IF_CHOICES=${IF_CHOICES/extern/extern (ROT)}
	IF_CHOICES=${IF_CHOICES/intern/intern (GRUEN)}
	IF_CHOICES=${IF_CHOICES/wlan/wlan (BLAU)}
	IF_CHOICES=${IF_CHOICES/dmz/dmz (ORANGE)}
	IF_CHOICES=${IF_CHOICES//,/, }
	IF_CHOICES="$IF_CHOICES, , keine Zuordnung"
	IF_DEFAULT=`echo $IF_CHOICES | cut -f1 -d,`

} # create_if_choices

delete_mac() {

	if [ "$CURMAC" = "$mac_extern" ]; then
		unset mac_extern
		db_set linuxmuster-base/mac_extern "" || true
	elif [ "$CURMAC" = "$mac_intern" ]; then
		unset mac_intern
		db_set linuxmuster-base/mac_intern "" || true
	elif [ "$CURMAC" = "$mac_wlan" ]; then
		unset mac_wlan
		db_set linuxmuster-base/mac_wlan "" || true
	elif [ "$CURMAC" = "$mac_dmz" ]; then
		unset mac_dmz
		db_set linuxmuster-base/mac_dmz "" || true
	fi

} # delete_mac

assign_nics() {

	# first fetch all nics and macs from the system
	nr_of_nics=0
	discover_nics

	# no nic no fun
	if [ $nr_of_nics -lt 1 ]; then
		echo " Sorry, no NIC found! Aborting!"
		exit 1
	fi

	# at least two nics required for integrated firewall
	if [[ "$fwconfig" = "integrated" && $nr_of_nics -lt 2 ]]; then
		echo "Only one NIC found! You need at least 2!"
		echo "Aborting installation!"
		exit 1
	fi

	# there is only an internal interface in case of dedicated firewall
	if [ "$fwconfig" = "dedicated" ]; then

		db_set linuxmuster-base/mac_extern "" || true
		db_set linuxmuster-base/mac_intern "" || true
		db_set linuxmuster-base/mac_wlan "" || true
		db_set linuxmuster-base/mac_dmz "" || true
		# no questions necessary in this case
		if [ $nr_of_nics -eq 1 ]; then
			db_set linuxmuster-base/mac_intern ${address[0]} || true
			return 0
		fi

		NIC_DESC="Welche Netzwerkkarte ist mit dem internen Netz verbunden? \
			  Waehlen Sie die entsprechende Karte mit den Pfeiltasten aus. \
			  Bestaetigen Sie die Auswahl mit ENTER."

	else

		db_get linuxmuster-base/mac_extern || true
		mac_extern=$RET
		db_get linuxmuster-base/mac_intern || true
		mac_intern=$RET
		db_get linuxmuster-base/mac_wlan || true
		mac_wlan=$RET
		db_get linuxmuster-base/mac_dmz || true
		mac_dmz=$RET

		NIC_DESC="Ordnen Sie die Netzwerkkarten den Interfaces extern, intern und ggf. wlan und dmz zu. \
			  Es muessen mindestens ein externes und ein internes Interface definiert sein. \
		          Waehlen Sie mit den Pfeiltasten eine Netzwerkkarte fuer die Zuordnung aus. \
			  Bestaetigen Sie die Auswahl mit ENTER. Beenden Sie die Zuordnung mit <Fertig>."

	fi

	db_subst linuxmuster-base/nicmenu nic_desc $NIC_DESC

	while true; do

		create_nic_choices
		db_fset linuxmuster-base/nicmenu seen false
		db_subst linuxmuster-base/nicmenu nic_choices $NIC_CHOICES

		unset choice
		while [ -z "$choice" ]; do
			db_set linuxmuster-base/nicmenu $NIC_DEFAULT || true
			db_input $PRIORITY linuxmuster-base/nicmenu || true
			db_go
			db_get linuxmuster-base/nicmenu || true
			choice="$RET"
		done

		[ "$choice" = "Abbrechen" ] && exit 1

		if [ "$choice" = "Fertig" ]; then
			if [[ -n "$mac_extern" && -n "$mac_intern" ]]; then
				break
			else
				continue
			fi
		fi

		CURMAC=`echo "$choice" | cut -f2 -d" "`
		CURTYP=`echo "$choice" | cut -f3 -d" "`

		if [ "$fwconfig" = "integrated" ]; then
			create_if_choices
			db_fset linuxmuster-base/ifmenu seen false
			db_subst linuxmuster-base/ifmenu if_choices $IF_CHOICES
			db_subst linuxmuster-base/ifmenu if_desc $choice
			unset iftype
			while [ -z "$iftype" ]; do
				db_set linuxmuster-base/ifmenu $IF_DEFAULT || true
				db_input $PRIORITY linuxmuster-base/ifmenu || true
				db_go
				db_get linuxmuster-base/ifmenu || true
				iftype=`echo "$RET" | cut -f1 -d" "`
			done
			delete_mac
		else
			iftype=intern
		fi

		case $iftype in

			extern)
				mac_extern=$CURMAC
				db_set linuxmuster-base/mac_extern $mac_extern || true
				;;

			intern)
				mac_intern=$CURMAC
				db_set linuxmuster-base/mac_intern $mac_intern || true
				[ "$fwconfig" = "dedicated" ] && return 0
				;;

			wlan)
				mac_wlan=$CURMAC
				db_set linuxmuster-base/mac_wlan $mac_wlan || true
				;;

			dmz)
				mac_dmz=$CURMAC
				db_set linuxmuster-base/mac_dmz $mac_dmz || true
				;;

			*)
				;;

		esac

	done

} # assign_nics


#################
# miscellanious #
#################

# get group members from ldab db
get_group_members() {
  unset RET
  group=$1
  RET=`psql -U ldap -d ldap -t -c "select uid from memberdata where adminclass = '$group' or gid = '$group';"`
}

# check if group is a project
check_project() {
  unset RET
  group=$1
  RET=`psql -U ldap -d ldap -t -c "select gid from projectdata where gid = '$group';"`
  strip_spaces $RET
  [ "$RET" = "$group" ] && return 0
  return 1
}

# stripping trailing and leading spaces
strip_spaces() {
  unset RET
  RET=`expr "$1" : '[[:space:]]*\(.*\)[[:space:]]*$'`
  return 0
}

# test if string is in string
stringinstring() {
  case "$2" in *$1*) return 0;; esac
  return 1
}

# checking if directory is empty, in that case it returns 0
check_empty_dir() {
  RET=$(ls -A1 $1 2>/dev/null | wc -l)
}

# check valid string without special characters
check_string() {
  if (expr match "$1" '\([a-z0-9-_]\+$\)') &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# converting string to lower chars
tolower() {
  unset RET
  [ -z "$1" ] && return 1
  RET=`echo $1 | tr A-Z a-z`
}

# converting string to lower chars
toupper() {
  unset RET
  [ -z "$1" ] && return 1
  RET=`echo $1 | tr a-z A-Z`
}
