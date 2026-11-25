provider "aws" {
  region = var.aws_region
}

resource "aws_key_pair" "lab_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Project = var.project_name
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "${var.project_name}-vpc"
  cidr = "10.10.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Allow HTTP to Nginx reverse proxy"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Allow MariaDB 3306 only from EC2 app security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Access to MariaDB only from app SG."
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-db-sg"
    Project = var.project_name
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name    = "${var.project_name}-db-subnets"
    Project = var.project_name
  }
}

resource "aws_db_instance" "mariadb" {
  identifier     = "${var.project_name}-db"
  engine         = "mariadb"
  engine_version = "10.11"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name    = "${var.project_name}-db"
    Project = var.project_name
  }
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable --now docker

    mkdir -p /opt/wp-stack/nginx
    chmod 700 /opt/wp-stack

    cat <<'NGINXCONF' > /opt/wp-stack/nginx/default.conf
    server {
        listen 80;
        server_name _;

        root /var/www/html;
        index index.php index.html;

        client_max_body_size 32M;

        location / {
            try_files $uri $uri/ /index.php?$args;
        }

        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass wordpress:9000;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
        }

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
            expires 7d;
            access_log off;
            try_files $uri /index.php?$args;
        }
    }
    NGINXCONF

    cat <<COMPOSEEOF > /opt/wp-stack/docker-compose.yml
    services:
      wordpress:
        image: wordpress:fpm
        container_name: wordpress
        restart: unless-stopped
        environment:
          WORDPRESS_DB_HOST: "${aws_db_instance.mariadb.address}:3306"
          WORDPRESS_DB_USER: "${var.db_username}"
          WORDPRESS_DB_PASSWORD: "${var.db_password}"
          WORDPRESS_DB_NAME: "${var.db_name}"
        volumes:
          - wp_data:/var/www/html
        networks:
          - wp_net

      nginx:
        image: nginx:alpine
        container_name: nginx
        restart: unless-stopped
        ports:
          - "80:80"
        volumes:
          - wp_data:/var/www/html:ro
          - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
        depends_on:
          - wordpress
        networks:
          - wp_net

    volumes:
      wp_data:

    networks:
      wp_net:
        driver: bridge
    COMPOSEEOF

    cd /opt/wp-stack
    docker compose up -d
  EOF
}

resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true
  user_data                   = local.user_data
  key_name                    = aws_key_pair.lab_key.key_name
  depends_on                  = [aws_db_instance.mariadb]

  root_block_device {
    volume_size           = 9
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-app"
    Project = var.project_name
  }
}
