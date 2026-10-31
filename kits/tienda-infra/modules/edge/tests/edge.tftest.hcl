mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/E123TEST"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }
}

variables {
  nombre     = "tienda-test"
  bucket_web = "tienda-test-web-123456789012"
  alb_dns    = "tienda-test-123.us-east-1.elb.amazonaws.com"
}

run "api_sin_cache_y_web_cacheada" {
  command = apply

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].path_pattern == "/api/*" && aws_cloudfront_distribution.this.ordered_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    error_message = "/api/* debe ir al balanceador sin caché."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Todo el tráfico debe redirigirse a HTTPS."
  }

  assert {
    condition     = strcontains(aws_cloudfront_response_headers_policy.seguridad.security_headers_config[0].content_security_policy[0].content_security_policy, "default-src 'self'")
    error_message = "La política de cabeceras debe llevar la misma CSP que el proxy (sin scripts en línea)."
  }

  assert {
    condition     = output.url == "https://d111111abcdef8.cloudfront.net"
    error_message = "Sin alias, la URL es la de CloudFront."
  }
}

run "rechaza_certificado_fuera_de_us_east_1" {
  command = plan

  variables {
    alias           = ["tienda.ejemplo.com"]
    certificado_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/abc"
  }

  expect_failures = [var.certificado_arn]
}
