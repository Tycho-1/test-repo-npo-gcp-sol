# Global Variables
variable "project" {
  type        = string
  description = "The project name"
  default     = ""
}
variable "location" {
  type        = string
  description = "The location"
  default     = ""
}
variable "region" {
  type        = string
  description = "The region"
  default     = ""
}

variable "labels" {
  type        = map(string)
  description = "Set of labels to identify the cluster"
  default     = {}
}

