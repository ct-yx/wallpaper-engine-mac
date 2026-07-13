# Releasing Open Wallpaper Engine

This project distributes GitHub Release archives with an ad-hoc macOS signature. This avoids the expiry of free Personal Team provisioning profiles without storing Apple ID credentials in CI.

## Create a release

1. Update `MARKETING_VERSION` in the Xcode project and the release heading in the README files.
2. Commit the release changes and push them to `main`.
3. Create and push a matching tag, for example:

   ```sh
   git tag v0.8.2
   git push origin v0.8.2
   ```

4. The `Release macOS app` workflow builds the app without an Apple development certificate, applies an ad-hoc signature, creates a ZIP archive and SHA-256 checksum, then publishes both to GitHub Releases.

For an existing tag, use the workflow's **Run workflow** action and enter that tag.

## Distribution characteristics

- The release signature does not expire after seven days.
- No Apple ID, provisioning profile or signing certificate is stored in GitHub Actions.
- The package is not notarized. Users may need to approve the first launch from macOS **Privacy & Security**.
- The SHA-256 checksum is published with every archive and should be verified before installation.

## Future notarized distribution

If a no-warning installation experience is required, use a paid Apple Developer Program membership with a Developer ID Application certificate and notarization. The release workflow can then be extended with repository secrets for the certificate and App Store Connect API credentials.
