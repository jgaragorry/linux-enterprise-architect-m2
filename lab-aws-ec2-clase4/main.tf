provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.finops_tags
  }
}

# AMI oficial de Canonical Ubuntu 26.04 LTS para arquitectura ARM64 (Graviton2)
data "aws_ami" "ubuntu_2604_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-*-26.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_key_pair" "gmt_key" {
  key_name   = "${var.admin_username}-graviton2-key"
  public_key = file("~/.ssh/gmt_lab_ed25519.pub")

  tags = merge(var.finops_tags, {
    Name = "${var.admin_username}-graviton2-key"
  })
}

resource "aws_default_vpc" "default" {
  tags = merge(var.finops_tags, {
    Name = "default-vpc-lab"
  })
}

resource "aws_security_group" "ssh_lab_sg" {
  name        = "${var.admin_username}-ssh-lab-sg"
  description = "Permite acceso SSH hacia la instancia de laboratorio"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.finops_tags, {
    Name = "${var.admin_username}-ssh-lab-sg"
  })
}

locals {
  pubkey = trimspace(file("~/.ssh/gmt_lab_ed25519.pub"))

  cloud_init_user_data = <<-CLOUDINIT
    #cloud-config
    users:
      - default
      - name: ${var.admin_username}
        groups: [sudo]
        shell: /bin/bash
        sudo: ["ALL=(ALL) NOPASSWD:ALL"]
        lock_passwd: true
        ssh_authorized_keys:
          - ${local.pubkey}
    runcmd:
      - systemctl mask systemd-networkd-wait-online.service || true
      - systemctl start ssh || systemctl start sshd || true
      - install -d -m 700 -o ${var.admin_username} -g ${var.admin_username} /home/${var.admin_username}/.ssh
      - printf '%s\n' '${local.pubkey}' > /home/${var.admin_username}/.ssh/authorized_keys
      - chown ${var.admin_username}:${var.admin_username} /home/${var.admin_username}/.ssh/authorized_keys
      - chmod 600 /home/${var.admin_username}/.ssh/authorized_keys
      - install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh || true
      - printf '%s\n' '${local.pubkey}' >> /home/ubuntu/.ssh/authorized_keys || true
      - chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys || true
      - chmod 600 /home/ubuntu/.ssh/authorized_keys || true
      - echo "${var.admin_username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${var.admin_username}
      - chmod 440 /etc/sudoers.d/90-${var.admin_username}
  CLOUDINIT
}

resource "aws_instance" "lab_node" {
  ami                         = data.aws_ami.ubuntu_2604_arm64.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.gmt_key.key_name
  vpc_security_group_ids      = [aws_security_group.ssh_lab_sg.id]
  associate_public_ip_address = true
  user_data_replace_on_change = false
  user_data                   = local.cloud_init_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 16
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.finops_tags, {
      Name       = "${var.admin_username}-root-gp3"
      VolumeRole = "root"
    })
  }

  tags = merge(var.finops_tags, {
    Name = "${var.admin_username}-ubuntu2604-graviton2"
  })
}

resource "aws_ebs_volume" "extra_data_gp3" {
  availability_zone = aws_instance.lab_node.availability_zone
  size              = var.extra_ebs_size_gb
  type              = "gp3"
  encrypted         = true

  tags = merge(var.finops_tags, {
    Name       = "${var.admin_username}-data-10gb-gp3"
    VolumeRole = "extra-data"
  })
}

resource "aws_volume_attachment" "extra_data_attach" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.extra_data_gp3.id
  instance_id = aws_instance.lab_node.id
}
