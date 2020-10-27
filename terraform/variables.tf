variable "region" {
    default = "us-east-2"
}

variable "ssh-pub-key" {
    default = "~/.ssh/id_rsa.pub"
}

variable "dev-instance-types" {
    default = ["r5.large", "r5a.large"]
}

variable "dev-instance-spot-price" {
    default = "0.1"
}
