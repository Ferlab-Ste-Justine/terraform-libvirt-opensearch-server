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
<<<<<<< Updated upstream
    cluster_name       = string
    manager            = bool
    seed_hosts         = list(string)
    initial_manager_nodes = list(string)
    bootstrap_security = bool
    initial_cluster    = bool
=======
    cluster_name                  = string
    cluster_manager               = optional(bool)
    manager                       = optional(bool)
    seed_hosts                    = list(string)
    bootstrap_security            = bool
    initial_cluster               = bool
    initial_cluster_manager_nodes = optional(list(string))
    initial_manager_nodes         = optional(list(string))
>>>>>>> Stashed changes

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
      audit_client = optional(object({
        key         = string
        certificate = string
      }), null)
    })

    auth_dn_fields = object({
      admin_common_name = string
      node_common_name  = string
      organization      = string
    })

    verify_domains     = bool
    basic_auth_enabled = bool

    audit = optional(object({
<<<<<<< Updated upstream
      enabled      = optional(bool, false)
      storage_type = optional(string, "")  
      index        = optional(string, "")

      external = optional(object({
        http_endpoints       = list(string)
        enable_ssl           = optional(bool, false)
        verify_hostnames     = optional(bool, false)
        use_client_cert_auth = optional(bool, false)
        username             = optional(string, "")
        password             = optional(string, "")
=======
      enabled = optional(bool, false)
      index   = string

      external = optional(object({
        http_endpoints = list(string)
        auth = optional(object({
          ca_cert     = optional(string, "")
          client_cert = optional(string, "")
          client_key  = optional(string, "")
          username    = optional(string, "")
          password    = optional(string, "")
        }), null)
>>>>>>> Stashed changes
      }), null)

      ignore_users = optional(list(string), [])
    }), null)
  })

  validation {
    condition = !(
      try(var.opensearch.audit.external.use_client_cert_auth, false) &&
      try(var.opensearch.tls.audit_client, null) == null
    )
    error_message = "Provide opensearch.tls.audit_client when audit.external.use_client_cert_auth is enabled."
  }

  validation {
    condition     = var.opensearch.cluster_manager != null || var.opensearch.manager != null
    error_message = "Set opensearch.cluster_manager (preferred) or legacy opensearch.manager to identify the node role."
  }
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
<<<<<<< Updated upstream
  type = bool
  default = true
=======
  type        = bool
  default     = true
>>>>>>> Stashed changes
}
