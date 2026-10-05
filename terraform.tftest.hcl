mock_provider "aws" {
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      arn           = "arn:aws:apigateway:us-east-1::/apis/a1b2c3d4e5"
      api_endpoint  = "https://a1b2c3d4e5.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:a1b2c3d4e5"
    }
  }

  mock_resource "aws_apigatewayv2_stage" {
    defaults = {
      arn        = "arn:aws:apigateway:us-east-1::/apis/a1b2c3d4e5/stages/$default"
      invoke_url = "https://a1b2c3d4e5.execute-api.us-east-1.amazonaws.com/"
    }
  }
}

run "an_unknown_protocol_type_is_rejected" {
  command = plan

  variables {
    protocol_type = "GRAPHQL"
  }

  expect_failures = [var.protocol_type]
}

run "a_websocket_api_without_a_route_selection_expression_is_rejected" {
  command = plan

  variables {
    protocol_type = "WEBSOCKET"
  }

  expect_failures = [var.protocol_type]
}

run "a_route_selection_expression_on_an_http_api_is_rejected" {
  command = plan

  variables {
    route_selection_expression = "$request.body.action"
  }

  expect_failures = [var.protocol_type]
}

run "cors_on_a_websocket_api_is_rejected" {
  command = plan

  variables {
    protocol_type              = "WEBSOCKET"
    route_selection_expression = "$request.body.action"

    cors_configuration = {
      allow_origins = ["https://example.com"]
    }
  }

  expect_failures = [var.protocol_type]
}

run "an_unknown_integration_type_is_rejected" {
  command = plan

  variables {
    integrations = {
      chat = { integration_type = "CARRIER_PIGEON", integration_uri = "https://example.com" }
    }
  }

  expect_failures = [var.integrations]
}

run "a_non_mock_integration_without_a_uri_is_rejected" {
  command = plan

  variables {
    integrations = {
      chat = { integration_type = "AWS_PROXY" }
    }
  }

  expect_failures = [var.integrations]
}

run "a_route_pointing_at_a_missing_integration_is_rejected" {
  command = plan

  variables {
    integrations = {
      chat = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:chat" }
    }

    routes = {
      chat = { route_key = "POST /chat", integration_key = "typo" }
    }
  }

  expect_failures = [var.routes]
}

run "an_unknown_authorization_type_is_rejected" {
  command = plan

  variables {
    routes = {
      chat = { route_key = "POST /chat", authorization_type = "HANDSHAKE" }
    }
  }

  expect_failures = [var.routes]
}

run "a_jwt_route_without_an_authorizer_is_rejected" {
  command = plan

  variables {
    routes = {
      chat = { route_key = "POST /chat", authorization_type = "JWT" }
    }
  }

  expect_failures = [var.routes]
}

run "name_defaults_to_the_generated_uuid" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_api.resource.name == random_uuid.resource.id
    error_message = "Leaving name unset should fall back to the generated random_uuid."
  }
}

run "an_api_with_no_routes_still_creates_one_stage" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.resource.protocol_type == "HTTP"
    error_message = "protocol_type should default to HTTP."
  }

  assert {
    condition     = aws_apigatewayv2_stage.resource.name == "$default"
    error_message = "stage_name should default to the $default stage, which serves the API with no path prefix."
  }

  assert {
    condition     = aws_apigatewayv2_stage.resource.auto_deploy == true
    error_message = "auto_deploy should default to true."
  }

  assert {
    condition     = length(aws_apigatewayv2_route.resource) == 0 && length(aws_apigatewayv2_integration.resource) == 0
    error_message = "An API with no integrations or routes should create neither."
  }
}

run "integrations_and_routes_are_keyed_by_the_caller" {
  command = plan

  variables {
    integrations = {
      chat   = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:chat" }
      health = { integration_type = "MOCK" }
    }

    routes = {
      chat   = { route_key = "POST /chat", integration_key = "chat" }
      health = { route_key = "GET /health", integration_key = "health" }
      catch  = { route_key = "$default" }
    }
  }

  assert {
    condition     = length(aws_apigatewayv2_integration.resource) == 2 && length(aws_apigatewayv2_route.resource) == 3
    error_message = "Each integrations and routes entry should create exactly one resource."
  }

  assert {
    condition     = aws_apigatewayv2_route.resource["chat"].route_key == "POST /chat"
    error_message = "A route should be addressed by the caller's key and carry its own route_key."
  }

  assert {
    condition     = aws_apigatewayv2_route.resource["catch"].target == null
    error_message = "A route with no integration_key should have no target."
  }
}

run "a_route_targets_the_integration_its_key_names" {
  command = apply

  variables {
    integrations = {
      chat = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:chat" }
    }

    routes = {
      chat = { route_key = "POST /chat", integration_key = "chat" }
    }
  }

  assert {
    condition     = aws_apigatewayv2_route.resource["chat"].target == "integrations/${aws_apigatewayv2_integration.resource["chat"].id}"
    error_message = "A route's target should resolve to the integration its integration_key names."
  }
}

run "payload_format_version_is_sent_for_http_and_omitted_for_websocket" {
  command = plan

  variables {
    integrations = {
      chat = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:chat" }
    }
  }

  assert {
    condition     = aws_apigatewayv2_integration.resource["chat"].payload_format_version == "2.0"
    error_message = "An HTTP API's integration should default to payload format 2.0."
  }
}

