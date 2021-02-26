# This file setup GCLB and SSL

resource "google_compute_backend_bucket" "webui_bucket" {
  name        = "webui-backend-bucket"
  description = "Webui app assets"
  bucket_name = google_storage_bucket.webui_bucket.name
  enable_cdn  = false
}

resource "google_compute_region_network_endpoint_group" "api_service_neg" {
  name                  = "web-app-backend-api-service-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = var.api_service_name
  }
}
resource "google_compute_backend_service" "api_service" {
  name       = "web-app-backend-api-service"
  enable_cdn = true

  backend {
    group = google_compute_region_network_endpoint_group.api_service_neg.id
  }
}

resource "google_compute_region_network_endpoint_group" "user_service_neg" {
  name                  = "web-app-backend-user-service-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = var.user_service_name
  }
}
resource "google_compute_backend_service" "user_service" {
  name       = "web-app-backend-user-service"
  enable_cdn = true

  backend {
    group = google_compute_region_network_endpoint_group.api_service_neg.id
  }
}

resource "google_compute_url_map" "default" {
  name        = "cwa-url-map"
  description = "URL mapping"

  default_service = google_compute_backend_bucket.webui_bucket.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.webui_bucket.id

    path_rule {
      paths   = ["/api", "/api/*"]
      service = google_compute_backend_service.api_service.id
    }

    path_rule {
      paths   = ["/api/users", "/api/users/*"]
      service = google_compute_backend_service.user_service.id
    }
  }
}

resource "google_compute_target_https_proxy" "default" {
  name             = "cwa-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}
resource "google_compute_managed_ssl_certificate" "default" {
  name = "cwa-ssl-certificate"

  managed {
    domains = [local.domain]
  }
}
resource "google_compute_global_forwarding_rule" "default" {
  name       = "global-rule"
  target     = google_compute_target_https_proxy.default.id
  port_range = "443"
}

# Map forwarding IP to the domain
resource "google_dns_record_set" "dns-a-record" {
  name = local.domain
  type = "A"
  ttl  = 300

  managed_zone = var.dns_zone

  rrdatas = [google_compute_global_forwarding_rule.default.ip_address]
}
# CAA record allows auto-provisioning SSL certs
resource "google_dns_record_set" "dns-caa-record" {
  name = local.domain
  type = "CAA"
  ttl  = 21600

  managed_zone = var.dns_zone

  rrdatas = [
    "0 issue \"pki.goog\"",
    "0 issue \"letsencrypt.org\"",
  ]
}
