variable "instance_id" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "cpu_threshold" {
  type    = number
  default = 80
}
