resource "random_uuid" "resource" {}

resource "aws_apigatewayv2_api" "resource" {
  name          = coalesce(var.name, random_uuid.resource.id)
  protocol_type = var.protocol_type
  description   = var.description

  route_selection_expression   = var.route_selection_expression
  disable_execute_api_endpoint = var.disable_execute_api_endpoint

  dynamic "cors_configuration" {
    for_each = var.cors_configuration[*]

    content {
      allow_origins     = cors_configuration.value.allow_origins
      allow_methods     = cors_configuration.value.allow_methods
      allow_headers     = cors_configuration.value.allow_headers
      expose_headers    = cors_configuration.value.expose_headers
      allow_credentials = cors_configuration.value.allow_credentials
      max_age           = cors_configuration.value.max_age
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "resource" {
  for_each = var.integrations

  api_id           = aws_apigatewayv2_api.resource.id
  integration_type = each.value.integration_type
  integration_uri  = each.value.integration_uri

  integration_method     = each.value.integration_method
  payload_format_version = var.protocol_type == "HTTP" ? each.value.payload_format_version : null
  timeout_milliseconds   = each.value.timeout_milliseconds
  connection_type        = each.value.connection_type
  connection_id          = each.value.connection_id
  request_parameters     = each.value.request_parameters
}

resource "aws_apigatewayv2_route" "resource" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.resource.id
  route_key = each.value.route_key
  target    = each.value.integration_key != null ? "integrations/${aws_apigatewayv2_integration.resource[each.value.integration_key].id}" : null

  authorization_type = each.value.authorization_type
  authorizer_id      = each.value.authorizer_id
  api_key_required   = var.protocol_type == "WEBSOCKET" ? each.value.api_key_required : null
}

resource "aws_apigatewayv2_stage" "resource" {
  api_id      = aws_apigatewayv2_api.resource.id
  name        = var.stage_name
  auto_deploy = var.auto_deploy

  stage_variables = var.stage_variables

  dynamic "default_route_settings" {
    for_each = var.default_route_settings[*]

    content {
      throttling_burst_limit   = default_route_settings.value.throttling_burst_limit
      throttling_rate_limit    = default_route_settings.value.throttling_rate_limit
      detailed_metrics_enabled = default_route_settings.value.detailed_metrics_enabled
    }
  }

  dynamic "access_log_settings" {
    for_each = var.access_log_destination_arn[*]

    content {
      destination_arn = access_log_settings.value
      format          = var.access_log_format
    }
  }

  tags = var.tags
}

resource "aws_lambda_permission" "resource" {
  for_each = var.lambda_permissions

  statement_id  = "AllowInvocationFromApiGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  qualifier     = each.value.qualifier
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.resource.execution_arn}/*/*"
}

output "id" {
  description = "The ID of the API."
  value       = aws_apigatewayv2_api.resource.id
}

output "arn" {
  description = "The ARN of the API."
  value       = aws_apigatewayv2_api.resource.arn
}

output "name" {
  description = "The name of the API, generated when name was left null."
  value       = aws_apigatewayv2_api.resource.name
}

output "api_endpoint" {
  description = "The API's own execute-api hostname, with no stage path. Null in effect when disable_execute_api_endpoint is set, since nothing answers there."
  value       = aws_apigatewayv2_api.resource.api_endpoint
}

output "invoke_url" {
  description = "The URL to call, including the stage path when stage_name is not '$default'. This is the value to hand to a client."
  value       = aws_apigatewayv2_stage.resource.invoke_url
}

output "execution_arn" {
  description = "The ARN API Gateway invokes integrations under, which an integration's own resource policy must permit."
  value       = aws_apigatewayv2_api.resource.execution_arn
}

output "stage_arn" {
  description = "The ARN of the stage. This is what terraform-aws-wafv2-web-acl-association takes as resource_arn — a web ACL attaches to the stage, not to the API."
  value       = aws_apigatewayv2_stage.resource.arn
}

output "stage_name" {
  description = "The name of the stage."
  value       = aws_apigatewayv2_stage.resource.name
}

output "integration_ids" {
  description = "Map of the key you chose for each integration to that integration's ID."
  value       = { for k, i in aws_apigatewayv2_integration.resource : k => i.id }
}

output "route_ids" {
  description = "Map of the key you chose for each route to that route's ID."
  value       = { for k, r in aws_apigatewayv2_route.resource : k => r.id }
}
