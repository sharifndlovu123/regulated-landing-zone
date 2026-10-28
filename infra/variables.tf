variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "location" {
  description = "Primary region. South Africa North (Johannesburg) has availability zones."
  type        = string
  default     = "southafricanorth"
}

variable "environment" {
  description = "Environment name, used in resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "nonprod", "prod"], var.environment)
    error_message = "environment must be dev, nonprod or prod."
  }
}

variable "owner" {
  description = "Who is responsible for these resources. Becomes the owner tag."
  type        = string
}

variable "cost_center" {
  description = "Who pays. Becomes the cost-center tag, used for chargeback."
  type        = string
  default     = "portfolio"
}
