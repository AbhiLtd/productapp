# CI/CD: Maven build -> upload JAR -> multi-arch build & push to GHCR -> immutable promote dev->stage->prod
# This version uses the "dependency chain" approach: promote_to_stage exports outputs,
# promote_to_prod depends only on promote_to_stage and reads its outputs.
#
# Notes:
# - Provide GHCR_USERNAME & GHCR_PAT (recommended) in repository secrets; if not present, the workflow falls back to GITHUB_TOKEN.
# - Push/promote jobs are skipped for pull_request events (forked PRs mask secrets).
# - The workflow assumes a single runnable JAR is produced at target/*.jar.
name: Java CI/CD with Maven and GHCR (stable)

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

permissions:
  contents: read
  packages: write
  id-token: write

env:
  REGISTRY: ghcr.io
  PLATFORMS: linux/amd64,linux/arm64

jobs:
  build:
    name: Build (Maven) and set metadata
    runs-on: ubuntu-latest
    outputs:
      image_name: ${{ steps.set_image.outputs.image_name }}
      sha_tag: ${{ steps.set_tag.outputs.sha_tag }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: temurin
          cache: maven

      - name: Build with Maven
        run: mvn -B clean package -DskipTests

      - name: Set image sha tag
        id: set_tag
        run: |
          echo "sha_tag=$(echo ${GITHUB_SHA} | cut -c1-7)" >> $GITHUB_OUTPUT

      - name: Set lowercase image name (owner/repo -> lowercased)
        id: set_image
        run: |
          repo_lower=$(echo "${GITHUB_REPOSITORY}" | tr '[:upper:]' '[:lower:]')
          echo "image_name=${repo_lower}" >> $GITHUB_OUTPUT

      - name: Upload JAR artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-jar
          path: target/*.jar

  build_and_push_dev:
    name: Build & push Docker image (dev)
    if: ${{ github.event_name != 'pull_request' }}
    runs-on: ubuntu-latest
    needs: build
    environment: dev
    outputs:
      image_digest: ${{ steps.set_outputs.outputs.image_digest }}
      image_name: ${{ steps.set_outputs.outputs.image_name }}
      sha_tag: ${{ steps.set_outputs.outputs.sha_tag }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download artifact (JAR)
        uses: actions/download-artifact@v4
        with:
          name: app-jar
          path: ./artifact

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR (prefer PAT, fallback to GITHUB_TOKEN)
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.GHCR_USERNAME || github.actor }}
          password: ${{ secrets.GHCR_PAT || secrets.GITHUB_TOKEN }}

      - name: Build & push image (multi-arch) and capture digest
        id: build_image
        uses: docker/build-push-action@v4
        with:
          context: .
          file: ./Dockerfile
          push: true
          platforms: ${{ env.PLATFORMS }}
          tags: |
            ${{ env.REGISTRY }}/${{ needs.build.outputs.image_name }}:dev
            ${{ env.REGISTRY }}/${{ needs.build.outputs.image_name }}:${{ needs.build.outputs.sha_tag }}
          build-args: |
            JAR_FILE=artifact/*.jar
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Set job outputs (image metadata)
        id: set_outputs
        run: |
          DIGEST="${{ steps.build_image.outputs.digest }}"
          IMAGE_NAME="${{ needs.build.outputs.image_name }}"
          SHA_TAG="${{ needs.build.outputs.sha_tag }}"
          if [ -z "$DIGEST" ]; then
            echo "ERROR: build step produced empty digest" >&2
            exit 1
          fi
          echo "image_digest=${DIGEST}" >> $GITHUB_OUTPUT
          echo "image_name=${IMAGE_NAME}" >> $GITHUB_OUTPUT
          echo "sha_tag=${SHA_TAG}" >> $GITHUB_OUTPUT

      - name: Upload metadata artifact
        run: |
          echo "${{ steps.set_outputs.outputs.image_digest }}" > image-digest.txt || true
          printf '{"image":"%s","digest":"%s","sha_tag":"%s"}\n' "${{ env.REGISTRY }}/${{ steps.set_outputs.outputs.image_name }}" "${{ steps.set_outputs.outputs.image_digest }}" "${{ steps.set_outputs.outputs.sha_tag }}" > image-metadata.json || true
        shell: bash

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: image-metadata
          path: |
            image-digest.txt
            image-metadata.json

  promote_to_stage:
    name: Promote to stage (immutable via digest) and export outputs
    if: ${{ github.event_name != 'pull_request' }}
    runs-on: ubuntu-latest
    needs: build_and_push_dev
    environment: stage
    outputs:
      image_digest: ${{ steps.set_outputs.outputs.image_digest }}
      image_name: ${{ steps.set_outputs.outputs.image_name }}
      sha_tag: ${{ steps.set_outputs.outputs.sha_tag }}
    steps:
      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.GHCR_USERNAME || github.actor }}
          password: ${{ secrets.GHCR_PAT || secrets.GITHUB_TOKEN }}

      - name: Pull by digest and push stage & sha tags
        id: promote_stage
        run: |
          set -e
          REG="${{ env.REGISTRY }}"
          IMG="${{ needs.build_and_push_dev.outputs.image_name }}"
          DIGEST="${{ needs.build_and_push_dev.outputs.image_digest }}"
          SHA_TAG="${{ needs.build_and_push_dev.outputs.sha_tag }}"

          echo "Promoting digest: ${DIGEST}"
          if [ -z "$IMG" ] || [ -z "$DIGEST" ]; then
            echo "ERROR: IMG or DIGEST is empty. IMG='$IMG' DIGEST='$DIGEST'"
            exit 1
          fi

          docker pull "${REG}/${IMG}@${DIGEST}"
          docker tag "${REG}/${IMG}@${DIGEST}" "${REG}/${IMG}:stage"
          docker tag "${REG}/${IMG}@${DIGEST}" "${REG}/${IMG}:${SHA_TAG}"
          docker push "${REG}/${IMG}:stage"
          docker push "${REG}/${IMG}:${SHA_TAG}"

      - name: Set outputs for promote_to_stage
        id: set_outputs
        run: |
          echo "image_digest=${{ needs.build_and_push_dev.outputs.image_digest }}" >> $GITHUB_OUTPUT
          echo "image_name=${{ needs.build_and_push_dev.outputs.image_name }}" >> $GITHUB_OUTPUT
          echo "sha_tag=${{ needs.build_and_push_dev.outputs.sha_tag }}" >> $GITHUB_OUTPUT

  promote_to_prod:
    name: Promote to prod (immutable via digest)
    if: ${{ github.event_name != 'pull_request' }}
    runs-on: ubuntu-latest
    needs: promote_to_stage
    environment: prod
    steps:
      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.GHCR_USERNAME || github.actor }}
          password: ${{ secrets.GHCR_PAT || secrets.GITHUB_TOKEN }}

      - name: Pull by digest and push prod & sha tags
        run: |
          set -e
          REG="${{ env.REGISTRY }}"
          IMG="${{ needs.promote_to_stage.outputs.image_name }}"
          DIGEST="${{ needs.promote_to_stage.outputs.image_digest }}"
          SHA_TAG="${{ needs.promote_to_stage.outputs.sha_tag }}"

          echo "Promoting digest: ${DIGEST}"
          if [ -z "$IMG" ] || [ -z "$DIGEST" ]; then
            echo "ERROR: IMG or DIGEST is empty. IMG='$IMG' DIGEST='$DIGEST'"
            exit 1
          fi

          docker pull "${REG}/${IMG}@${DIGEST}"
          docker tag "${REG}/${IMG}@${DIGEST}" "${REG}/${IMG}:prod"
          docker tag "${REG}/${IMG}@${DIGEST}" "${REG}/${IMG}:${SHA_TAG}"
          docker push "${REG}/${IMG}:prod"
          docker push "${REG}/${IMG}:${SHA_TAG}"
