# Connecting your accounts

Crossroads reads Google Calendar, Gmail and iCloud Calendar. Nothing is shared with a Crossroads server, because there isn't one: you bring your own Google app, your own iCloud password, and everything stays on your machine.

This takes about 15 minutes the first time. Most of it is Google.

- [How it fits together](#how-it-fits-together)
- [Google Calendar and Gmail](#google-calendar-and-gmail)
- [A work calendar you can't connect directly](#a-work-calendar-you-cant-connect-directly)
- [iCloud Calendar](#icloud-calendar)
- [The config file](#the-config-file)
- [Tagging calendars personal or work](#tagging-calendars-personal-or-work)
- [Troubleshooting](#troubleshooting)

The commands below call `crossroads`. If you didn't link it into your `PATH` during install, use `~/.local/share/crossroads/venv/bin/crossroads`.

## How it fits together

- **Google:** you create one OAuth app in Google Cloud, and every Google account you connect signs in through it. Crossroads only asks for read-only access: calendars, and the senders and subjects of unread mail. It never sees message bodies.
- **iCloud:** an app-specific password. Your Apple ID password is never used.
- **Work calendars behind SSO:** if your employer blocks third-party apps, share the work calendar as free/busy with an account Crossroads can read. Crossroads then sees your busy blocks without their titles, which is enough to catch conflicts.
- **Secrets** go into your desktop keyring (gnome-keyring, through `secret-tool`). `~/.config/crossroads/config.json` only lists accounts and calendar tags.

## Google Calendar and Gmail

### 1. Decide which account owns the app

This choice decides how much setup Google asks for.

| The app lives on | Audience | What you get |
| --- | --- | --- |
| A Google Workspace you administer (your own domain) | **Internal** | No verification, no privacy policy, tokens don't expire. Only accounts in that Workspace can sign in. |
| A personal @gmail.com account | **External** | To publish it, Google requires a homepage URL and a privacy policy URL. Left in Testing instead, its tokens expire every 7 days and you sign in again weekly. Sign-in shows an "unverified app" warning. |

If you have a Workspace on your own domain, use **Internal**. Calendars from other accounts, including a plain @gmail.com, can still be shared into it (see [step 6](#6-bring-in-calendars-from-other-accounts)).

### 2. Create the project and turn on the APIs

1. Go to [console.cloud.google.com](https://console.cloud.google.com), signed in as the account that will own the app.
2. Open the project picker at the top, then **New project**. Name it `crossroads` and select it once it's created.
3. Search for **Google Calendar API** and click **Enable**.
4. Search for **Gmail API** and click **Enable**.

### 3. Configure the consent screen

1. Open the menu, then **Google Auth Platform**, then **Get started**.
2. App name `Crossroads`, and your email as the support address.
3. Audience: **Internal** or **External**, from step 1.
4. Contact email: yours. Agree to the policy and click **Create**.
5. Go to **Data access**, then **Add or remove scopes**, and add:
   - `https://www.googleapis.com/auth/calendar.readonly`
   - `https://www.googleapis.com/auth/gmail.metadata`

   Then **Save**.
6. External only: go to **Audience** and click **Publish app**. Google asks for the homepage and privacy policy URLs first. Without publishing, sign-ins expire after 7 days.

### 4. Create the client

1. Go to **Clients**, then **Create client**.
2. Application type **Desktop app**, name `crossroads`, then **Create**.
3. Click **Download JSON**.
4. Store it in your keyring:

   ```bash
   crossroads auth google-client ~/Downloads/client_secret_<...>.json
   ```

   You can delete the downloaded file afterwards.

### 5. Sign in

```bash
crossroads auth google you@example.com
```

Your browser opens on Google's consent screen. With an External app, Google warns that it "hasn't verified this app". That's expected, since it's your own app: click **Advanced**, then **Go to Crossroads**.

Crossroads checks that you signed in with the account you named, then keeps a refresh token in the keyring. Repeat for every Google account you want, then [add each one to the config](#the-config-file).

### 6. Bring in calendars from other accounts

Any calendar shared with a signed-in account can be read through it. This is how you connect a calendar from an account that can't use your app, like a @gmail.com calendar when your app is Internal.

1. In Google Calendar, signed in as the account that owns the calendar, open **Settings**, pick the calendar, then **Share with specific people**.
2. Add the account Crossroads signs in with, and choose **See all event details**.
3. Signed in as that account, accept it: click **Add this calendar** in the email Google sends, or open **Other calendars**, then **+**, then **Subscribe to calendar**, and enter the owner's address.

A shared calendar only shows up once it's accepted. To list what an account can see:

```bash
crossroads calendars google you@example.com
```

Gmail can't be shared like this. Each inbox needs its own sign-in.

## A work calendar you can't connect directly

Companies that sign in through SSO, like Okta, often block third-party apps, so your work account can't use your Crossroads app. You can still see your work commitments:

1. In your **work** Google Calendar, open **Settings**, pick your calendar, then **Share with specific people**.
2. Add the account Crossroads signs in with, and choose **See only free/busy (hide details)**. That's often the only level a company allows outside its domain.
3. Accept it on that account, as in [step 6](#6-bring-in-calendars-from-other-accounts).
4. In Crossroads settings, tag it **Work**.

What to expect:

- Every work event shows up as its own **Busy** block, without a title. Back-to-back meetings stay separate blocks and are never merged.
- Overlaps with personal events are caught as usual.
- If a work meeting is also on one of your personal calendars, Crossroads can't tell it's the same meeting, so the two show as a personal + work overlap.
- Work email isn't available this way.

## iCloud Calendar

1. Go to [account.apple.com](https://account.apple.com), then **Sign-In and Security**, then **App-Specific Passwords**.
2. Create one named `crossroads` and copy it.
3. Store it, using your Apple ID email, which may well be a Gmail address:

   ```bash
   crossroads auth icloud you@icloud.com
   ```

   Paste the password when asked. It isn't echoed.

4. [Add the account to the config](#the-config-file), then list its calendars:

   ```bash
   crossroads calendars icloud you@icloud.com
   ```

iCloud has no links to individual events, so opening an iCloud event takes you to iCloud Calendar on the web.

## The config file

Signing in stores credentials. The config says which accounts Crossroads reads. It lives at `~/.config/crossroads/config.json`:

```json
{
  "google": [
    {
      "account": "you@example.com",
      "mail": true,
      "calendars": [
        { "id": "you@example.com", "tag": "personal", "name": "Me" }
      ]
    }
  ],
  "icloud": [
    {
      "account": "you@icloud.com",
      "calendars": []
    }
  ]
}
```

- `account`: the address you signed in with.
- `mail`: show this inbox's unread mail. Google only.
- `calendars`: the calendars to read. Each needs an `id` from `crossroads calendars` and a `tag` of `personal` or `work`. `name` is what the view shows, and is optional.

Start with an empty `calendars` list and tag them from settings, as described next.

## Tagging calendars personal or work

Open Crossroads (Super+Alt+C), then settings (Ctrl+,). Under **Calendars**, every calendar your configured accounts can see has **Off / Personal / Work**. Changes save straight away and your view refreshes.

The tag decides how overlaps look. Two events with the same tag show in a darker shade of that tag's color. A personal event against a work event shows in a blend of both, which is the clash Crossroads is mostly there to catch.

From a terminal:

```bash
crossroads calendars --json
crossroads tag icloud you@icloud.com /123456/calendars/home/ personal --name "Home"
crossroads tag google you@example.com you@example.com off
```

`off` removes the calendar from the config. Every change validates the whole config and writes it in one step, so a failed write leaves the old file in place.

## Troubleshooting

Problems show in red at the bottom of the modal and the bar panel, labeled with the account and calendar they come from. One broken account never hides the others.

| You see | What to do |
| --- | --- |
| `… is not signed in; run: crossroads auth …` | Run that command. |
| `no Google OAuth client` | Run `crossroads auth google-client <file>` ([step 4](#4-create-the-client)). |
| `could not refresh …` | The Google sign-in was revoked or expired (always after 7 days for an External app left in Testing). Sign in again. |
| `401 from iCloud …` | The app-specific password was revoked. Create a new one and run `crossroads auth icloud` again. |
| `403 from …` on a shared calendar | The share was removed, or never accepted on the account Crossroads uses. |
| `no config at …` | Create `~/.config/crossroads/config.json` ([The config file](#the-config-file)). |
| A shared calendar is missing from settings | Accept the share first ([step 6](#6-bring-in-calendars-from-other-accounts)). |
