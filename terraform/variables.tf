variable "project" {
  type    = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

provider "google" {
  project = var.project
  region  = var.region
}


variable "api_service_name" {
  type = string
  default = "api-service"
}
variable "user_service_name" {
  type = string
  default = "user-service"
}

variable "dns_zone" {
  type    = string
}
locals {
  domain = data.google_dns_managed_zone.default.dns_name
}
data "google_dns_managed_zone" "default" {
  name = var.dns_zone
}
