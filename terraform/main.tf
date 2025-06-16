provider "aws" {
  region = "us-east-1"
}

# === IAM Role for Lambda ===
resource "aws_iam_role" "lambda_exec_role" {
  name = "mythical_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_logs" {
  name       = "attach-lambda-logs"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# === S3 Bucket ===
resource "aws_s3_bucket" "data_bucket" {
  bucket = "mythical-realms-data-${random_id.suffix.hex}"
  force_destroy = true
}

resource "random_id" "suffix" {
  byte_length = 4
}

# === DynamoDB Table ===
resource "aws_dynamodb_table" "guest_flow" {
  name         = "MythicalGuestFlow"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ride_id"

  attribute {
    name = "ride_id"
    type = "S"
  }
}

# === Lambda Function ===

# Lambda Zip Packaging
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/lambda_function.py"
  output_path = "${path.module}/../lambda/lambda_function.zip"
}

resource "aws_lambda_function" "predict_wait_time" {
  function_name    = "predictWaitTime"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.guest_flow.name
      BUCKET_NAME    = aws_s3_bucket.data_bucket.bucket
    }
  }
}

# === API Gateway ===
resource "aws_apigatewayv2_api" "http_api" {
  name          = "predict-api"
  protocol_type = "HTTP"
}

# Lambda Permission to allow API Gateway invocation
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.predict_wait_time.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Lambda Integration
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.predict_wait_time.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# Route to Lambda (GET /predict)
resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /predict"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Default Stage with Auto Deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# === Outputs ===
output "api_endpoint" {
  value = "${aws_apigatewayv2_api.http_api.api_endpoint}/predict"
}
