# Privacy policy

Flare Status TV ("the app") is an Apple TV app that displays UptimeFlare
status pages. This policy covers the app. It was last updated on
24 November 2026.

## The short version

The app collects no data. Nothing you do in the app is sent to its developers
or to anyone else. The only servers the app talks to are the status pages you
tell it to show.

## What the app stores, and where

Everything the app stores stays on your Apple TV:

- the addresses of the status pages you add, and the user name for a page that
  is password protected, in the app's preferences;
- the password for a password-protected page, in the Apple TV's Keychain;
- your display settings (refresh interval, idle scrolling, page rotation), in
  the app's preferences.

Status data is held in memory while the app is open and is not saved.

Removing a page in Settings deletes its address and password. Deleting the app
deletes everything it stored.

## What leaves your Apple TV

The app makes ordinary web requests (HTTP `GET`) to the status pages you add,
and to no other server:

- the status page itself;
- its `/api/data` address;
- the page's own script files, from the same server, to read the page title
  and monitor groups.

As with any web request, the server you connect to sees your IP address and
the standard headers the system sends (such as the app's name and version and
your language). If the page is password protected, the request carries the
user name and password you entered, so that the page will answer. If a status
page redirects to another address, the app follows the redirect, as a web
browser would.

Those servers are run by whoever runs the status page, not by the developers
of this app. What they log is up to them.

## What the app does not do

- No accounts and no sign-in to any service of ours. We run no servers for
  this app.
- No analytics, no crash reporting of our own, no advertising, no tracking.
- No third-party code or SDKs.
- No access to your location, contacts, photos, microphone, camera or any
  other personal data.
- No device or advertising identifiers.

"Try with sample data" shows invented monitors that are built into the app. It
makes no network requests.

## Apple

If you have chosen to share analytics with app developers in your Apple TV's
settings, Apple may give us anonymous, aggregated usage and crash statistics
for the app. That is Apple's service, governed by Apple's privacy policy; the
app itself sends nothing.

## Children

The app has no content aimed at children and collects no data from anyone.

## Changes

If this policy changes, the new version will be published at this address,
with a new date at the top. The history of this file is public.

## Contact

Questions about this policy: open an issue at
<https://github.com/WoofyIO/flare-status-tv/issues>.
