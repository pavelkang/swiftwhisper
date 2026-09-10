# SwiftWhisper 0.1.0 beta distribution

## Current status

The Release candidate targets Apple silicon, macOS 26 or later, version 0.1.0, build 2. The archive is built with signing disabled so compilation can be verified independently of missing distribution credentials. It is not a public-ready download.

Release archive compilation and diagnostics smoke checks passed. Bundle inspection confirmed version 0.1.0, build 2, minimum macOS 26.0, and eeveearchie@gmail.com. The custom support field now comes from Configuration/MacInfo.plist because the generated Info.plist omitted the custom INFOPLIST_KEY setting. The local candidate is build/beta/0.1.0-2/SwiftWhisper-0.1.0-2-UNSIGNED.zip; it is approximately 20 MB. A checksum is stored beside it. The blog's MDX compilation, frontmatter, and image references were checked.

The available signing identities are Apple Development identities. A Developer ID Application certificate and its private key are still needed for team TYS32Z4DEC, along with compatible iCloud distribution provisioning and configured notarization credentials. The public support email is eeveearchie@gmail.com. Do not publish the unsigned candidate or the existing build/SwiftWhisper-Release.zip as a verified release.

## Hosting

Use the existing repository's [GitHub Releases](https://github.com/pavelkang/swiftwhisper/releases) for the final ZIP and SHA-256 checksum. Keep the product story and installation instructions on coding-collie. GitHub supports release binaries smaller than 2 GiB per file; see [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).

The repository is now verified as PUBLIC. Host the final ZIP and checksum directly at https://github.com/pavelkang/swiftwhisper/releases; no separate download repository is needed.

Use a versioned release tag such as v0.1.0-beta.1 and mark the release as a prerelease. Upload only SwiftWhisper-Beta.zip and SwiftWhisper-Beta.zip.sha256. Keep archives, symbols, intermediate uploads, and signing details private. No release has been uploaded by this workflow.

## Finish distribution

1. Install Developer ID Application signing credentials in Xcode and verify iCloud provisioning for com.swiftwhisper.app.
2. Supply the public support email, then prepare a new build (build 3, since build 2 is the unsigned compilation candidate):

   ```sh
   Scripts/release-beta.sh prepare 0.1.0 3 eeveearchie@gmail.com
   ```

3. Configure an Apple notarization Keychain profile locally and run:

   ```sh
   Scripts/release-beta.sh notarize build/beta/0.1.0-3 YOUR_KEYCHAIN_PROFILE
   ```

4. Complete the dependency/model attribution review and clean-Mac checks in BETA_RELEASE.md. Apple describes the signing and notarization requirements in [Developer ID distribution](https://developer.apple.com/developer-id/).
5. Upload the verified final ZIP and checksum to GitHub Releases. Check the download while signed out to confirm public access, then test that downloaded copy on another Mac.
6. Update the blog's beta-status section with the actual download link, version, size, and support address. Change draft to false when ready to publish.

The blog draft is at ~/Documents/coding_collie/data/blog/swiftwhisper-local-dictation.md. The existing blog directory uses an underscore, not a hyphen.
