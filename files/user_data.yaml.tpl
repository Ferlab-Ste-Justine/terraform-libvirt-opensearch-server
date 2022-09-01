#cloud-config
%{ if admin_user_password != "" ~}
chpasswd:
  list: |
     ${ssh_admin_user}:${admin_user_password}
  expire: False
%{ endif ~}
preserve_hostname: false
hostname: ${node_name}
users:
  - default
  - name: node-exporter
    system: true
    lock_passwd: true
  - name: opensearch
    system: true
    lock_passwd: true
  - name: ${ssh_admin_user}
    ssh_authorized_keys:
      - "${ssh_admin_public_key}"
write_files:
  #Chrony config
%{ if chrony.enabled ~}
  - path: /opt/chrony.conf
    owner: root:root
    permissions: "0444"
    content: |
%{ for server in chrony.servers ~}
      server ${join(" ", concat([server.url], server.options))}
%{ endfor ~}
%{ for pool in chrony.pools ~}
      pool ${join(" ", concat([pool.url], pool.options))}
%{ endfor ~}
      driftfile /var/lib/chrony/drift
      makestep ${chrony.makestep.threshold} ${chrony.makestep.limit}
      rtcsync
%{ endif ~}
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
%{ if fluentd.enabled ~}
  #Fluentd config file
  - path: /opt/fluentd.conf
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd_conf)}
  #Fluentd systemd configuration
  - path: /etc/systemd/system/fluentd.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Fluentd"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=root
      Group=root
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=fluentd -c /opt/fluentd.conf

      [Install]
      WantedBy=multi-user.target
  #Fluentd forward server certificate
  - path: /opt/fluentd_ca.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd.forward_ca_cert)}
%{ endif ~}
  #Opensearch certs
  - path: /etc/opensearch/server-certs/server.crt
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, server_tls_cert)}
  - path: /etc/opensearch/server-certs/server.key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, server_tls_key)}
  - path: /etc/opensearch/ca-certs/ca.crt
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, ca_tls_cert)}
%{ if opensearch.bootstrap_security ~}
  - path: /etc/opensearch/client-certs/admin.crt
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, opensearch_admin_tls_cert)}
  - path: /etc/opensearch/client-certs/admin.key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, opensearch_admin_tls_key)}
  - path: /usr/local/bin/bootstrap_opensearch_security
    owner: root:root
    permissions: "0555"
    content: |
      echo "Waiting for server to join cluster with green status before bootstraping security"
      STATUS=$(curl --silent --cert /etc/opensearch/client-certs/admin.crt --key /etc/opensearch/client-certs/admin.key --cacert /etc/opensearch/ca-certs/ca.crt https://${node_ip}:9200/_cluster/health | jq ".status")
      while [ "$STATUS" != "\"green\"" ]; do
          sleep 1
          STATUS=$(curl --silent --cert /etc/opensearch/client-certs/admin.crt --key /etc/opensearch/client-certs/admin.key --cacert /etc/opensearch/ca-certs/ca.crt https://${node_ip}:9200/_cluster/health | jq ".status")
      done
      /opt/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
        -f /etc/opensearch/configuration/opensearch-security.yml \
        -icl -nhnv -cert /etc/opensearch/client-certs/admin.crt \
        -key /etc/opensearch/client-certs/admin.key \
        -cacert /etc/opensearch/ca-certs/ca.crt \
        -t config
%{ endif ~}
  #opensearch configuration
  - path: /etc/opensearch/configuration/log4j2.properties
    owner: root:root
    permissions: "0644"
    content: |
      log4j.rootLogger = INFO,CONSOLE
      log4j.appender.console=org.apache.log4j.ConsoleAppender
      log4j.appender.CONSOLE.Threshold=INFO
  - path: /etc/opensearch/configuration/jvm.options
    owner: root:root
    permissions: "0644"
    content: |
      #Heap
      -Xms__HEAP_SIZE__m
      -Xmx__HEAP_SIZE__m

      #G1GC Configuration
      -XX:+UseG1GC
      -XX:G1ReservePercent=25
      -XX:InitiatingHeapOccupancyPercent=30

      #performance analyzer
      -Djdk.attach.allowAttachSelf=true
      -Djava.security.policy=/opt/opensearch/plugins/opensearch-performance-analyzer/plugin-security.policy
      --add-opens=jdk.attach/sun.tools.attach=ALL-UNNAMED
  - path: /usr/local/bin/set_dynamic_opensearch_java_options
    owner: root:root
    permissions: "0555"
    content: |
      #!/bin/bash
      #Heap size
%{ if opensearch.manager ~}
      HEAP_SIZE=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') * 3 / 4 / 1024 ))
%{ else ~}
      HEAP_SIZE=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 2 / 1024 ))
