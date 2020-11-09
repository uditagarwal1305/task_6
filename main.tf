# Kubernetes Provider

provider "kubernetes" {}

# AWS Provider

provider "aws" {
  profile = "udit"
  region  = "ap-south-1"
}

# Getting default VPC

data "aws_vpc" "default_vpc" {
    default = true
}

# Getting default Subnets

data "aws_subnet_ids" "default_subnet" {
  vpc_id = data.aws_vpc.default_vpc.id
}

# Security Group for RDS Instance

resource "aws_security_group" "rds_sg" {
  name        = "rds security group"
  description = "Connection between WordPress and RDS"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS-SG"
  }
}

# Subnet Group for RDS

resource "aws_db_subnet_group" "subnet_grp" {
  name       = "rds subnet group"
  subnet_ids = data.aws_subnet_ids.default_subnet.ids
}

# RDS Instance

resource "aws_db_instance" "rds" {

    depends_on = [
    aws_security_group.rds_sg,
    aws_db_subnet_group.subnet_grp,
  ]

  engine                 = "mysql"
  engine_version         = "5.7"
  identifier             = "wordpress-database"
  username               = "wpuser"
  password               = "WordPressPass"
  instance_class         = "db.t2.micro"
  storage_type           = "gp2"
  allocated_storage      = 20
  db_subnet_group_name   = aws_db_subnet_group.subnet_grp.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = true
  name                   = "wpdb"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
}

# Kubernetes Deployment of WordPress

resource "kubernetes_deployment" "wp_deploy" {
    depends_on = [
    aws_db_instance.rds,
  ]
  metadata {
      name = "wordpress"
      labels = {
          app = "wordpress"
        }
    }
  spec {
      selector {
        match_labels = {
            app = "wordpress"
            }
        }
    template {
        metadata {
            labels = {
               app = "wordpress"
           }
        }
        spec {
            container {
                image = "wordpress"
                name  = "wordpress-pod"
                env {
                    name = "WORDPRESS_DB_HOST"
                    value = aws_db_instance.rds.endpoint
                }
                env {
                    name = "WORDPRESS_DB_DATABASE"
                    value = aws_db_instance.rds.name 
                }
                env {
                    name = "WORDPRESS_DB_USER"
                    value = aws_db_instance.rds.username
                }
                env {
                    name = "WORDPRESS_DB_PASSWORD"
                    value = aws_db_instance.rds.password
                }
                port {
                container_port = 80
                }
            }
        }
     }
  }
}

# Exposing Kubernetes Deployment

resource "kubernetes_service" "wp_service" {
    depends_on = [
    kubernetes_deployment.wp_deploy,
  ]
  metadata {
    name = "wp-service"
  }
  spec {
    selector = {
      app = "wordpress"
    }
    port {
      port = 80
      target_port = 80
      node_port = 30050
    }

    type = "NodePort"
  }
}

// Finally opening WordPress in Chrome Browser

resource "null_resource" "ChromeOpen"  {
depends_on = [
    kubernetes_service.wp_service,
  ]

	provisioner "local-exec" {
	    command = "minikube service ${kubernetes_service.wp_service.metadata[0].name}"
  	}
}