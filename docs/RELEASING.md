# Releasing Lowdrift

Every commit on `main` is built once, by Xcode Cloud. Staging and prod never
rebuild: they find the build made from that commit and give it to more people.
So one build, such as `1.0.0 (57)`, keeps the same version and build number
from alpha to the App Store, and testers test the exact file that ships.

| Branch | Channel | What happens on a push | Git record |
| --- | --- | --- | --- |
| `main` | Alpha: internal TestFlight group "Alpha" | Xcode Cloud tests, archives, stamps the next build number, uploads, and sends it to "Alpha" with notes from `ci_scripts/ci_post_clone.sh` | none |
| `staging` | Beta: external TestFlight group "Beta" | `promote-beta.yml` finds the build of the merged main commit and adds it to "Beta" | tag `vX.Y.Z-beta.N` |
| `prod` | App Store | `promote-release.yml` submits that build for review, then tags and opens the next-version pull request | tag `vX.Y.Z`, GitHub Release |

## Versions

- **Version** (`MARKETING_VERSION`, shown on the App Store) lives only in
  `Config/Version.xcconfig`. It is `MAJOR.MINOR.PATCH`, digits and dots only.
  No target sets its own; the "Version check" CI job enforces both.
- **Main is always the next release.** After a submission, CI opens a pull
  request moving main to the next minor version. Before merging it, change it
  to the next patch for a fixes-only release, or the next major for a
  redesign, a one-way data change or a dropped iOS version:
  `scripts/release/bump-version.sh patch|minor|major|X.Y.Z`.
- **Build number** (`CURRENT_PROJECT_VERSION`) is Xcode Cloud's counter. It
  only goes up, across all versions. The repo keeps `1` as a placeholder and
  never commits a real one. Never upload Lowdrift any other way (Xcode
  Organizer, Transporter, fastlane): a build number Xcode Cloud doesn't know
  about makes its next upload fail with "bundle version must be higher".
- The channel is not part of the version (Apple allows only digits and dots).
  Alpha and beta are TestFlight groups; the release is an App Store submission.

## Shipping a release

1. Land work on `main` through pull requests. Each push produces an alpha
   build in TestFlight within about half an hour.
2. **Beta:** open a pull request from `main` into `staging` and merge it with
   **Create a merge commit**. The beta workflow waits (up to 30 minutes) for the
   build to finish processing, adds it to "Beta" with a list of changes, and
   tags `vX.Y.Z-beta.N`. The first build of each version waits for Beta App
   Review, which can take a day or more.
3. **Release:** open a pull request from `staging` into `prod` and merge it with
   **Create a merge commit**. The release workflow checks the version is above
   any version Apple has approved, submits the build for review, tags
   `vX.Y.Z`, creates the GitHub Release, and opens the next-version pull
   request on main.
4. Merge (or adjust, then merge) the next-version pull request.

Pull requests into `staging` must come from `main`, and into `prod` from
`staging` ("Promotion source" check). Squash or rebase merges would break the
link to the built commit, so only merge commits are allowed there.

## When something fails

- **"…differs from the main commit it merged"**: something reached staging or
  prod that main never built. Put the change on main, then promote again.
- **"no Xcode Cloud build run … yet" / timed out**: the main commit wasn't
  built (or is still building). Check Xcode Cloud, then re-run the workflow.
- **"expired"**: TestFlight builds last 90 days. Push a fresh commit to main
  and merge it into staging again.
- **"not above …, which Apple already approved"**: main still has the released
  version. Merge the next-version pull request, let Xcode Cloud build it, and
  promote that build.
- **Personal info check fails on a staging or prod pull request**: a merge was
  made with an account email that isn't private. Turn on "Keep my email
  addresses private" on GitHub before merging promotions in the web UI.
- To retry after fixing the cause, re-run the failed workflow run. The tag and
  release steps skip what already exists.

## One-time setup (owner)

1. **Build numbers:** in App Store Connect, note the highest build number of
   any Lowdrift build already uploaded. In Xcode Cloud settings, set **Next
   Build Number** above it.
2. **TestFlight groups:** an internal group "Alpha" and an external group
   "Beta" (other names: set the repository variable `BETA_GROUP`). Fill in
   TestFlight's Test Information (feedback email, beta description, review
   contact) once.
3. **Xcode Cloud workflow "Alpha":** start condition *Branch changes* on
   `main`; actions *Test* (Lowdrift scheme) and *Archive* (iOS, deployment
   preparation **TestFlight and App Store**, not "Internal Testing Only", or
   the build can never reach Beta or the App Store); post-action *TestFlight
   Internal Testing* to "Alpha". Turn off any other workflow that archives and
   uploads.
4. **Branches:** create `staging` and `prod` from `main`.
5. **Secrets** (repository → Settings → Secrets and variables → Actions):
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`: an App Store Connect API key with the App
     Manager role.
   - `ASC_KEY_P8_BASE64`: the key's `.p8` file, base64-encoded
     (`base64 -i AuthKey_XXXX.p8 | pbcopy`).
   - `RELEASE_PR_TOKEN` (recommended): a fine-grained token for this repository
     with Contents and Pull requests read/write, so the next-version pull
     request starts CI.
   - Optional variables: `BETA_GROUP`, `AUTOMATIC_RELEASE` (`false` holds an
     approved version for a manual release), `NEXT_VERSION_BUMP` (`patch` to
     default to fixes-only).
6. **Rulesets:** Settings → Rules → Rulesets → Import a ruleset, once for each
   file in `.github/rulesets/`. After the first Xcode Cloud build reports to a
   GitHub commit, add its check (named after the workflow) to the staging and
   prod rulesets' required checks, so a commit whose build failed can't be
   promoted.
7. **First App Store submission:** fill in the store listing, screenshots,
   privacy answers ("Data Not Collected") and age rating in App Store Connect.
   The release workflow submits the build but never uploads metadata.

## Files

| File | Role |
| --- | --- |
| `Config/Version.xcconfig` | The version, for every target |
| `ci_scripts/ci_post_clone.sh` | Xcode Cloud: TestFlight "What to Test" notes |
| `.github/workflows/ci.yml` | Tests and the version check on pull requests and main |
| `.github/workflows/promotion-guard.yml` | Only main → staging → prod |
| `.github/workflows/promote-beta.yml` | staging → TestFlight "Beta" |
| `.github/workflows/promote-release.yml` | prod → App Store review, tag, release, next version |
| `fastlane/Fastfile` | `find_build`, `promote_beta`, `promote_release` (no building or uploading) |
| `scripts/release/built-commit.sh` | From a staging/prod commit back to the main commit that was built |
| `scripts/release/bump-version.sh` | Sets the next version |
| `scripts/release/check-version.sh` | The "Version check" job |
| `.github/rulesets/*.json` | Branch rules to import |
