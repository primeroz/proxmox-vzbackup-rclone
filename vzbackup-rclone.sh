#!/bin/bash
# ./vzbackup-rclone.sh rehydrate YYYY/MM/DD file_name_encrypted.bin

############ /START CONFIG
MAX_AGE=30       # This is the age in days to keep local backup copies. Local backups older than this are deleted.
CLOUD_MAX_AGE=30 # This is the age in days to keep local backup copies. Local backups older than this are deleted.
_rclone_common_options="-v --stats=60s --transfers=4 --checkers=8"
_rclone_b2_options="--fast-list --b2-chunk-size 50M --b2-memory-pool-use-mmap"
_rclone_gdrive_options="--drive-chunk-size=32M"
############ /END CONFIG

############ /START HOOK CONFIGS
COMMAND=${1}
MODE=${2}
VMID=${3}
_vmtype=${VMTYPE}
_dumpdir=${DUMPDIR}
_storeid=${STOREID}
_hostname=${HOSTNAME} # Will depend on the phase / command
_target=${TARGET}     # When VMTYPE == qemu TARGET is what we need to copy
if [ -z ${TARGET+x} ]; then
	tarfile=${TARFILE}
else
	tarfile=${TARGET}
fi
############ /END HOOK CONFIGS

_bdir="${DUMPDIR}"
timepath="$(date +%Y-%m-%d)"

# TODO: Sort this one out , possibly split in separate script
if [[ ${COMMAND} == 'rehydrate' ]]; then
	rehydrate=${2} #enter the date you want to rehydrate in the following format: YYYY/MM/DD
	if [ ! -z "${3}" ]; then
		CMDARCHIVE=$(echo "/${3}" | sed -e 's/\(.bin\)*$//g')
	fi
	#echo "Please enter the date you want to rehydrate in the following format: YYYY/MM/DD"
	#echo "For example, today would be: $timepath"
	#read -p 'Rehydrate Date => ' rehydrate

	#rclone --config /root/.config/rclone/rclone.conf \
	#	--drive-chunk-size=32M $B2_OPTIONS copy backup_crypt:/$rehydrate$CMDARCHIVE $dumpdir \
	#	-v --stats=60s --transfers=16 --checkers=16
fi

# Disabled since i have retention through proxmox backups ?
if [[ ${COMMAND} == 'job-start' ]]; then
	#echo "Deleting backups older than $MAX_AGE days."
	#find $_dumpdir -type f -mtime +$MAX_AGE -exec /bin/rm -f {} \;
fi

# TODO: Split to support multiple types
if [[ ${COMMAND} == 'backup-end' ]]; then
	_src_files_copy=()

	if [[ ${_vmtype} == 'qemu' ]]; then
		_src_files_copy+=("${_target}")
		_src_files_copy+=("${_target}.notes")
	fi

	echo "Backing up ${_target} to remote storage"
	for file in "${_src_files_copy[@]}"; do
		echo "Processing file: $file"
		rclone --config /root/.config/rclone/rclone.conf ${_rclone_common_options} ${_rclone_b2_options} \
			copy ${file} backup_crypt:/$timepath
	done
fi

if [[ ${COMMAND} == 'job-end' || ${COMMAND} == 'job-abort' ]]; then
	echo "Backing up main PVE configs"
	_tdir=${TMP_DIR:-/var/tmp}
	_tdir=$(mktemp -d $_tdir/proxmox-XXXXXXXX)

	function clean_up {
		echo "Cleaning up"
		rm -rf $_tdir
	}

	trap clean_up EXIT

	_now=$(date +%Y-%m-%d.%H.%M.%S)
	_HOSTNAME=$(hostname -f)
	_filename1="$_tdir/proxmoxetc.$_now.tar"
	_filename2="$_tdir/proxmoxpve.$_now.tar"
	_filename3="$_tdir/proxmoxroot.$_now.tar"
	_filename4="$_tdir/proxmox_backup_"$_HOSTNAME"_"$_now".tar.gz"

	echo "Tar files"
	# copy key system files
	tar --warning='no-file-ignored' -cPf "$_filename1" /etc/.
	tar --warning='no-file-ignored' -cPf "$_filename2" /var/lib/pve-cluster/.
	tar --warning='no-file-ignored' -cPf "$_filename3" /root/.

	echo "Compressing files"
	# archive the copied system files
	tar -cvzPf "$_filename4" $_tdir/*.tar

	# copy config archive to backup folder
	#mkdir -p $rclonedir
	cp -v $_filename4 $_bdir/
	echo "rcloning $_filename4"

	rclone --config /root/.config/rclone/rclone.conf ${_rclone_common_options} ${_rclone_b2_options} \
		copy "${_filename4}" backup_crypt:/$timepath

	echo "Deleting Cloud files older than $CLOUD_MAX_AGE"
	rclone --config /root/.config/rclone/rclone.conf ${_rclone_common_options} ${_rclone_b2_options} \
		delete --min-age ${MAX_CLOUD_AGE}d backup_crypt:/
fi
