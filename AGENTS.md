# Lisse release routine

The owner wants every new Lisse release published to `shrotshahariar/Lisse` on GitHub and the latest copy installed on their Mac.

- Increase the app version and build number, add `releases/vVERSION.md`, run the scroll regression checks, and build the universal app.
- Commit the source and push a matching `vVERSION` tag. The release workflow builds, checks, and publishes `Lisse.zip`. Verify the published release and downloadable asset; a draft or a queued workflow is not completion.
- Install the verified release at `/Applications/Lisse.app`. Verify the installed version and executable against the released ZIP, and launch that exact path.
- Keep a single installed Lisse copy. After the new copy is verified, stop older Lisse processes and move other positively identified Lisse app bundles to Trash. Preserve source code, settings, icon sources, and release ZIPs. Never remove unrelated apps.
- Keep scrolling paused during replacement. Check permissions on the installed copy and use the 30-second trial for a hands-on scroll check before claiming the scroll feel is verified.
- These are release completion steps, not a request to install a background updater or to publish every source edit.
