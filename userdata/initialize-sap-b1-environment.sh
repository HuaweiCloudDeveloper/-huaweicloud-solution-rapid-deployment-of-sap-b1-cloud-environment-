#!/bin/sh
export "${1?}"
export "${2?}"
export "${3?}"
export "${4?}"
export "${5?}"

#hosts and fstab configurations
while :
do  
  sleep 5
  if lsblk|grep -q  "vdg"
  then
    break
  fi  
done
mkdir -p /usr/sap /hana/log /hana/shared /hana/data
mkswap /dev/vdb
swapon /dev/vdb
mkfs.xfs /dev/vdc
mkfs.xfs /dev/vdd
mkfs.xfs /dev/vde 
pvcreate /dev/vdf /dev/vdg
vgcreate vghana /dev/vdf /dev/vdg
lvcreate -i 2 -l 100%VG -n lvhanadata vghana
mkfs.xfs /dev/mapper/vghana-lvhanadata
{
    echo "$(blkid /dev/vdb|awk '{print $2}') swap swap defaults 0 0"
    echo "$(blkid /dev/vdc|awk '{print $2}') /usr/sap xfs defaults 0 0"
    echo "$(blkid /dev/vdd|awk '{print $2}') /hana/log xfs defaults 0 0"
    echo "$(blkid /dev/vde|awk '{print $2}') /hana/shared xfs defaults 0 0"
    echo "$(blkid /dev/mapper/vghana-lvhanadata|awk '{print $2}') /hana/data xfs defaults 0 0" 
} >> /etc/fstab
mount -a

#SFS mounting configurations
if  [ -n "${SFS_TURBO_NAME}" ] && [ -z "${OBS_BUCKET_NAME}" ]
then
    mkdir -p /hana/backup
    echo "${SFS_TURBO_IP} /hana/backup nfs vers=3,timeo=600,nolock 1 2" >> /etc/fstab
    mount -a
fi

#AZ identification
az=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
azaz=${az::-1}

#OBS mounting configurations
if  [ -n "${OBS_BUCKET_NAME}" ] && [ -n "${AK}" ] && [ -n "${SK}" ]
then
    echo "$AK":"$SK" > /etc/passwd-obsfs
    chmod 600 /etc/passwd-obsfs
    mkdir -p /hana/backup
    cat > /etc/init.d/obsfs <<- EOF
#!/bin/bash
obsfs ${OBS_BUCKET_NAME} /hana/backup -o url=obs.$azaz.myhuaweicloud.com -o passwd_file=/etc/passwd-obsfs -o big_writes -o max_write=131072 -o max_background=100 -o use_ino -o allow_other -o nonempty
EOF
    chmod +x /etc/init.d/obsfs
    if which obsfs;then
      systemctl daemon-reload
      systemctl start obsfs.service
      chkconfig obsfs on
    else
       echo "obsfs uninstalled"
    fi
fi

if [ "$azaz" = "ap-southeast-3" ]
then
#ces plug-in
cd /usr/local && curl -k -O https://obs.ap-southeast-3.myhuaweicloud.com/uniagent-ap-southeast-3/script/agent_install.sh && bash agent_install.sh
#hss plug-in
curl -k -O 'https://hss-agent.ap-southeast-3.myhuaweicloud.com:10180/package/agent/linux/x86/hostguard.x86_64.rpm' && echo 'MASTER_IP=hss-agent.ap-southeast-3.myhuaweicloud.com:10180' > hostguard_setup_config.conf && echo 'SLAVE_IP=hss-agent-slave.ap-southeast-3.myhuaweicloud.com:10180' >> hostguard_setup_config.conf && echo 'ORG_ID=' >> hostguard_setup_config.conf && rpm -ivh hostguard.x86_64.rpm && rm -f hostguard_setup_config.conf && rm -f hostguard.X86_64.rpm
#Database backup plug-in
dig @100.125.1.250 +short A csbs-agent-ap-southeast-3.obs.ap-southeast-3.myhuaweicloud.com | tail -n1 | xargs -t -I '{}' wget http://{}/csbs-agent-ap-southeast-3/"Cloud Server Backup Agent-SuSE12-x86_64.tar.gz" && tar -zxf "Cloud Server Backup Agent-SuSE12-x86_64.tar.gz" && cd bin && chmod u+x agent_install_ebk.sh &&  ./agent_install_ebk.sh
fi