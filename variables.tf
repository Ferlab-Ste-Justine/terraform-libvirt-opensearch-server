variable "name" {
  description = "Name to give to the vm."
  type        = string
}

variable "vcpus" {
  description = "Number of vcpus to assign to the vm"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory in MiB"
  type        = number
  default     = 8192
}

variable "volume_id" {
  description = "Id of the disk volume to attach to the vm"
  type        = string
}

variable "libvirt_networks" {
  description = "Parameters of libvirt network connections if libvirt networks are used."
  type = list(object({
    network_name  = optional(string, "")
    network_id    = optional(string, "")
    prefix_length = string
    ip            = string
    mac           = string
    gateway       = optional(string, "")
    dns_servers   = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for net in var.libvirt_networks : net.prefix_length != "" && net.ip != "" && net.mac != "" && ((net.network_name != "" && net.network_id == "") || (net.network_name == "" && net.network_id != ""))])
    error_message = "Each entry in libvirt_networks must have the following keys defined and not empty: prefix_length, ip, mac, network_name xor network_id"
  }
}

variable "macvtap_interfaces" {
  description = "List of macvtap interfaces. Mutually exclusive with the libvirt_network Field. Each entry has the following keys: interface, prefix_length, ip, mac, gateway and dns_servers"
  type = list(object({
    interface     = string
    prefix_length = string
    ip            = string
    mac           = string
    gateway       = string
    dns_servers   = list(string)
  }))
  default = []
}

variable "extra_http_bind_ips" {
  description = "Extra ip(s) to which the node binds for http communication specifically"
  type        = list(string)
  default     = []
}

variable "cloud_init_volume_pool" {
  description = "Name of the volume pool that will contain the cloud init volume"
  type        = string
}

variable "cloud_init_volume_name" {
  description = "Name of the cloud init volume"
  type        = string
  default     = ""
}

variable "ssh_admin_user" {
  description = "Pre-existing ssh admin user of the image"
  type        = string
  default     = "ubuntu"
}

variable "admin_user_password" {
  description = "Optional password for admin user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_admin_public_key" {
  description = "Public ssh part of the ssh key the admin will be able to login as"
  type        = string
}

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type = object({
    enabled = bool,
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url     = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url     = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number,
      limit     = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools   = []
    makestep = {
      threshold = 0,
      limit     = 0
    }
  }
}

variable "fluentd" {
  description = "Fluentd configurations"
  sensitive   = true
  type = object({
    enabled           = bool,
    opensearch_tag    = string,
    node_exporter_tag = string,
    forward = object({
      domain     = string,
      port       = number,
      hostname   = string,
      shared_key = string,
      ca_cert    = string,
    }),
    buffer = object({
      customized   = bool,
      custom_value = string,
    })
  })
  default = {
    enabled           = false
    opensearch_tag    = ""
    node_exporter_tag = ""
    forward = {
      domain     = ""
      port       = 0
      hostname   = ""
      shared_key = ""
      ca_cert    = ""
    }
    buffer = {
      customized   = false
      custom_value = ""
    }
  }
}

variable "opensearch" {
  description = "Opensearch configurations"
  type = object({
    cluster_name                  = string
    cluster_manager               = bool
    seed_hosts                    = list(string)
    bootstrap_security            = bool
    initial_cluster               = bool
    initial_cluster_manager_nodes = optional(list(string))

    tls = object({
      ca_certificate = string
      server = object({
        key         = string
        certificate = string
      })
      admin_client = object({
        key         = string
        certificate = string
      })
    })

    auth_dn_fields = object({
      admin_common_name = string
      node_common_name  = string
      organization      = string
    })

    verify_domains     = bool
    basic_auth_enabled = bool

    audit = optional(object({
      enabled = optional(bool, false)
      index   = string

      external = optional(object({
        http_endpoints = optional(list(string), [])
        auth = optional(object({
          ca_cert     = optional(string, "")
          client_cert = optional(string, "")
          client_key  = optional(string, "")
          username    = optional(string, "")
          password    = optional(string, "")
          }), {
          ca_cert     = ""
          client_cert = ""
          client_key  = ""
          username    = ""
          password    = ""
        })
        }), {
        http_endpoints = []
        auth = {
          ca_cert     = ""
          client_cert = ""
          client_key  = ""
          username    = ""
          password    = ""
        }
      })

      ignore_users    = optional(list(string), [])
      ignore_requests = optional(list(string), [])
    }), null)

    index_lifecycle_policies = optional(list(object({
      name              = string
      delete_min_age    = string
      index_patterns    = list(string)
      template_name     = string
      template_priority = number
    })), [])
  })
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type        = bool
  default     = true
}

variable "snapshot_repository" {
  description = "Snapshot repository credentials and CA propagated to cloud-init"
  type = object({
    access_key = optional(string, "")
    secret_key = optional(string, "")
    ca_cert    = optional(string, "")
  })
  default = {
    access_key = ""
    secret_key = ""
    ca_cert    = ""
  }
  sensitive = true
}
