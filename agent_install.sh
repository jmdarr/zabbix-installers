#!/bin/bash

# Check for required packages
packages=( "gcc" "make" "bind-utils" "sed" "net-snmp" );
for package in "${packages[@]}"; do
    if ! rpm -q --quiet ${package}; then
        echo "Zabbix Agent installation requires ${package}, please install first.";
        exit 1;
    fi
done

# Assign some variables... FOR SCIENCE!
curdir=$(pwd);
fqdn=$(hostname -f);
zabbix_url="http://zabbix.solarsquid.com/assets";
zabbix_tar="zabbix.tgz";
zbxserver_ip=$(host zabbix.solarsquid.com | grep address | awk '{ print $4 }');
sedbin="sed --follow-symlinks -i";

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
## zabbix_agent.conf
${sedbin} "s/Server=127.0.0.1/Server=${zbxserver_ip}/g" /etc/zabbix_agent.conf;

## zabbix_agentd.conf
if [ ${zabbix_log_size} -ne 0 ]; then
    ${sedbin} 's/LogFile=\/tmp\//LogFile=\/home\/zbxagent\/logs\//g' /etc/zabbix_agentd.conf;
    ${sedbin} "/# LogFileSize/a \ \nLogFileSize=${zabbix_log_size}" /etc/zabbix_agentd.conf;
    ${sedbin} '/# LogRemoteCommands/a \ \nLogRemoteCommands=1' /etc/zabbix_agentd.conf;
else
    ${sedbin} 's/LogFile=\/tmp\/zabbix_agentd\.log/LogFile=\/dev\/null/g' /etc/zabbix_agentd.conf;
fi
${sedbin} '/# PidFile/a \ \nPidFile=\/home\/zbxagent\/\.zabbix_agentd\.pid' /etc/zabbix_agentd.conf;
${sedbin} '/# DebugLevel/a \ \nDebugLevel=3' /etc/zabbix_agentd.conf;
${sedbin} '/# EnableRemoteCommands/a \ \nEnableRemoteCommands=1' /etc/zabbix_agentd.conf;
${sedbin} '/# ListenPort/a \ \nListenPort=10050' /etc/zabbix_agentd.conf;
${sedbin} '/# StartAgents/a \ \nStartAgents=3' /etc/zabbix_agentd.conf;
${sedbin} '/# AllowRoot=0/a \ \nAllowRoot=0' /etc/zabbix_agentd.conf;
${sedbin} "s/ServerActive=127\.0\.0\.1/ServerActive=${zbxserver_ip}/g" /etc/zabbix_agentd.conf;
${sedbin} "s/Hostname=Zabbix server/Hostname=${fqdn}/g" /etc/zabbix_agentd.conf;
${sedbin} "s/Server=127\.0\.0\.1/Server=${zbxserver_ip}/g" /etc/zabbix_agentd.conf

# Copy init script
cp /usr/src/${zbx_dir}/misc/init.d/fedora/core5/zabbix_agentd /etc/init.d/;

# Adjust init script to run daemon as the zbxagent user
${sedbin} 's/daemon \$ZABBIX_BIN/daemon --user=zbxagent \$ZABBIX_BIN/g' /etc/init.d/zabbix_agentd;

# Start agent
/etc/init.d/zabbix_agentd start;

# Clean up install files
cd ${curdir};
rm -rf /usr/src/${zbx_dir};
echo 'All done!';