run "a_websocket_api_omits_payload_format_version" {
  command = plan

  variables {
    protocol_type              = "WEBSOCKET"
    route_selection_expression = "$request.body.action"

    integrations = {
      send = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:send" }
    }

    routes = {
      send = { route_key = "send", integration_key = "send", api_key_required = true }
    }
  }

  assert {
    condition     = aws_apigatewayv2_integration.resource["send"].payload_format_version == null
    error_message = "A WebSocket API has no payload format, so the argument should be omitted rather than defaulted."
  }

  assert {
    condition     = aws_apigatewayv2_route.resource["send"].api_key_required == true
    error_message = "api_key_required should pass through on a WebSocket route."
  }
}

run "an_http_route_omits_api_key_required" {
  command = plan

  variables {
    routes = {
      chat = { route_key = "POST /chat", api_key_required = true }
    }
  }

  assert {
    condition     = aws_apigatewayv2_route.resource["chat"].api_key_required == null
    error_message = "api_key_required applies only to a WebSocket route and should be omitted for an HTTP one."
  }
}

run "access_logging_appears_only_when_a_destination_is_given" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_stage.resource.access_log_settings) == 0
    error_message = "With no access_log_destination_arn the stage should carry no access_log_settings block."
  }
}

run "an_access_log_destination_configures_the_stage" {
  command = plan

  variables {
    access_log_destination_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/apigateway/example"
  }

  assert {
    condition     = length(aws_apigatewayv2_stage.resource.access_log_settings) == 1
    error_message = "Setting access_log_destination_arn should add one access_log_settings block."
  }

  assert {
    condition     = one(aws_apigatewayv2_stage.resource.access_log_settings).destination_arn == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/apigateway/example"
    error_message = "The access log destination should be the log group the caller supplied."
  }
}

run "cors_and_route_settings_are_applied_when_supplied" {
  command = plan

  variables {
    cors_configuration = {
      allow_origins     = ["https://example.com"]
      allow_methods     = ["POST"]
      allow_credentials = true
    }

    default_route_settings = {
      throttling_burst_limit = 50
      throttling_rate_limit  = 25
    }
  }

  assert {
    condition     = one(aws_apigatewayv2_api.resource.cors_configuration).allow_origins == toset(["https://example.com"])
    error_message = "cors_configuration should pass the caller's origins through."
  }

  assert {
    condition     = one(aws_apigatewayv2_stage.resource.default_route_settings).throttling_rate_limit == 25
    error_message = "default_route_settings should apply the caller's throttle."
  }
}

run "a_lambda_permission_is_scoped_to_this_api" {
  command = apply

  variables {
    integrations = {
      chat = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:chat" }
    }

    routes = {
      chat = { route_key = "POST /chat", integration_key = "chat" }
    }

    lambda_permissions = {
      chat = { function_name = "chat" }
    }
  }

  assert {
    condition     = length(aws_lambda_permission.resource) == 1
    error_message = "Each lambda_permissions entry should create one permission."
  }

  assert {
    condition     = aws_lambda_permission.resource["chat"].statement_id == "AllowInvocationFromApiGateway-chat"
    error_message = "A permission's statement_id should be derived from the caller's key so two APIs do not collide."
  }

  assert {
    condition     = aws_lambda_permission.resource["chat"].source_arn == "${aws_apigatewayv2_api.resource.execution_arn}/*/*"
    error_message = "A permission should be scoped to this API's execution ARN, not left open to any caller."
  }
}

run "readme_minimal_http_api" {
  command = plan

  variables {
    name = "example"

    integrations = {
      chat = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:example-chat" }
    }

    routes = {
      chat = { route_key = "POST /chat", integration_key = "chat" }
    }

    lambda_permissions = {
      chat = { function_name = "example-chat" }
    }
  }

  assert {
    condition     = length(aws_apigatewayv2_route.resource) == 1
    error_message = "The README's minimal example should plan and create its one route."
  }
}

run "readme_github_source_example" {
  command = plan

  variables {
    name = "example"

    routes = {
      health = { route_key = "GET /health" }
    }

    integrations = {}
  }

  assert {
    condition     = aws_apigatewayv2_api.resource.name == "example"
    error_message = "The README's GitHub-source example should plan."
  }
}

run "readme_logged_and_throttled_api" {
  command = plan

  variables {
    name = "example"

    integrations = {
      chat = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:example-chat" }
    }

    routes = {
      chat = { route_key = "POST /chat", integration_key = "chat", authorization_type = "AWS_IAM" }
    }

    lambda_permissions = {
      chat = { function_name = "example-chat" }
    }

    access_log_destination_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/apigateway/example"

    default_route_settings = {
      throttling_burst_limit   = 100
      throttling_rate_limit    = 50
      detailed_metrics_enabled = true
    }

    cors_configuration = {
      allow_origins = ["https://example.com"]
      allow_methods = ["POST"]
      allow_headers = ["content-type"]
    }

    tags = {
      Service = "support-assistant"
    }
  }

  assert {
    condition     = aws_apigatewayv2_route.resource["chat"].authorization_type == "AWS_IAM"
    error_message = "The README's hardened example should require IAM authorization on its route."
  }
}

run "readme_websocket_api" {
  command = plan

  variables {
    name                       = "example"
    protocol_type              = "WEBSOCKET"
    route_selection_expression = "$request.body.action"

    integrations = {
      send = { integration_uri = "arn:aws:lambda:us-east-1:123456789012:function:example-send" }
    }

    routes = {
      connect    = { route_key = "$connect" }
      disconnect = { route_key = "$disconnect" }
      send       = { route_key = "send", integration_key = "send" }
    }

    lambda_permissions = {
      send = { function_name = "example-send" }
    }

    stage_name = "production"
  }

  assert {
    condition     = length(aws_apigatewayv2_route.resource) == 3
    error_message = "The README's WebSocket example should plan its three routes."
  }
}
