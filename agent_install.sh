#!/bin/bash

# Check for required packages
if ! rpm -q --quiet gcc; then echo "Zabbix Agent installation requires GCC, please install first."; exit 1; fi
if ! rpm -q --quiet make; then echo "Zabbix Agent installtion requires make, please install first."; exit 1; fi
if ! rpm -q --quiet bind-utils; then echo "Zabbix Agent installation requires bind-utils, please install first."; exit 1; fi

# Assign some variables... FOR SCIENCE!
curdir=$(pwd);
fqdn=$(hostname -f);
zabbix_url="http://zabbix.solarsquid.com/assets";
zabbix_tar="zabbix.tgz";
zbxserver_ip=$(host zabbix.solarsquid.com | grep address | awk '{ print $4 }');

# Get details from user
zabbix_log_size=-1
until [ ${zabbix_log_size} -ge 0 ] && [ ${zabbix_log_size} -le 1024 ]; do
    echo "Please input desired log size in MB (0 for no logging, max 1024): "
    read zabbix_log_size;
done

# Set up zbxagent user
useradd -d /home/zbxagent -m -s /sbin/nologin zbxagent;

# Set up the log dir for zbxagent if logging is on
if [ ${zabbix_log_size} -ne 0 ]; then
    mkdir /home/zbxagent/logs;
    touch /home/zbxagent/logs/zabbix_agentd.log;
    chown -R zbxagent.zbxagent /home/zbxagent;
fi

# Download and install the zabbix agent software
cd /usr/src;
wget "${zabbix_url}/${zabbix_tar}";
tar -xzvf ${zabbix_tar};
rm -f ${zabbix_tar};
zbx_dir=$(ls | grep zabbix);
cd ${zbx_dir};
./configure --enable-agent;
make install;

# Symlink the configuration file
ln -s /usr/local/etc/zabbix_agent.conf /etc/zabbix_agent.conf;
ln -s /usr/local/etc/zabbix_agentd.conf /etc/zabbix_agentd.conf;

# Adjust conf files
sed --follow-symlinks -i "s/Server=127.0.0.1/Server=${zbxserver_ip}/g" /etc/zabbix_agent.conf;
sed --follow-symlinks -i '/# PidFile/a \ \nPidFile=\/home\/zbxagent\/\.zabbix_agentd\.pid' /etc/zabbix_agentd.conf;
if [ ${zabbix_log_size} -ne 0 ]; then
    sed --follow-symlinks -i 's/LogFile=\/tmp\//LogFile=\/home\/zbxagent\/logs\//g' /etc/zabbix_agentd.conf;
    sed --follow-symlinks -i "/# LogFileSize/a \ \nLogFileSize=${zabbix_log_size}" /etc/zabbix_agentd.conf;
else
    sed --follow-symlinks -i 's/LogFile=\/tmp\/zabbix_agentd\.log/LogFile=\/dev\/null/g' /etc/zabbix_agentd.conf;
fi
sed --follow-symlinks -i '/# DebugLevel/a \ \nDebugLevel=3' /etc/zabbix_agentd.conf;
sed --follow-symlinks -i '/# EnableRemoteCommands/a \ \nEnableRemoteCommands=1' /etc/zabbix_agentd.conf;
if [ ${zabbix_log_size} -ne 0 ]; then
    sed --follow-symlinks -i '/# LogRemoteCommands/a \ \nLogRemoteCommands=1' /etc/zabbix_agentd.conf;
fi
sed --follow-symlinks -i "s/Server=127\.0\.0\.1/Server=${zbxserver_ip}/g" /etc/zabbix_agentd.conf
sed --follow-symlinks -i '/# ListenPort/a \ \nListenPort=10050' /etc/zabbix_agentd.conf;
sed --follow-symlinks -i '/# StartAgents/a \ \nStartAgents=3' /etc/zabbix_agentd.conf;
sed --follow-symlinks -i "/ServerActive=127\.0\.0\.1/ServerActive=${zbxserver_ip}/g" /etc/zabbix_agentd.conf;
sed --follow-symlinks -i "s/Hostname=Zabbix server/Hostname=${fqdn}/g" /etc/zabbix_agentd.conf;

# Copy init script
cp /usr/src/${zbx_dir}/misc/init.d/fedora/core5/zabbix_agentd /etc/init.d/;

# Adjust init script to run daemon as the zbxagent user
sed --follow-symlinks -i 's/daemon \$ZABBIX_BIN/daemon --user=zbxagent \$ZABBIX_BIN/g' /etc/init.d/zabbix_agentd;

# Start agent
/etc/init.d/zabbix_agentd start;

# Clean up install files
cd ${curdir};
rm -rf /usr/src/${zbx_dir};
echo 'All done!';
