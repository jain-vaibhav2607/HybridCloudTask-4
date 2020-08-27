provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true

  tags = {
    Name = "wordpressvpc"
  }
}

resource "aws_subnet" "subnet1" {

  depends_on = [
    aws_vpc.myvpc
  ]

  vpc_id     = "${aws_vpc.myvpc.id}"
  cidr_block = "192.168.0.0/24"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "PublicSubnet"
  }
}


resource "aws_subnet" "subnet2" {

  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "PrivateSubnet"
  }
}

resource "aws_internet_gateway" "gw" {
  
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "myigw"
  }
}

resource "aws_route_table" "route1" {
  depends_on = [
    aws_internet_gateway.gw
  ]

  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "myroutetable"
  }
}


resource "aws_route_table_association" "routeassociation1" {

  depends_on = [
    aws_subnet.subnet1,
    aws_route_table.route1
  ]

  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route1.id
}


resource "aws_eip" "lb" {
vpc      = true
}

resource "aws_nat_gateway" "NATgw" {

depends_on = [
    aws_subnet.subnet1,
    aws_eip.lb
  ]

allocation_id = aws_eip.lb.id
subnet_id     = aws_subnet.subnet1.id
}

resource "aws_route_table" "route2" {

depends_on = [
    aws_nat_gateway.NATgw,
    aws_eip.lb
  ]

vpc_id = aws_vpc.myvpc.id
    route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.NATgw.id
    }
}

resource "aws_route_table_association" "routeassociation2" {

depends_on = [
    aws_subnet.subnet2,
    aws_route_table.route2
  ]

subnet_id      = aws_subnet.subnet2.id
route_table_id = aws_route_table.route2.id
}


resource "aws_security_group" "mywpsg" {
  name        = "wordpress_sg"
  description = "Allow HTTP and SSH for wordpress"
  vpc_id      = "${aws_vpc.myvpc.id}"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
    Name = "wordpress_sg"
  }
}



resource "aws_security_group" "mysqlsg" {
  name        = "mysql_sg"
  description = "Allow MYSQL from wordpress only for privacy"
  vpc_id      = "${aws_vpc.myvpc.id}"

  ingress {
    description = "MYSQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups =  [ "${aws_security_group.mywpsg.id}" ]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups =  [ "${aws_security_group.mybastionhost.id}" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

tags = {
    Name = "mysql_sg"
  }
}


resource "aws_security_group" "mybastionhost" {
  name        = "bastion_sg"
  description = "Allow SSH from outside world"
  vpc_id      = "${aws_vpc.myvpc.id}"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "bastion_sg"
  }
}


resource "tls_private_key" "myprivatekey" {
  algorithm   = "RSA"
}


resource "aws_key_pair" "remotelogin_key" {
  key_name   = "remotelogin_key"
  public_key = tls_private_key.myprivatekey.public_key_openssh
}



resource  "aws_instance"   "wpinstance" {

  depends_on = [
    aws_security_group.mywpsg,
    aws_key_pair.remotelogin_key,
    aws_subnet.subnet1
  ]

  ami           = "ami-00f69f7ee089055fe"
  instance_type = "t2.micro"
  subnet_id = "${aws_subnet.subnet1.id}"
  key_name      = "${aws_key_pair.remotelogin_key.key_name}"
  security_groups   =   [ "${aws_security_group.mywpsg.id}" ]

  tags = {
    Name = "wpos"
  }
}


resource  "aws_instance"   "bastionhostinstance" {

  depends_on = [
    aws_security_group.mybastionhost,
    aws_key_pair.remotelogin_key,
    aws_subnet.subnet1
  ]

  ami           = "ami-0a780d5bac870126a"
  instance_type = "t2.micro"
  subnet_id = "${aws_subnet.subnet1.id}"
  key_name      = "${aws_key_pair.remotelogin_key.key_name}"
  security_groups   =   [ "${aws_security_group.mybastionhost.id}" ]

  tags = {
    Name = "bastionhostos"
  }
}




resource  "aws_instance"   "mysqlinstance" {

  depends_on = [
    aws_security_group.mysqlsg,
    aws_key_pair.remotelogin_key,
    aws_subnet.subnet2,
  ]

  ami           = "ami-06848868ff58d6c0e"
  instance_type = "t2.micro"
  subnet_id = "${aws_subnet.subnet2.id}"
  key_name      = "${aws_key_pair.remotelogin_key.key_name}"
  security_groups   =   [ "${aws_security_group.mysqlsg.id}" ]

  tags = {
    Name = "mysqlos"
  }
}
