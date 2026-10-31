# La API de la tienda en ECS Fargate (ARM64) detrás de un Application Load Balancer.
# Terraform crea el servicio y su primera versión; el workflow Deploy AWS de la Fase 3 publica
# las siguientes. Por eso el servicio ignora los cambios de task_definition y desired_count.

data "aws_region" "actual" {}

locals {
  https = var.certificado_arn != null
}

# --- Registro de imágenes

resource "aws_ecr_repository" "api" {
  name                 = "${var.nombre}-api"
  image_tag_mutability = "IMMUTABLE" # una etiqueta = un contenido, siempre
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar las 30 imágenes más recientes"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}

# --- Roles: el de ejecución lo usa ECS (descargar la imagen, leer secretos, escribir logs);
#     el de tarea lo usa tu código (vacío: la API no llama a servicios de AWS)

resource "aws_iam_role" "ejecucion" {
  name = "${var.nombre}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ejecucion" {
  role       = aws_iam_role.ejecucion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ejecucion_secretos" {
  count = length(var.secretos_arn) > 0 ? 1 : 0
  name  = "leer-secretos"
  role  = aws_iam_role.ejecucion.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.secretos_arn
    }]
  })
}

resource "aws_iam_role" "tarea" {
  name = "${var.nombre}-api-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# --- Balanceador

resource "aws_security_group" "alb" {
  name        = "${var.nombre}-alb"
  description = "Balanceador publico de la tienda"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each          = toset(local.https ? ["80", "443"] : ["80"])
  security_group_id = aws_security_group.alb.id
  description       = "Entrada publica al puerto ${each.key}"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_tareas" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Hacia las tareas"
  ip_protocol                  = "tcp"
  from_port                    = var.puerto
  to_port                      = var.puerto
  referenced_security_group_id = aws_security_group.tareas.id
}

# Público a propósito: es la entrada de la API
#trivy:ignore:AWS-0053
resource "aws_lb" "this" {
  name                       = var.nombre
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.subredes_publicas
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.proteccion_borrado
}

resource "aws_lb_target_group" "api" {
  name                 = "${var.nombre}-api"
  port                 = var.puerto
  protocol             = "HTTP"
  target_type          = "ip" # Fargate (awsvpc): cada tarea tiene su IP
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.ruta_salud
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Sin certificado, el ALB solo recibe tráfico HTTP de CloudFront, que sirve HTTPS al usuario
#trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https ? "redirect" : "forward"
    target_group_arn = local.https ? null : aws_lb_target_group.api.arn

    dynamic "redirect" {
      for_each = local.https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificado_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# --- Servicio

resource "aws_security_group" "tareas" {
  name        = "${var.nombre}-tareas"
  description = "Tareas de la API"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "tareas" {
  security_group_id            = aws_security_group.tareas.id
  description                  = "Solo desde el balanceador"
  ip_protocol                  = "tcp"
  from_port                    = var.puerto
  to_port                      = var.puerto
  referenced_security_group_id = aws_security_group.alb.id
}

# Salida HTTPS (ECR, Secrets Manager, CloudWatch) a través del NAT: sus IPs públicas cambian
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "tareas_https" {
  security_group_id = aws_security_group.tareas.id
  description       = "HTTPS hacia las APIs de AWS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.nombre}-api"
  retention_in_days = var.retencion_logs
}

resource "aws_ecs_cluster" "this" {
  name = var.nombre
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.nombre}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memoria
  execution_role_arn       = aws_iam_role.ejecucion.arn
  task_role_arn            = aws_iam_role.tarea.arn

  runtime_platform {
    cpu_architecture        = "ARM64" # Graviton: ~20 % más barato que x86
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name                   = "api"
    image                  = var.imagen
    essential              = true
    readonlyRootFilesystem = true
    user                   = "10001:10001"
    portMappings           = [{ containerPort = var.puerto, protocol = "tcp" }]
    environment            = [for k, v in var.variables_entorno : { name = k, value = v }]
    secrets                = [for k, v in var.secretos : { name = k, valueFrom = v }]
    healthCheck = {
      command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.puerto}${var.ruta_salud}', timeout=2)"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = data.aws_region.actual.region
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.tareas_min
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subredes_privadas
    security_groups  = concat([aws_security_group.tareas.id], var.security_groups_extra)
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.puerto
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true # si la versión nueva no arranca, vuelve sola a la anterior
  }

  health_check_grace_period_seconds = 60

  lifecycle {
    # desired_count lo cambia el autoescalado y task_definition el pipeline de despliegue:
    # sin esto, cada plan intentaría deshacer sus cambios.
    ignore_changes = [desired_count, task_definition]
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
}

# --- Autoescalado por CPU

resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.tareas_min
  max_capacity       = var.tareas_max
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.nombre}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_objetivo
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
