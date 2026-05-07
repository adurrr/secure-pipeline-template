#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: deploy.sh <environment> <image_tag>}"
IMAGE_TAG="${2:?Usage: deploy.sh <environment> <image_tag>}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Deploying $IMAGE_TAG to $ENVIRONMENT..."

case "$ENVIRONMENT" in
    local)
        # Local / on-premise deployment via Docker Compose
        cd "$ROOT"
        COMPOSE_CMD="docker compose"
        if ! $COMPOSE_CMD version &>/dev/null; then
            COMPOSE_CMD="docker-compose"
        fi
        IMAGE_TAG="$IMAGE_TAG" $COMPOSE_CMD up -d --build
        echo "Deployed locally. Health check: https://localhost/healthz"
        ;;
    staging|production)
        # AWS ECS deployment
        CLUSTER="${APP_NAME:-secure-pipeline}-${ENVIRONMENT}"
        SERVICE="${APP_NAME:-secure-pipeline}-${ENVIRONMENT}"
        ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME:-secure-pipeline}"
        LOCAL_IMAGE="${IMAGE_NAME:-secure-pipeline-template}:${IMAGE_TAG}"

        aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO"

        docker tag "$LOCAL_IMAGE" "$ECR_REPO:$IMAGE_TAG"
        docker push "$ECR_REPO:$IMAGE_TAG"

        TASK_DEF=$(aws ecs describe-task-definition \
            --task-definition "${APP_NAME:-secure-pipeline}-${ENVIRONMENT}" \
            --region "$AWS_REGION" \
            --query 'taskDefinition' \
            --output json)

        NEW_TASK_DEF=$(echo "$TASK_DEF" | jq \
            --arg IMAGE "$ECR_REPO:$IMAGE_TAG" \
            '.containerDefinitions[0].image = $IMAGE | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

        NEW_REVISION=$(aws ecs register-task-definition \
            --cli-input-json "$NEW_TASK_DEF" \
            --region "$AWS_REGION" \
            --query 'taskDefinition.taskDefinitionArn' \
            --output text)

        aws ecs update-service \
            --cluster "$CLUSTER" \
            --service "$SERVICE" \
            --task-definition "$NEW_REVISION" \
            --region "$AWS_REGION"

        echo "Deployment triggered. Waiting for stabilization..."
        aws ecs wait services-stable \
            --cluster "$CLUSTER" \
            --services "$SERVICE" \
            --region "$AWS_REGION"

        echo "Deployed $IMAGE_TAG to $ENVIRONMENT successfully."
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        echo "Valid options: local, staging, production"
        exit 1
        ;;
esac
