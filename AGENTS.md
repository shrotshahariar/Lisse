# Lisse release routine

The owner wants every new Lisse release published to `shrotshahariar/Lisse` on GitHub only. Do not install or launch releases on their Mac unless they explicitly ask again.

- Increase the app version and build number, add `releases/vVERSION.md`, run the scroll regression checks, and build the universal app.
- Commit the source and push a matching `vVERSION` tag. The release workflow builds, checks, and publishes `Lisse.zip`. Verify the published release and downloadable asset; a draft or a queued workflow is not completion.
- Preserve source code, settings, icon sources, and release ZIPs. The user requested local uninstallation; do not reinstall automatically.
- These are release completion steps, not a request to install a background updater or to publish every source edit.
