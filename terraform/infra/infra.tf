# Configure AWS
provider "aws" {
	access_key = "${var.aws_access_key}"
	secret_key = "${var.aws_secret_key}"
	region = "us-east-1"
}

resource "aws_vpc" "infra" {
     cidr_block = "10.0.0.0/16"

     tags {
      Name = "infra-vpc"
     }
}

resource "aws_subnet" "public1a" {
	vpc_id =  "${aws_vpc.infra.id}"
	cidr_block = "10.0.0.0/24"
	map_public_ip_on_launch = "true"
	availability_zone = "us-east-1c"

	tags {
		Name = "Public 1A"
	}
}

resource "aws_subnet" "public1b" {
	vpc_id =  "${aws_vpc.infra.id}"
	cidr_block = "10.0.1.0/24"
	map_public_ip_on_launch = "true"
	availability_zone = "us-east-1b"

	tags {
		Name = "Public 1B"
	}
}

resource "aws_internet_gateway" "gw" {
	vpc_id = "${aws_vpc.infra.id}"

	tags {
		Name = "infra gw"
	}
}

resource "aws_security_group" "allow_ssh" {
	name = "allow_ssh"
	description = "Allow inbound SSH traffic from my IP"
	vpc_id = "${aws_vpc.infra.id}"

	ingress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["${var.my_ip}"]
	}

  egress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${var.my_ip}"]
    # cidr_blocks = ["0.0.0.0/0"]
  }

	tags {
		Name = "Allow SSH"
	}
}

resource "aws_security_group" "web_server" {
  name = "web server"
  description = "Allow HTTP and HTTPS traffic in, browser access out."
  vpc_id = "${aws_vpc.infra.id}"

  ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
      from_port = 1024
      to_port = 65535
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "Web Server"
  }
}

resource "aws_security_group" "myapp_mysql_rds" {
  name = "db server"
  description = "Allow access to MySQL RDS"
  vpc_id = "${aws_vpc.infra.id}"

  ingress {
      from_port = 3306
      to_port = 3306
      protocol = "tcp"
      security_groups = ["${aws_security_group.web_server.id}"]
      #cidr_blocks = ["${aws_instance.web01.private_ip}","${aws_instance.web02.private_ip}"]
  }

  egress {
      from_port = 1024
      to_port = 65535
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "DB Server"
  }
}

resource "aws_instance" "web01" {
    ami = "ami-6869aa05"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.public1a.id}"
    vpc_security_group_ids = ["${aws_security_group.web_server.id}","${aws_security_group.allow_ssh.id}"]
    key_name = "infra"
    tags {
        Name = "web01"
    }
}

resource "aws_instance" "web02" {
    ami = "ami-6869aa05"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.public1b.id}"
    vpc_security_group_ids = ["${aws_security_group.web_server.id}","${aws_security_group.allow_ssh.id}"]
    key_name = "infra"
    tags {
        Name = "web02"
    }
}

resource "aws_elb" "web-elb" {
  name = "web-elb-infra"
  # availability_zones = ["us-east-1c", "us-east-1b"]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }


  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 30
  }

  instances = ["${aws_instance.web01.id}","${aws_instance.web02.id}"]
  subnets = ["${aws_subnet.public1a.id}","${aws_subnet.public1b.id}"]
  security_groups = ["${aws_security_group.web_server.id}"]

  cross_zone_load_balancing = true
  idle_timeout = 400
  connection_draining = true
  connection_draining_timeout = 400

  tags {
    Name = "Web ELB"
  }
}

resource "aws_db_subnet_group" "myapp-db" {
    name = "main"
    description = "Our main group of subnets"
    subnet_ids = ["${aws_subnet.public1a.id}", "${aws_subnet.public1b.id}"]
    tags {
        Name = "MyApp DB subnet"
    }
}

resource "aws_db_instance" "web-rds-01" {
    identifier = "infradb-rds"
    allocated_storage = 10
    engine = "mysql"
    instance_class = "db.t2.micro"
    name = "infradb"
    username = "${var.db_username}"
    password = "${var.db_password}"
    vpc_security_group_ids = ["${aws_security_group.myapp_mysql_rds.id}"]
    db_subnet_group_name = "${aws_db_subnet_group.myapp-db.id}"
    parameter_group_name = "default.mysql5.6"
}

resource "aws_route_table" "internet_route" {
  vpc_id = "${aws_vpc.infra.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"

  }

  tags {
    Name = "Infra"
  }
}

resource "aws_eip" "one" {
  vpc = true
  instance = "${aws_instance.web01.id}"
}

resource "aws_eip" "two" {
  vpc = true
  instance = "${aws_instance.web02.id}"
}

resource "aws_route_table_association" "one" {
  subnet_id = "${aws_subnet.public1a.id}"
  route_table_id = "${aws_route_table.internet_route.id}"
}

resource "aws_route_table_association" "two" {
  subnet_id = "${aws_subnet.public1b.id}"
  route_table_id = "${aws_route_table.internet_route.id}"
}