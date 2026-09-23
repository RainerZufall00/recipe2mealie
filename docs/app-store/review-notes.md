# Notes for App Review

Paste into App Store Connect → App Review Information → Notes. Fill in the test server credentials.

---

Recipe2Mealie is a client for Mealie (https://mealie.io), an open-source, self-hosted recipe manager. Users
connect the app to their own Mealie server. The app has no backend of its own and no user accounts.

HOW TO REVIEW WITHOUT A SERVER
On the first screen, tap "Try Without a Server" (German: "Ohne Server ausprobieren"). The app then runs with
built-in sample recipes, including a simulated import, recipe browsing and editing.

TEST SERVER (full functionality)
Server: [https://…]
Username: [user]
Password: [password]
Choose "Password" on the sign-in screen.

FEATURES TO TRY
- Import tab → Link: paste a recipe website URL, e.g. https://www.chefkoch.de/rezepte/… or any page with a recipe.
- Share sheet: in Safari, share a recipe page and choose Recipe2Mealie.
- Recipes tab: browse, open a recipe, tap the pencil to edit.

THIRD-PARTY CONTENT
- The app does not download, store or play any video or audio. For video links it only sends the link to the
  user's own Mealie server, which creates the recipe there.
- For YouTube links the app reads the video title and description through the official YouTube Data API v3
  (YouTube API Services). Terms and Google's privacy policy are linked in Settings → Privacy.
- "Mealie" is used only to describe compatibility. The app is independent and says so in its description.

PERMISSIONS
- Camera: scanning cookbook pages and taking cover photos.
- Local network: many users run Mealie in their home network.

ON-DEVICE AI
On devices with Apple Intelligence, photos and pasted text are processed with the Vision framework and the
Foundation Models framework on the device.
