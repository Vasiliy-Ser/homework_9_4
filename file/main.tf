terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "my_network" {
  name = "default-network"
}

resource "yandex_vpc_subnet" "my_subnet" {
  name           = "my_subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.my_network.id
  v4_cidr_blocks = ["172.24.8.0/24"]
}

resource "yandex_compute_instance" "vm" {
  count        = 2
  name         = "vm-${count.index + 1}"
  platform_id  = "standard-v1"
  zone         = "ru-central1-a"
  boot_disk {
    initialize_params {
      image_id = "fd866d9q7rcg6h4udadk" # ID образа Ubuntu 20.04 в Yandex Cloud
      size = 8
    }
  }
  resources {
    cores         = 2
    memory        = 2
  }
  
  network_interface {
    subnet_id = yandex_vpc_subnet.my_subnet.id
    nat       = true
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-config.yaml", {
      ssh_public_key = var.ssh_public_key
    })
  }
}

resource "yandex_lb_target_group" "my_tg" {
  name = "vm-target-group"
  region_id = "ru-central1"

  dynamic "target" {
    for_each = [for instance in yandex_compute_instance.vm : {
      address  = instance.network_interface.0.ip_address
      subnet_id = yandex_vpc_subnet.my_subnet.id
    }]
    content {
      address   = target.value.address
      subnet_id = target.value.subnet_id
    }
  }
}

#  target {
#    subnet_id = yandex_vpc_subnet.my_subnet.id
#    ip_address  = yandex_compute_instance.vm[0].network_interface.0.ip_address
#  }

#  target {
#    ubnet_id = yandex_vpc_subnet.my_subnet.id
#    ip_address  = yandex_compute_instance.vm[1].network_interface.0.ip_address
#  }
#}

resource "yandex_lb_network_load_balancer" "my-balancer" {
  name    = "my-balancer"
  deletion_protection = "false"

  listener {
    name        = "my-http-listener"
    port        = 80
    target_port = 80
    external_address_spec {}
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.my_tg.id

    healthcheck {
      name                = "my-http-healthcheck"
      interval            = 5
      timeout             = 2
      healthy_threshold   = 2
      unhealthy_threshold = 2

      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
