#!/bin/bash

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <domain_name> <server_ip>"
    exit 1
fi

# Read command-line arguments
domain_name=$1
server_ip=$1
ns1_ip=$1
mail_server_ip=$1
web_server_ip=$1

# Disable SELinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

# Disable Firewalld
systemctl stop firewalld
systemctl disable firewalld

# Install BIND DNS server
yum -y install bind bind-utils

# Configure named.conf
echo "options {
        listen-on port 53 { any; };
        directory       \"/var/named\";
        dump-file       \"/var/named/data/cache_dump.db\";
        statistics-file \"/var/named/data/named_stats.txt\";
        memstatistics-file \"/var/named/data/named_mem_stats.txt\";
        allow-query     { any; };

        recursion yes;

        dnssec-enable yes;
        dnssec-validation yes;

        /* Path to ISC DLV key */
        bindkeys-file \"/etc/named.iscdlv.key\";

        managed-keys-directory \"/var/named/dynamic\";

        pid-file \"/run/named/named.pid\";
        session-keyfile \"/run/named/session.key\";

        forwarders {
            8.8.8.8;
            8.8.4.4;
        };
};

logging {
        channel default_debug {
                file \"data/named.run\";
                severity dynamic;
        };
};

zone \".\" IN {
        type hint;
        file \"named.ca\";
};

include \"/etc/named.rfc1912.zones\";
include \"/etc/named.root.key\";

zone \"$domain_name\" IN {
        type master;
        file \"/var/named/$domain_name.zone\";
        allow-update { none; };
};

" > /etc/named.conf

# Create zone file for the domain
echo "\$TTL 86400
@       IN      SOA     ns1.$domain_name. admin.$domain_name. (
                        2023052001      ; Serial
                        3600            ; Refresh
                        1800            ; Retry
                        604800          ; Expire
                        86400           ; Minimum TTL
)
;
@       IN      NS      ns1.$domain_name.
@       IN      NS      ns2.$domain_name.
;
@       IN      MX      10      mail.$domain_name.
;
ns1     IN      A       $ns1_ip
ns2     IN      A       $server_ip
mail    IN      A       $mail_server_ip
www     IN      A       $web_server_ip
" > "/var/named/$domain_name.zone"

# Update file permissions
chown root:named /etc/named.conf
chown named:named "/var/named/$domain_name.zone"

# Enable and start named service
systemctl enable named
systemctl start named

# Test the configuration
named-checkconf /etc/named.conf
named-checkzone "$domain_name" "/var/named/$domain_name.zone"

echo "BIND installation and MX record configuration completed."
