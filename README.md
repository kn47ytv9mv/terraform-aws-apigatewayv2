# terraform-aws-apigatewayv2

Terraform module for an API Gateway v2 API — the HTTP or WebSocket front
door that receives a request from the internet and forwards it to a Lambda
function or an HTTP backend.

## Cost

An HTTP API is billed per million requests, with no standing charge: an API
nobody calls costs nothing. A WebSocket API is billed per million messages
*and* per connection-minute, so an idle open connection still bills.

HTTP APIs are substantially cheaper per request than the REST APIs of API
Gateway v1, which is the main reason to prefer them when their smaller
feature set is sufficient.

Access logging is the one setting here that creates a charge somewhere else:
each record is ingested and stored by CloudWatch Logs and billed there, not
against the API. Set a retention period on the log group.

See AWS's [API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/)
page for current rates.

## Design

This module owns the API, its stage, its routes and integrations, and the
Lambda invoke permissions those integrations need. Those resources are
useless apart from one another — a route addresses an integration by ID, and
a permission is scoped to this API's own execution ARN — so they live
together rather than as separate modules.

It does not create the Lambda function or the IAM role the function assumes.
Use [`terraform-aws-lambda-function`](https://github.com/kn47ytv9mv/terraform-aws-lambda-function) and [`terraform-aws-iam-role`](https://github.com/kn47ytv9mv/terraform-aws-iam-role) for those,
and pass the function's `invoke_arn` output as an integration's
`integration_uri`.

### The caller writes the keys

`integrations`, `routes` and `lambda_permissions` are maps keyed by a name
you choose, not lists. Two reasons, and the second is the important one.

Adding an entry to a list renumbers every entry after it, so Terraform
plans to destroy and recreate routes that did not change. A map key is
stable.

More importantly, a key derived from a value AWS computes cannot be known
at plan time, and Terraform decides resource addresses before it knows any
computed value. A module that keyed its own routes by, say, the integration
ARN would fail to plan for exactly the configuration this module exists to
support — an API created in the same apply as the function behind it. Keys
you write are known, so the plan succeeds.

### Access logging is off by default

`access_log_destination_arn` is null unless you set it, which means a
failing request leaves no trace. Turning it on requires a log group that
this module deliberately does not create, because a log group has its own
retention and encryption decisions that belong to the caller.

A static analyser will flag the default as a missing control, and that is a
fair reading: supply a log group for anything serving real traffic. The
default is null rather than created-for-you so that the module never
silently bills for a log group you did not ask for.

### CORS applies to HTTP APIs only

`cors_configuration` is evaluated by API Gateway before the request reaches
an integration, so a preflight request never costs a Lambda invocation.

One restriction is a browser rule rather than an AWS one, and AWS will
accept the configuration that violates it: a browser refuses a credentialed
cross-origin request when the response allows every origin. If
`allow_credentials` is true, list the origins explicitly instead of `*`.

### A Lambda integration needs a permission

API Gateway invokes a function as its own principal, not with the
credentials of whoever called the API. Without an entry in
`lambda_permissions`, a Lambda-backed route returns a 500 at runtime while
the plan and the apply both succeed. Each permission is scoped to this API's
execution ARN, so it does not let any other API invoke the function.

### What this module does not cover

Custom domain names, API mappings, authorizers, and VPC links are separate
resources with their own lifecycles and are not created here. Pass an
existing authorizer's ID to a route through `authorizer_id`. Deployments are
not created either — `auto_deploy` is true by default, which is the normal
way an HTTP API is operated.

## Usage

```hcl
module "api" {
  source = "kn47ytv9mv/apigatewayv2/aws"

  name = "example"

  integrations = {
    chat = { integration_uri = module.chat_function.invoke_arn }
  }

  routes = {
    chat = { route_key = "POST /chat", integration_key = "chat" }
  }

  lambda_permissions = {
    chat = { function_name = module.chat_function.function_name }
  }
}
```

Or directly from this repository:

```hcl
module "api" {
  source = "github.com/kn47ytv9mv/terraform-aws-apigatewayv2"

  name = "example"

  routes = {
    health = { route_key = "GET /health" }
  }
}
```

## Examples

<details>
<summary>A logged, throttled, IAM-authorized API with CORS</summary>

```hcl
module "api" {
  source = "kn47ytv9mv/apigatewayv2/aws"

  name = "example"

  integrations = {
    chat = { integration_uri = module.chat_function.invoke_arn }
  }

  routes = {
    chat = {
      route_key          = "POST /chat"
      integration_key    = "chat"
      authorization_type = "AWS_IAM"
    }
  }

  lambda_permissions = {
    chat = { function_name = module.chat_function.function_name }
  }

  access_log_destination_arn = module.api_logs.arn

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
```

</details>

<details>
<summary>A WebSocket API on a named stage</summary>

```hcl
module "api" {
  source = "kn47ytv9mv/apigatewayv2/aws"

  name                       = "example"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  integrations = {
    send = { integration_uri = module.send_function.invoke_arn }
  }

  routes = {
    connect    = { route_key = "$connect" }
    disconnect = { route_key = "$disconnect" }
    send       = { route_key = "send", integration_key = "send" }
  }

  lambda_permissions = {
    send = { function_name = module.send_function.function_name }
  }

  stage_name = "production"
}
```

`$connect` and `$disconnect` carry no integration here, so the API accepts
and closes connections without invoking anything. Give them an integration
to authorize a connection or to record one.

</details>

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| name | Name of the API. If null, a unique name is generated. | `null` | no |
| protocol_type | Whether this is an `HTTP` API or a `WEBSOCKET` API. | `"HTTP"` | no |
| description | Description of the API. | `null` | no |
| route_selection_expression | For a WebSocket API, the expression selecting which route handles a message. Required for `WEBSOCKET`, rejected for `HTTP`. | `null` | no |
| disable_execute_api_endpoint | Whether to disable the default `execute-api` endpoint, leaving the API reachable only through a custom domain. | `false` | no |
| cors_configuration | Cross-origin request policy. HTTP APIs only. | `null` | no |
| integrations | Backends the API forwards to, keyed by a name you choose. | `{}` | no |
| routes | Routes the API answers, keyed by a name you choose. | `{}` | no |
| lambda_permissions | Lambda functions this API is permitted to invoke, keyed by a name you choose. | `{}` | no |
| stage_name | Name of the stage. `$default` serves the API with no path prefix. | `"$default"` | no |
| auto_deploy | Whether a change to a route or integration deploys itself. | `true` | no |
| stage_variables | Key-value pairs readable from an integration as `$stageVariables.key`. | `null` | no |
| default_route_settings | Throttling and metrics applied to every route. | `null` | no |
| access_log_destination_arn | ARN of a CloudWatch log group receiving one record per request, from [`terraform-aws-cloudwatch-log-group`](https://github.com/kn47ytv9mv/terraform-aws-cloudwatch-log-group). | `null` | no |
| access_log_format | Format of each access log record, as a `$context` template. | a JSON record | no |
| tags | A map of tags to assign to the API and its stage. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the API. |
| arn | The ARN of the API. |
| name | The name of the API, generated when `name` was left null. |
| api_endpoint | The API's own `execute-api` hostname, with no stage path. |
| invoke_url | The URL to call, including the stage path when `stage_name` is not `$default`. |
| execution_arn | The ARN API Gateway invokes integrations under. |
| stage_arn | The ARN of the stage, which is what [`terraform-aws-wafv2-web-acl-association`](https://github.com/kn47ytv9mv/terraform-aws-wafv2-web-acl-association) takes as `resource_arn`. |
| stage_name | The name of the stage. |
| integration_ids | Map of the key you chose for each integration to that integration's ID. |
| route_ids | Map of the key you chose for each route to that route's ID. |

## License

MIT — see [LICENSE.md](LICENSE.md).
