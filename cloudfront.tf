resource "aws_cloudfront_origin_access_identity" "static_file_host" {
  comment = "${var.service_name} ${terraform.workspace} web front"
}

resource "aws_cloudfront_distribution" "web_front" {
  depends_on = [aws_lb.web_api]
  aliases    = [local.domain[terraform.workspace]["domain_name"]]

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.service_name} ${terraform.workspace} web front contents delivery network"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.static_file_host.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_file_host.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_file_host.cloudfront_access_identity_path
    }
  }
  origin {
    domain_name = aws_lb.web_api.dns_name
    origin_id   = "ALB-${terraform.workspace}.${var.service_name}.${var.domain_name}"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "match-viewer"
      origin_read_timeout      = 30
      origin_ssl_protocols     = [
          "TLSv1",
          "TLSv1.1",
          "TLSv1.2",
      ]
    }

    custom_header {
      name  = "x-pre-shared-key"
      value = var.custom_header_value_via_cloudfront
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.static_file_host.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "POST", "PATCH", "PUT", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ALB-${terraform.workspace}.${var.service_name}.${var.domain_name}"

    forwarded_values {
      # Cache Based on Selected Request Headers
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    min_ttl                = 0
    max_ttl                = 0
    default_ttl            = 0
    compress               = false
    viewer_protocol_policy = "redirect-to-https"
  }

  # to enable SPA reloading
  custom_error_response {
    error_code = 403
    response_page_path = "/"
    response_code = 200
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_200"

  viewer_certificate {
    # cloudfront_default_certificate = true
    acm_certificate_arn      = aws_acm_certificate.cloudfront.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }
}

output "cloud_front_distribution_domain_name" {
  value = aws_cloudfront_distribution.web_front.domain_name
}
