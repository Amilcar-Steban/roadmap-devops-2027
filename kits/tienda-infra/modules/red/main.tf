# VPC en tres niveles por AZ: pública (ALB, NAT), privada (tareas ECS) y datos (RDS, caché, sin internet).
#
#   10.0.0.0/16
#   ├── públicas  /24  10.0.0.0, 10.0.1.0, …       cidrsubnet(cidr, 8, i)
#   ├── privadas  /20  10.0.16.0, 10.0.32.0, …     cidrsubnet(cidr, 4, i + 1)
#   └── datos     /24  10.0.100.0, 10.0.101.0, …   cidrsubnet(cidr, 8, i + 100)

locals {
  indices  = { for i, az in var.azs : az => i }
  publicas = { for az, i in local.indices : az => cidrsubnet(var.cidr, 8, i) }
  privadas = { for az, i in local.indices : az => cidrsubnet(var.cidr, 4, i + 1) }
  datos    = { for az, i in local.indices : az => cidrsubnet(var.cidr, 8, i + 100) }

  nat_azs = var.nat == "por_az" ? var.azs : (var.nat == "uno" ? [var.azs[0]] : [])
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.nombre }
}

# Sin reglas: nada usa el security group por defecto por accidente
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.nombre}-default-no-usar" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.nombre }
}

resource "aws_subnet" "publica" {
  for_each          = local.publicas
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value
  tags              = { Name = "${var.nombre}-publica-${each.key}", tipo = "publica" }
}

resource "aws_subnet" "privada" {
  for_each          = local.privadas
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value
  tags              = { Name = "${var.nombre}-privada-${each.key}", tipo = "privada" }
}

resource "aws_subnet" "datos" {
  for_each          = local.datos
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value
  tags              = { Name = "${var.nombre}-datos-${each.key}", tipo = "datos" }
}

# --- Rutas públicas: salida directa por el Internet Gateway

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.nombre}-publica" }
}

resource "aws_route" "publica_internet" {
  route_table_id         = aws_route_table.publica.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "publica" {
  for_each       = aws_subnet.publica
  subnet_id      = each.value.id
  route_table_id = aws_route_table.publica.id
}

# --- NAT: uno por AZ en producción, uno solo (o ninguno) en dev

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)
  domain   = "vpc"
  tags     = { Name = "${var.nombre}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.nat_azs)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.publica[each.key].id
  tags          = { Name = "${var.nombre}-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# --- Rutas privadas: una tabla por AZ, para que cada AZ salga por su NAT

resource "aws_route_table" "privada" {
  for_each = local.indices
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${var.nombre}-privada-${each.key}" }
}

resource "aws_route" "privada_nat" {
  for_each               = length(local.nat_azs) == 0 ? {} : local.indices
  route_table_id         = aws_route_table.privada[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  # Con un solo NAT, todas las AZ salen por él; con por_az, cada una por el suyo
  nat_gateway_id = aws_nat_gateway.this[contains(local.nat_azs, each.key) ? each.key : local.nat_azs[0]].id
}

resource "aws_route_table_association" "privada" {
  for_each       = aws_subnet.privada
  subnet_id      = each.value.id
  route_table_id = aws_route_table.privada[each.key].id
}

# --- Datos: sin ruta a internet

resource "aws_route_table" "datos" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.nombre}-datos" }
}

resource "aws_route_table_association" "datos" {
  for_each       = aws_subnet.datos
  subnet_id      = each.value.id
  route_table_id = aws_route_table.datos.id
}

# Endpoint de tipo gateway para S3: gratis, y el tráfico a S3 no pasa por el NAT (que cobra por GB)
data "aws_region" "actual" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.actual.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for rt in aws_route_table.privada : rt.id], [aws_route_table.datos.id])
  tags              = { Name = "${var.nombre}-s3" }
}

# --- Flow logs

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.flow_logs ? 1 : 0
  name              = "/vpc/${var.nombre}/flow-logs"
  retention_in_days = var.retencion_logs
}

resource "aws_iam_role" "flow_logs" {
  count = var.flow_logs ? 1 : 0
  name  = "${var.nombre}-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.flow_logs ? 1 : 0
  name  = "escribir-logs"
  role  = aws_iam_role.flow_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count           = var.flow_logs ? 1 : 0
  vpc_id          = aws_vpc.this.id
  traffic_type    = "REJECT" # solo lo rechazado: barato y suficiente para depurar
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
}
