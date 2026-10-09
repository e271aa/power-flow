PowerFlow is a menu bar app that shows where your Mac's power goes, in watts: what comes in through the adapter, what goes into or out of the battery, and what the system uses. It only reads sensors; it never changes how the battery charges.

**Requirements:** an Apple Silicon Mac with macOS 13 or later.

**Install**

1. Download the `.dmg` below, open it and drag **PowerFlow** onto **Applications**.
2. Open PowerFlow from Applications. It is signed ad hoc and not notarized, so the first time macOS will not open it. Go to **System Settings › Privacy & Security**, click **Open Anyway** next to the message about PowerFlow, and confirm. You only do this once.

To check the download, put the `.sha256` file next to the `.dmg` and run `shasum -a 256 -c PowerFlow-*.dmg.sha256`.
