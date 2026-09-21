# External Live Activities (local UDS API)

DynamicNotch listens at `~/Library/Application Support/DynamicNotch/live-activity.sock` while running. The socket is owned by the current user with mode `0600`. Keep one Unix-domain stream connection open for the lifetime of your activity. Send one UTF-8 JSON object followed by `\n` per request; each request receives a JSON response line with `ok` and `message`.

Only a locally running macOS app with a bundle identifier can connect. DynamicNotch resolves the peer process from the socket (the JSON does not claim an identity). The first request prompts the user. Decisions can be changed under Settings → External Apps. A denied app can be enabled there. Revocation ends its activities, and closing or crashing the connection ends all activities created on that connection.

```json
{"action":"activity.upsert","id":"download-42","icon":"arrow.down.circle.fill","statusIcon":"arrow.down","title":"Downloading","message":"52%","progress":0.52}
{"action":"alert.post","id":"download-42","activityID":"download-42","icon":"checkmark.circle.fill","title":"Download complete","message":"Ready to open","duration":3}
{"action":"activity.end","id":"download-42"}
```

`activity.upsert` creates or updates a stable ID. `progress` is a fraction from 0 to 1 for the trailing progress ring; omit it to use `statusIcon` instead. Compact presentation uses the leading identity icon and trailing status; minimal presentation uses the leading icon. `alert.post` may omit `id` and `activityID` for an unrelated alert. Set `activityID` to an active ID to pause that activity while its alert is visible, then restore it. Icons are SF Symbol names. Requests are limited to 64 KiB. There is no cross-connection ownership or ability to modify built-in activities.
