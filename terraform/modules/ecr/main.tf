resource "aws_ecr_repository" "main" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  // One rule per tag prefix so that pushing proxy revisions never evicts the
  // expensive vllm image (10-15 min rebuild because of the baked Gemma weights).
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 vllm images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["vllm"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 proxy images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["proxy"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = { type = "expire" }
      },
      // Both rules above select tagStatus = "tagged", and only one image ever holds
      // :vllm or :proxy at a time, so neither can reach a count of five and neither
      // ever fires. Re-pushing a mutable tag moves it and leaves the previous image
      // UNTAGGED, which a "tagged" rule can never select — so every rebuild used to
      // strand another ~18 GB in the repository permanently. This is the rule that
      // actually reclaims anything.
      {
        rulePriority = 3
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}