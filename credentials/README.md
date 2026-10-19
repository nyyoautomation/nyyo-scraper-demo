# Your Google credentials (optional, only for the Google Sheets export)

Put **your own** Google service-account key here as `service-account.json`. It never leaves your computer
and the kit never uploads it anywhere except to Google when it writes to your sheet.

1. Go to https://console.cloud.google.com/ and create a project (any name).
2. **APIs & Services > Library**: enable **Google Sheets API**.
3. **APIs & Services > Credentials > Create credentials > Service account**. Any name, no role needed. Done.
4. Open the service account > **Keys > Add key > Create new key > JSON**. A `.json` file downloads.
5. Rename it `service-account.json` and move it into this `credentials` folder.
6. Open the JSON, copy the `client_email` value (ends with `iam.gserviceaccount.com`).
7. Open your Google Sheet > **Share** > paste that address > **Editor** > Send.
8. In `config/scrape.toml`: `enabled = true` and paste the sheet id into `spreadsheet_id`.

Each target goes to its own tab (named like the target). The tab is replaced on every run, never appended,
so running again does not duplicate rows. Keep this file private: do not e-mail it or commit it to git.
