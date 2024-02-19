#!/bin/bash
sudo /usr/bin/scsi-rescan -r
# Set initial value for drive index
d=1

# Populate temp.txt with configuration parameters
echo debug=88 > temp.txt
echo compratio=3 >> temp.txt
echo data_errors=1 >> temp.txt

# Iterate through the output of multipath command, filter by certain criteria, and append to temp.txt
for i in $(multipath -ll | egrep 'SILK|KMNRIO' | grep -v 0000 | awk '{print $3}'); do
    echo sd=sd$d,lun=/dev/$i,openflags=o_direct >> temp.txt
    let "d=d+1"
done

# Append additional configuration parameters to temp.txt
echo 'wd=wd1,sd=sd*,rdpct=50,rhpct=0,whpct=0,xfersize=64k,seekpct=100' >> temp.txt
echo 'rd=rd1,wd=wd*,interval=1,iorate=MAX,elapsed=2600000,forthreads=(10)' >> temp.txt

# Execute vdbench with the generated configuration file using sudo
sudo /local_hd/vdbench50406/vdbench -f temp.txt