# Vertex AI REST Setup

Use this path if you want Beeamvo to call Vertex AI directly through your own Google Cloud project.

## How it works

Beeamvo talks directly to the Vertex AI REST API using your machine's Application Default Credentials. No additional SDKs, config files, or service-account JSON files are required.

## What you need

- Your own Google Cloud project
- Billing enabled on that project
- Vertex AI enabled
- A project ID
- Application Default Credentials (ADC)

## Setup

1. Create or choose a Google Cloud project.
2. Enable Vertex AI for that project.
3. Configure Application Default Credentials on the machine:

   ```bash
   gcloud auth application-default login
   ```

   or set `GOOGLE_APPLICATION_CREDENTIALS` to a credential file path.

4. Start Beeamvo.
5. Open Settings -> Intelligence.
6. Keep `Processing Engine` on `Cloud`.
7. Set `Cloud Provider` to `Vertex AI`.
8. Set your Google Cloud project ID. For development-only overrides, you can alternatively set `VERTEX_PROJECT_ID` in `.env`.
9. Click `Verify`.

## Notes

- Beeamvo uses direct `generateContent` REST calls for Vertex AI.
- ADC does not store a credential secret inside the app.
- The current model list uses the model's configured Vertex location, which is `global` for the public defaults.
- `.env` is for local debug/development overrides only and is ignored in release builds. Prefer UI settings and OS secure storage for app configuration used day to day.

## Troubleshooting

- `Set a Vertex AI project ID in Settings before using Vertex.`
  You have not saved the Google Cloud project ID yet.
- `Vertex ADC is not configured.`
  Run `gcloud auth application-default login` or set `GOOGLE_APPLICATION_CREDENTIALS`.
- Vertex verification fails with a permission or billing error
  Confirm the project exists, Vertex AI is enabled, and billing is active.
