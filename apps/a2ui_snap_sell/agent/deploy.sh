#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Deployment Script for Snap Sell Agent to Cloud Run via Cloud Build
#
# Instructions:
# 1. Grant execute permissions:
#      chmod +x apps/a2ui_snap_sell/agent/deploy.sh
#
# 2. Run the deployment:
#      cd apps/a2ui_snap_sell/agent && ./deploy.sh
#    or from workspace root:
#      ./apps/a2ui_snap_sell/agent/deploy.sh
#

set -euo pipefail

# Ensure the script runs from the agent directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=========================================================="
echo "Deploying Snap Sell Agent to Cloud Run via Cloud Build"
echo "Directory: ${SCRIPT_DIR}"
echo "Project:   devhack-3f0c2"
echo "=========================================================="

# Capture COMMIT_SHA if available from git or environment for tagging
COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo '')}"

if [ -n "${COMMIT_SHA}" ]; then
  echo "Using COMMIT_SHA: ${COMMIT_SHA}"
  exec gcloud builds submit \
    --config=cloudbuild.yaml \
    --project=devhack-3f0c2 \
    --substitutions=COMMIT_SHA="${COMMIT_SHA}" \
    .
else
  exec gcloud builds submit \
    --config=cloudbuild.yaml \
    --project=devhack-3f0c2 \
    .
fi
