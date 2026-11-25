# Help and support

Flare Status TV shows an [UptimeFlare](https://github.com/lyc8503/UptimeFlare)
status page on an Apple TV. It is an unofficial viewer: you need your own
UptimeFlare deployment (or the address of one) for it to show real data.

## Getting help

Open an issue at <https://github.com/WoofyIO/flare-status-tv/issues>. Say what
you did, what you expected and what happened, and which version of the app you
have (Settings > About Flare Status). Please do not post passwords or the
address of a private status page.

## Common questions

**What do I type on the first screen?**
The address you open in a web browser to see your status page, for example
`status.example.com`. When the text field is selected, a nearby iPhone offers
its keyboard.

**I do not have a status page. Can I still look at the app?**
Yes. Choose **Try with sample data** on the first screen. The monitors are
invented and the dashboard says so. Select the **Sample data** badge at the
top of the dashboard, or **Leave sample data** in Settings, to go back.

**It says "This is not an UptimeFlare status page".**
The address answered, but not with an UptimeFlare page. Check that it is the
status page itself and not, say, the site being monitored.

**It says "This status page needs a password".**
The deployment sets `passwordProtection: 'user:password'`. Enter the two
halves as user name and password.

**It says "Cannot reach the status page".**
Check that the Apple TV is online and that the address opens in a browser on
the same network. Plain `http` is accepted only for addresses on your local
network; everything else must be `https`.

**The monitors are not in groups, or the title is the address.**
UptimeFlare publishes the title and groups only inside the page's compiled
script. If the app cannot find them there it shows the monitors ungrouped.
Please open an issue; say which UptimeFlare version you run.

**The banner turned amber and says the data is stale.**
The status page has not been updated by its UptimeFlare worker for more than
five minutes, or the Apple TV could not reach it. The last data stays on
screen and the app keeps trying.

**How do I change the refresh interval, add another page, or stop the idle
scrolling?**
Select the gear in the top right corner of the dashboard.

**How do I remove everything the app stored?**
Remove your pages in Settings, or delete the app.

## Privacy

See the [privacy policy](PRIVACY.md). In short: the app collects no data and
talks only to the status pages you add.
