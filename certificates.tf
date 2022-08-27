resource "tls_private_key" "server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.opensearch.auth_dn_fields.node_common_name
    organization = var.opensearch.auth_dn_fields.organization
  }

  dns_names = var.opensearch.certificates.domains
  ip_addresses = [local.ips.0]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = var.opensearch.ca.key
  ca_cert_pem        = var.opensearch.ca.certificate

  validity_period_hours = var.opensearch.certificates.validity_period
  early_renewal_hours = var.opensearch.certificates.early_renewal_period

  allowed_uses = [
    "server_auth",
    "client_auth"
  ]

  is_ca_certificate = false
}

resource "tls_private_key" "admin" {
  count = var.opensearch.bootstrap_security ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "admin" {
  count = var.opensearch.bootstrap_security ? 1 : 0
  private_key_pem = tls_private_key.admin.0.private_key_pem

  subject {
    common_name  = var.opensearch.auth_dn_fields.admin_common_name
    organization = var.opensearch.auth_dn_fields.organization
  }
}

resource "tls_locally_signed_cert" "admin" {
  count = var.opensearch.bootstrap_security ? 1 : 0
  cert_request_pem   = tls_cert_request.admin.0.cert_request_pem
  ca_private_key_pem = var.opensearch.ca.key
  ca_cert_pem        = var.opensearch.ca.certificate

  validity_period_hours = var.opensearch.certificates.validity_period
  early_renewal_hours = var.opensearch.certificates.early_renewal_period

  allowed_uses = [
    "client_auth",
  ]

  is_ca_certificate = false
}