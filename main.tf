locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_config = templatefile(
    "${path.module}/files/network_config.yaml.tpl", 
    {
      macvtap_interfaces = var.macvtap_interfaces
    }
  )
  network_interfaces = length(var.macvtap_interfaces) == 0 ? [{
    network_id = var.libvirt_network.network_id
    macvtap = null
    addresses = [var.libvirt_network.ip]
    mac = var.libvirt_network.mac != "" ? var.libvirt_network.mac : null
    hostname = var.name
  }] : [for macvtap_interface in var.macvtap_interfaces: {
    network_id = null
    macvtap = macvtap_interface.interface
    addresses = null
    mac = macvtap_interface.mac
    hostname = null
  }]
  ips = length(var.macvtap_interfaces) == 0 ? [
    var.libvirt_network.ip
  ] : [
    for macvtap_interface in var.macvtap_interfaces: macvtap_interface.ip
  ]
  fluentd_conf = templatefile(
    "${path.module}/files/fluentd.conf.tpl", 
    {
      fluentd = var.fluentd
      fluentd_buffer_conf = var.fluentd.buffer.customized ? var.fluentd.buffer.custom_value : file("${path.module}/files/fluentd_buffer.conf")
    }
  )
  opensearch_bootstrap_conf = templatefile(
    "${path.module}/files/opensearch.yml.tpl",
    {
      opensearch = var.opensearch
      node_name = var.name
      node_ip = local.ips.0
      initial_cluster = var.opensearch.initial_cluster
    }
  )
  opensearch_runtime_conf = templatefile(
    "${path.module}/files/opensearch.yml.tpl",
    {
      opensearch = var.opensearch
      node_name = var.name
      node_ip = local.ips.0
      initial_cluster = false
    }
  )
  opensearch_security_conf = {
    config = templatefile(
        "${path.module}/files/opensearch_security/config.yml.tpl",
        {
            opensearch = var.opensearch
        }
    )
    allowlist = file("${path.module}/files/opensearch_security/allowlist.yml")
    internal_users = file("${path.module}/files/opensearch_security/internal_users.yml")
    roles = file("${path.module}/files/opensearch_security/roles.yml")
    roles_mapping = file("${path.module}/files/opensearch_security/roles_mapping.yml")
    action_groups = file("${path.module}/files/opensearch_security/action_groups.yml")
    tenants = file("${path.module}/files/opensearch_security/tenants.yml")
    nodes_dn = file("${path.module}/files/opensearch_security/nodes_dn.yml")
    whitelist = file("${path.module}/files/opensearch_security/whitelist.yml")
  }
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/user_data.yaml.tpl", 
      {
        node_name = var.name
        ssh_admin_public_key = var.ssh_admin_public_key
        ssh_admin_user = var.ssh_admin_user
        admin_user_password = var.admin_user_password
        chrony = var.chrony
        fluentd = var.fluentd
        fluentd_conf = local.fluentd_conf
        opensearch = var.opensearch
        server_tls_cert = tls_locally_signed_cert.server.cert_pem
        server_tls_key = tls_private_key.server.private_key_pem
        ca_tls_cert = var.opensearch.ca.certificate
        opensearch_admin_tls_cert = var.opensearch.bootstrap_security ? tls_locally_signed_cert.admin.0.cert_pem : ""
        opensearch_admin_tls_key = var.opensearch.bootstrap_security ? tls_private_key.admin.0.private_key_pem : ""
        opensearch_bootstrap_conf = local.opensearch_bootstrap_conf
        opensearch_runtime_conf = local.opensearch_runtime_conf
        opensearch_security_conf = local.opensearch_security_conf
        node_ip = local.ips.0
        install_dependencies = var.install_dependencies
      }
    )
  }
}

resource "libvirt_cloudinit_disk" "opensearch" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = length(var.macvtap_interfaces) > 0 ? local.network_config : null
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "opensearch" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  disk {
    volume_id = var.volume_id
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.opensearch.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}