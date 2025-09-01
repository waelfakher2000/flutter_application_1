<#
PowerShell deploy script for the mqtt-fcm-bridge to Google Cloud Run.
Edit the variables below if needed, then run this script from PowerShell:

    cd mqtt-fcm-bridge
    ./deploy-cloudrun.ps1

This script assumes you have gcloud installed and authenticated, and that
service-account.json is present in this folder.
#>

param(
    [string]$PROJECT = 'liquid-level-3abd4',
    [string]$REGION = 'us-central1',
    [string]$SECRET_NAME = 'mqtt-firebase-sa',
    [string]$SERVICE_ACCOUNT_FILE = "$(Join-Path $PSScriptRoot 'service-account.json')",
    [string]$IMAGE = "gcr.io/liquid-level-3abd4/mqtt-bridge",
    [string]$SERVICE = 'mqtt-bridge'
)

Write-Host "Project: $PROJECT"
Write-Host "Region: $REGION"
Write-Host "Service account file: $SERVICE_ACCOUNT_FILE"

# Check prerequisites
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error "gcloud CLI not found in PATH. Install Cloud SDK: https://cloud.google.com/sdk/docs/install"
    exit 1
}

# Set project and enable APIs
gcloud config set project $PROJECT
gcloud services enable run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com --project=$PROJECT

# Create secret if missing
try {
    gcloud secrets describe $SECRET_NAME --project=$PROJECT --format='value(name)' | Out-Null
    Write-Host "Secret '$SECRET_NAME' already exists"
} catch {
    Write-Host "Creating secret '$SECRET_NAME'..."
    gcloud secrets create $SECRET_NAME --replication-policy="automatic" --project=$PROJECT
}

# Add service account JSON as a new secret version
Write-Host "Uploading service account to Secret Manager..."
gcloud secrets versions add $SECRET_NAME --data-file="$SERVICE_ACCOUNT_FILE" --project=$PROJECT

# Build and push container
Write-Host "Building and pushing container image: $IMAGE"
gcloud builds submit --tag $IMAGE --project=$PROJECT

# Deploy to Cloud Run (public)
Write-Host "Deploying to Cloud Run as service '$SERVICE' (public)..."
gcloud run deploy $SERVICE --image $IMAGE --platform managed --region $REGION --allow-unauthenticated `
    --set-secrets "SERVICE_ACCOUNT_JSON=$SECRET_NAME:latest" `
    --update-env-vars "HTTP_PORT=3000,MQTT_URL=mqtt://mqtt.mautoiot.com:1883,MQTT_DEFAULT_TOPIC=#" `
    --project=$PROJECT

# Fetch URL
$svcUrl = (& gcloud run services describe $SERVICE --region=$REGION --platform=managed --project=$PROJECT --format='value(status.url)')
Write-Host "\nService URL: $svcUrl\n"

# Quick checks
Write-Host "Health check (should return 'ok'):"
try { Invoke-RestMethod -Uri "$svcUrl/health" -UseBasicParsing | Write-Host } catch { Write-Host "Health check failed: $_" }

Write-Host "Status (registered devices):"
try { Invoke-RestMethod -Uri "$svcUrl/status" -UseBasicParsing | ConvertTo-Json -Depth 4 | Write-Host } catch { Write-Host "Status check failed: $_" }

Write-Host "\nIf deployment succeeded, copy the Service URL into the app DebugPage Bridge URL field and press 'Save' then 'Register Now' on your phone to register the device.\n"