%{ endif ~}
      sed "s/__HEAP_SIZE__/$HEAP_SIZE/g" -i /etc/opensearch/configuration/jvm.options
      #performance analyzer
      CLK_TCK=$(/usr/bin/getconf CLK_TCK)
      echo "-Dclk.tck=$CLK_TCK" >> /etc/opensearch/configuration/jvm.options
  - path: /usr/local/bin/adjust_tls_key_format
    owner: root:root
    permissions: "0555"
    content: |
      #!/bin/bash
      openssl pkcs8 -in /etc/opensearch/server-certs/server.key -topk8 -nocrypt -out /etc/opensearch/server-certs/server-key-pk8.pem
  - path: /etc/opensearch/configuration/opensearch.yml
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, opensearch_config)}
  - path: /etc/opensearch/configuration/opensearch-security.yml
    owner: root:root
    permissions: "0444"
    content: |
      _meta:
        type: "config"
        config_version: 2

      config:
        dynamic:
          http:
            anonymous_auth_enabled: false
            xff:
              enabled: false
          authc:
            clientcert_auth_domain:
              description: "Authenticate via TLS client certificates"
              http_enabled: true
              transport_enabled: true
              order: 1
              http_authenticator:
                type: clientcert
                config:
                  username_attribute: cn
                challenge: false
              authentication_backend:
                type: noop
  #opensearch systemd configuration
  - path: /etc/systemd/system/opensearch.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Opensearch"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      Environment=OPENSEARCH_PATH_CONF=/etc/opensearch/configuration
      Environment=JAVA_HOME=/opt/opensearch/jdk
      Environment=OPENSEARCH_TMPDIR=
      Environment=LD_LIBRARY_PATH=/opt/opensearch/plugins/opensearch-knn/lib
      LimitNOFILE=65535
      LimitNPROC=4096
      LimitAS=infinity
      LimitFSIZE=infinity
      User=opensearch
      Group=opensearch
      Type=simple
      Restart=always
      RestartSec=1
      WorkingDirectory=/opt/opensearch
      ExecStart=/opt/opensearch/bin/opensearch

      [Install]
      WantedBy=multi-user.target
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg-agent
  - software-properties-common
  - libdigest-sha-perl
  - jq
%{ if fluentd.enabled ~}
  - ruby-full
  - build-essential
%{ endif ~}
%{ if chrony.enabled ~}
  - chrony
%{ endif ~}
runcmd:
  #Finalize Chrony Setup
%{ if chrony.enabled ~}
  - cp /opt/chrony.conf /etc/chrony/chrony.conf
  - systemctl restart chrony.service 
%{ endif ~}
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.3.0/node_exporter-1.3.0.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.3.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter
  #Fluentd setup
%{ if fluentd.enabled ~}
  - mkdir -p /opt/fluentd-state
  - chown root:root /opt/fluentd-state
  - chmod 0700 /opt/fluentd-state
  - gem install fluentd
  - gem install fluent-plugin-systemd -v 1.0.5
  - systemctl enable fluentd.service
  - systemctl start fluentd.service
%{ endif ~}
  #Install Opensearch
  - /usr/local/bin/set_dynamic_opensearch_java_options
  - /usr/local/bin/adjust_tls_key_format
  - echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
  - echo 'vm.swappiness = 1' >> /etc/sysctl.conf
  - sysctl -p
  - wget -O /opt/opensearch.tar.gz https://artifacts.opensearch.org/releases/bundle/opensearch/2.2.0/opensearch-2.2.0-linux-x64.tar.gz
  - tar zxvf /opt/opensearch.tar.gz -C /opt
  - mv /opt/opensearch-2.2.0 /opt/opensearch
  - chown -R opensearch:opensearch /opt/opensearch
  - rm /opt/opensearch.tar.gz
  - chown -R opensearch:opensearch /etc/opensearch
  - systemctl enable opensearch.service
  - systemctl start opensearch.service
%{ if opensearch.bootstrap_security ~}
  - /usr/local/bin/bootstrap_opensearch_security
%{ endif ~}