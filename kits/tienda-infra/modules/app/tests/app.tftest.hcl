mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test/abc", dns_name = "test-123.us-east-1.elb.amazonaws.com" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test/abc" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { id = "arn:aws:ecs:us-east-1:123456789012:cluster/test" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/test-api:1" }
  }
}

variables {
  nombre            = "tienda-test"
  vpc_id            = "vpc-0123456789abcdef0"
  subredes_publicas = ["subnet-pub-a", "subnet-pub-b"]
  subredes_privadas = ["subnet-priv-a", "subnet-priv-b"]
  imagen            = "public.ecr.aws/docker/library/python:3.13-slim"
  variables_entorno = { DB_HOST = "bd.local", DB_USER = "app" }
  secretos          = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-x:password::" }
  secretos_arn      = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-x"]
}

run "solo_http_detras_de_cloudfront" {
  command = apply

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "forward" && length(aws_lb_listener.https) == 0
    error_message = "Sin certificado, el listener HTTP debe reenviar a las tareas."
  }

  assert {
    condition     = output.url == "http://test-123.us-east-1.elb.amazonaws.com"
    error_message = "La URL debe ser HTTP cuando no hay certificado."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.api.container_definitions)[0].readonlyRootFilesystem
    error_message = "El contenedor debe tener el sistema de archivos en solo lectura."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.api.container_definitions)[0].secrets[0].name == "DB_PASSWORD"
    error_message = "La contraseña debe llegar como secreto, no como variable de entorno."
  }

  assert {
    condition     = one(aws_ecs_task_definition.api.runtime_platform).cpu_architecture == "ARM64"
    error_message = "Las tareas deben ser ARM64 (Graviton)."
  }

  assert {
    condition     = one(aws_ecs_service.api.network_configuration).assign_public_ip == false
    error_message = "Las tareas no deben tener IP pública."
  }
}

run "https_con_certificado" {
  command = apply

  variables {
    certificado_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
    tareas_min      = 2
    tareas_max      = 6
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect" && length(aws_lb_listener.https) == 1
    error_message = "Con certificado, HTTP debe redirigir a HTTPS."
  }

  assert {
    condition     = aws_appautoscaling_target.api.min_capacity == 2 && aws_appautoscaling_target.api.max_capacity == 6
    error_message = "El autoescalado debe respetar tareas_min y tareas_max."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 2
    error_message = "Con HTTPS el balanceador debe abrir 80 y 443."
  }
}

run "rechaza_max_menor_que_min" {
  command = plan

  variables {
    tareas_min = 3
    tareas_max = 2
  }

  expect_failures = [var.tareas_max]
}
