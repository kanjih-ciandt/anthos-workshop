#!/usr/bin/env bash

# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

REGION=us-central1
SERVICE_NAME=cloud-run-vision
PROJECT_ID=$(gcloud config list --format 'value(core.project)')
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

echo "###"
echo "# Creating a new repo and build triggers for the Cloud Run app"
echo "###"

# some simple navigation of the directory structure
SOURCE_PATH=$(pwd)
PARENT_PATH_1=$(dirname $(pwd))
PARENT_PATH_2=$(dirname $PARENT_PATH_1)
PARENT_PATH_3=$(dirname $PARENT_PATH_2)

echo "Enabling Cloud Build API"
gcloud services enable cloudbuild.googleapis.com
echo "Enabling Cloud Source Repositories API"
gcloud services enable sourcerepo.googleapis.com

echo "Adding Cloud Run admin permissions to Cloud Build service account"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
  --role roles/run.admin

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
  --role roles/iam.serviceAccountUser

echo "Creating repo $SERVICE_NAME-$PROJECT_ID"
gcloud source repos create $SERVICE_NAME-$PROJECT_ID

echo "Creating directory $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID"
cd $PARENT_PATH_3
gcloud source repos clone $SERVICE_NAME-$PROJECT_ID --project=$PROJECT_ID

echo "Copying local source files to $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID"
cp $SOURCE_PATH/src/* $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID/

cat <<EOF > $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID/cloud-build-trigger.json
{
  "triggerTemplate": {
    "projectId": "${PROJECT_ID}",
    "repoName": "${SERVICE_NAME}-${PROJECT_ID}",
    "branchName": "master"
  },
  "description": "cloud-run-deployment",
  "filename": "cloudbuild.yaml"
}
EOF

echo "Create .gitignore"
touch $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID/.gitignore
echo 'go.sum' >> $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID/.gitignore

echo "Removing any existing build triggers for the $SERVICE_NAME-$PROJECT_ID CSR repo"
GET_RESULT=$(curl -X GET \
    https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth application-default print-access-token)")

TRIGGER_TEMPLATE_IDS=$(echo $GET_RESULT | jq --arg REPO_NAME "${SERVICE_NAME}-${PROJECT_ID}" '.triggers[] | {id: .id, repoName: .triggerTemplate.repoName} | select(.repoName | contains($REPO_NAME)) | .id')

for value in $TRIGGER_TEMPLATE_IDS
do
    TRIMMED=$(sed -e 's/^"//' -e 's/"$//' <<<"$value")
    #echo $TRIMMED
    curl -X DELETE \
      https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers/${TRIMMED} \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(gcloud auth application-default print-access-token)"
done

echo "Creating build triggers for the $SERVICE_NAME-$PROJECT_ID CSR repo"
cd $PARENT_PATH_3/$SERVICE_NAME-$PROJECT_ID
curl -X POST \
    https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    --data-binary @cloud-build-trigger.json

echo "Now ready for commits to $SERVICE_NAME-$PROJECT_ID"