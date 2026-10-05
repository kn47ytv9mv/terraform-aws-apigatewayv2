variable "name" {
  default     = null
  description = "Name of the API. If null, a unique name is generated."
}

variable "protocol_type" {
  default     = "HTTP"
  description = "Whether this is an 'HTTP' API or a 'WEBSOCKET' API. An HTTP API routes on method and path; a WebSocket API holds the connection open and routes on a field of each message."

  validation {
    condition     = contains(["HTTP", "WEBSOCKET"], var.protocol_type)
    error_message = "protocol_type must be 'HTTP' or 'WEBSOCKET'."
  }

  validation {
    condition     = var.protocol_type != "WEBSOCKET" || var.route_selection_expression != null
    error_message = "A WEBSOCKET API requires route_selection_expression, which names the field of an incoming message that selects the route."
  }

  validation {
    condition     = var.protocol_type != "HTTP" || var.route_selection_expression == null
    error_message = "route_selection_expression applies only to a WEBSOCKET API. An HTTP API selects its route from the method and path in route_key."
  }

  validation {
    condition     = var.protocol_type != "WEBSOCKET" || var.cors_configuration == null
    error_message = "cors_configuration applies only to an HTTP API. CORS is a browser mechanism for cross-origin HTTP requests and has no meaning for a WebSocket connection."
  }
}

variable "description" {
  default     = null
  description = "Description of the API."
}

variable "route_selection_expression" {
  default     = null
  description = "For a WEBSOCKET API, the expression selecting which route handles a message, conventionally '$request.body.action'. Required for a WEBSOCKET API and rejected for an HTTP one."
}

variable "disable_execute_api_endpoint" {
  default     = false
  description = "Whether to disable the default 'execute-api' endpoint, leaving the API reachable only through a custom domain. Set this once a custom domain is in place, or the API becomes unreachable."
}

variable "cors_configuration" {
  default     = null
  description = "Cross-origin request policy, applied by API Gateway before the request reaches an integration. If null, no CORS headers are added and a browser refuses every cross-origin call. HTTP APIs only — see the Design section for the credentials restriction."
  type = object({
    allow_origins     = optional(list(string))
    allow_methods     = optional(list(string))
    allow_headers     = optional(list(string))
    expose_headers    = optional(list(string))
    allow_credentials = optional(bool)
    max_age           = optional(number)
  })
}

variable "integrations" {
  default     = {}
  description = <<-EOT
    Backends the API forwards requests to, keyed by a name you choose. The key identifies the integration in state and is what a route's integration_key refers to, so it must be a value you write, not one read from another resource.

    integration_uri is the Lambda invoke ARN for 'AWS_PROXY', or the URL for 'HTTP_PROXY'. payload_format_version is sent only for an HTTP API, where '2.0' is the current event shape; a WebSocket API has no payload format and the module omits it.
  EOT
  type = map(object({
    integration_type       = optional(string, "AWS_PROXY")
    integration_uri        = optional(string)
    integration_method     = optional(string)
    payload_format_version = optional(string, "2.0")
    timeout_milliseconds   = optional(number)
    connection_type        = optional(string)
    connection_id          = optional(string)
    request_parameters     = optional(map(string))
  }))

  validation {
    condition     = alltrue([for i in var.integrations : contains(["AWS_PROXY", "HTTP_PROXY", "MOCK", "AWS"], i.integration_type)])
    error_message = "Each integration_type must be 'AWS_PROXY', 'HTTP_PROXY', 'MOCK', or 'AWS'."
  }

  validation {
    condition     = alltrue([for i in var.integrations : i.integration_type == "MOCK" || i.integration_uri != null])
    error_message = "Every integration except a 'MOCK' one requires integration_uri — the Lambda invoke ARN for 'AWS_PROXY', or the URL for 'HTTP_PROXY'."
  }
}

variable "routes" {
  default     = {}
  description = <<-EOT
    Routes the API answers, keyed by a name you choose. The key identifies the route in state, so adding one leaves the others untouched — and it must be a value you write, not one read from another resource.

    route_key is 'METHOD /path' for an HTTP API ('POST /chat'), or the message action for a WebSocket one. '$default' catches everything unmatched. integration_key names an entry in integrations; a route without one returns an error to the caller, which is only useful for a placeholder.
  EOT
  type = map(object({
    route_key          = string
    integration_key    = optional(string)
    authorization_type = optional(string, "NONE")
    authorizer_id      = optional(string)
    api_key_required   = optional(bool)
  }))

  validation {
    condition     = alltrue([for r in var.routes : r.integration_key == null || contains(keys(var.integrations), r.integration_key)])
    error_message = "Every route's integration_key must name an entry in integrations."
  }

  validation {
    condition     = alltrue([for r in var.routes : contains(["NONE", "AWS_IAM", "JWT", "CUSTOM"], r.authorization_type)])
    error_message = "Each authorization_type must be 'NONE', 'AWS_IAM', 'JWT', or 'CUSTOM'. 'NONE' leaves the route open to the internet."
  }

  validation {
    condition     = alltrue([for r in var.routes : !contains(["JWT", "CUSTOM"], r.authorization_type) || r.authorizer_id != null])
    error_message = "A route with authorization_type 'JWT' or 'CUSTOM' requires authorizer_id naming the authorizer that evaluates the request."
  }
}

variable "lambda_permissions" {
  default     = {}
  description = <<-EOT
    Lambda functions this API is permitted to invoke, keyed by a name you choose. A Lambda integration fails at runtime with a 500 until this permission exists, because API Gateway invokes the function as a separate principal rather than through the caller's credentials.

    function_name is the function's name or ARN, from terraform-aws-lambda-function's function_name output. qualifier names a published version or alias when the integration targets one. The module scopes each permission to this API's own execution ARN, so a permission granted here does not let any other API invoke the function.
  EOT
  type = map(object({
    function_name = string
    qualifier     = optional(string)
  }))
}

variable "stage_name" {
  default     = "$default"
  description = "Name of the stage. '$default' serves the API at the bare endpoint with no path prefix; any other name appends itself to the URL. A stage is required — an API with none cannot be called."
}

variable "auto_deploy" {
  default     = true
  description = "Whether a change to a route or integration deploys itself. With this false, a deployment has to be created separately and the API serves its previous configuration until then."
}

variable "stage_variables" {
  default     = null
  description = "Key-value pairs readable from an integration as '$stageVariables.key', for varying a backend between stages."
}

variable "default_route_settings" {
  default     = null
  description = "Throttling and metrics applied to every route. If null, the API is subject only to the account-level API Gateway throttle, which a single misbehaving client can consume."
  type = object({
    throttling_burst_limit   = optional(number)
    throttling_rate_limit    = optional(number)
    detailed_metrics_enabled = optional(bool)
  })
}

variable "access_log_destination_arn" {
  default     = null
  description = "ARN of a CloudWatch log group receiving one record per request, from terraform-aws-cloudwatch-log-group. If null, the API keeps no request log and a failing call leaves no trace. API Gateway needs no role for this; it writes to the group directly."
}

variable "access_log_format" {
  default     = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"routeKey\":\"$context.routeKey\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\",\"integrationErrorMessage\":\"$context.integrationErrorMessage\"}"
  description = "Format of each access log record, as a '$context' template. Only used when access_log_destination_arn is set. The default emits JSON including integrationErrorMessage, which is where an integration's own failure is reported."
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the API and its stage."
}
