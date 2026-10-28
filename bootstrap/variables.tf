variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "location" {
  type    = string
  default = "southafricanorth"
}

variable "owner" {
  type = string
}
