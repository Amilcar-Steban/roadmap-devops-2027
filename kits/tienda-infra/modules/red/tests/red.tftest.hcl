# El proveedor simulado inventa valores, pero algunos argumentos exigen un ARN con formato válido
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:/vpc/test/flow-logs" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test" }
  }
}

variables {
  nombre = "tienda-test"
  azs    = ["us-east-1a", "us-east-1b"]
}

run "dev_con_un_nat" {
  command = apply

  variables {
    nat = "uno"
  }

  assert {
    condition     = aws_subnet.publica["us-east-1a"].cidr_block == "10.0.0.0/24" && aws_subnet.privada["us-east-1b"].cidr_block == "10.0.32.0/20" && aws_subnet.datos["us-east-1a"].cidr_block == "10.0.100.0/24"
    error_message = "Los CIDR de las subredes no siguen el plan de direcciones."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Con nat = uno debe haber un solo NAT Gateway."
  }

  assert {
    condition     = aws_route.privada_nat["us-east-1b"].nat_gateway_id == aws_nat_gateway.this["us-east-1a"].id
    error_message = "Con un solo NAT, la AZ b debe salir por el NAT de la AZ a."
  }

  assert {
    condition     = length(output.subredes_privadas) == 2
    error_message = "Debe haber una subred privada por AZ."
  }
}

run "prod_con_un_nat_por_az" {
  command = apply

  variables {
    nat = "por_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Con nat = por_az debe haber un NAT por AZ."
  }

  assert {
    condition     = aws_route.privada_nat["us-east-1b"].nat_gateway_id == aws_nat_gateway.this["us-east-1b"].id
    error_message = "Cada AZ debe salir por su propio NAT."
  }
}

run "sin_nat_no_hay_salida_a_internet" {
  command = plan

  variables {
    nat       = "ninguno"
    flow_logs = false
  }

  assert {
    condition     = length(aws_route.privada_nat) == 0 && length(aws_nat_gateway.this) == 0
    error_message = "Con nat = ninguno no debe haber NAT ni ruta por defecto en las privadas."
  }

  assert {
    condition     = length(aws_flow_log.this) == 0
    error_message = "flow_logs = false no debe crear flow logs."
  }
}

run "rechaza_una_sola_az" {
  command = plan

  variables {
    azs = ["us-east-1a"]
  }

  expect_failures = [var.azs]
}

run "rechaza_cidr_demasiado_pequeno" {
  command = plan

  variables {
    cidr = "10.0.0.0/24"
  }

  expect_failures = [var.cidr]
}
