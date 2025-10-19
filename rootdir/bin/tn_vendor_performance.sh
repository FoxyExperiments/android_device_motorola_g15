#!/vendor/bin/sh

function configure_zram_parameters() {
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	# Zram disk - 75% for < 2GB devices .
	# For >2GB Non-Go devices, size = 50% of RAM size. Max 4GB.

	let RamSizeGB="( $MemTotal / 1048576 ) + 1"
	diskSizeUnit=M
	if [ $RamSizeGB -le 2 ]; then
		let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
	else
		let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
	fi

	if [ $zRamSizeMB -gt 4096 ]; then
		let zRamSizeMB=4096
	fi

	# And enable lz4 zram compression for Go targets.
	low_ram=`getprop ro.config.low_ram`
	if [ "$low_ram" == "true" ]; then
		echo lz4 > /sys/block/zram0/comp_algorithm
	fi

	if [ -f /sys/block/zram0/disksize ]; then
		if [ -f /sys/block/zram0/use_dedup ]; then
			echo 1 > /sys/block/zram0/use_dedup
		fi
		echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize

		# ZRAM may use more memory than it saves if
		# SLAB_STORE_USER debug option is enabled.
		if [ -e /sys/kernel/slab/zs_handle ]; then
			echo 0 > /sys/kernel/slab/zs_handle/store_user
		fi
		if [ -e /sys/kernel/slab/zspage ]; then
			echo 0 > /sys/kernel/slab/zspage/store_user
		fi

		mkswap /dev/block/zram0
		swapon /dev/block/zram0 -p 32758
	fi
}

function configure_read_ahead_kb_values() {
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc -e sd)
	# dmpts holds below read_ahead_kb nodes if exists:
	# /sys/block/dm-0/queue/read_ahead_kb to /sys/block/dm-10/queue/read_ahead_kb
	# /sys/block/sda/queue/read_ahead_kb to /sys/block/sdh/queue/read_ahead_kb

	# Set 128 for <= 4GB &
	# set 512 for >= 5GB targets.
	if [ $MemTotal -le 4194304 ]; then
		ra_kb=128
	else
		ra_kb=512
	fi
	for dm in $dmpts; do
		if [ `cat $(dirname $dm)/../removable` -eq 0 ]; then
			echo $ra_kb > $dm
		fi
	done
	if [ -f /sys/block/mmcblk0/bdi/read_ahead_kb ]; then
		echo $ra_kb > /sys/block/mmcblk0/bdi/read_ahead_kb
	fi
	if [ -f /sys/block/mmcblk0rpmb/bdi/read_ahead_kb ]; then
		echo $ra_kb > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
	fi
}


function taskset_process_cpu() {
  #cpu taskset core
  taskset -ap 3f `pidof -x kswapd0`
}

function configure_memory_parameters() {
	#configure_zram_parameters
	configure_read_ahead_kb_values
	taskset_process_cpu

	# Disable periodic kcompactd wakeups. We do not use THP, so having many
	# huge pages is not as necessary.
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}
	let RamSizeGB="( $MemTotal / 1048576 ) + 1"

	echo 0 > /proc/sys/vm/compaction_proactiveness

	echo 8700 > /proc/sys/vm/min_free_kbytes
	echo 200 > /proc/sys/vm/watermark_scale_factor

        # keep these values of swappiness to be same
        echo 160 > /dev/memcg/memory.swappiness
        echo 160 > /dev/memcg/apps/memory.swappiness
        echo 160 > /dev/memcg/system/memory.swappiness
        echo 160 > /proc/sys/vm/swappiness

	echo 5 > /proc/sys/vm/dirty_background_ratio
	echo 20 > /proc/sys/vm/dirty_ratio

	# -ge:	>=	大于等于
	#if [ $RamSizeGB -ge 8 ]; then
	#elif [ $RamSizeGB -ge 4 ]; then
	#elif [ $RamSizeGB -ge 2 ]; then	
	#else
	#fi	

	# Disable wsf for all targets beacause we are using efk.
	# wsf Range : 1..1000 So set to bare minimum value 1.

	#Set per-app max kgsl reclaim limit and per shrinker call limit
	if [ -f /sys/class/kgsl/kgsl/page_reclaim_per_call ]; then
		echo 38400 > /sys/class/kgsl/kgsl/page_reclaim_per_call
	fi
	if [ -f /sys/class/kgsl/kgsl/max_reclaim_limit ]; then
		echo 25600 > /sys/class/kgsl/kgsl/max_reclaim_limit
	fi
}


# Set Memory parameters.
configure_memory_parameters





