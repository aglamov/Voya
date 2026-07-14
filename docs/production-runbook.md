# Voya production runbook

This is the release path for the current account-free MVP: Trips, Import, Assistant, live flights, routes, events, weather, and push notifications. The removed Inspire tab and later product tracks are not part of this release.

## 1. Production services

| Capability | Service | Required configuration |
| --- | --- | --- |
| Confirmation parsing and assistant | OpenAI | `OPENAI_API_KEY` and optional task model overrides |
| Flight lookup and live callbacks | FlightAware AeroAPI | API key, public callback URL, webhook secret |
| Routes and time-to-leave | Google Routes | server-side Routes API key |
| Weather cards and alerts | OpenWeather One Call 4.0 | API key with One Call by Call enabled |
| Nearby public events | Ticketmaster Discovery | Consumer Key |
| Watches, deduplication, rate limits | Upstash Redis | REST URL and token |
| Push delivery | Apple APNs | `.p8` key, key ID, team ID, bundle ID |
| Hosting | Vercel Hobby | production deployment |
| Weather schedule | Upstash QStash Free | ten-minute POST schedule and `WEATHER_MONITOR_SECRET` |

Use `.env.example` as the variable inventory. Store values only in Vercel and the relevant CI/Xcode secret store; never commit them.

## 2. Vercel

1. Link this repository to the existing Vercel project or run `vercel link` after `vercel login`.
2. Add every required variable from `.env.example` to Production. Provider keys needed by previews may also be added to Preview.
3. Use independent random values of at least 32 bytes for `WEATHER_MONITOR_SECRET`, `FLIGHTAWARE_ALERT_WEBHOOK_SECRET`, `VOYA_ADMIN_SECRET`, and `VOYA_CLIENT_API_KEY`.
4. Deploy production, then create the QStash schedule described below.
5. Set a low Vercel spend notification and hard limit appropriate for the MVP.

The public app endpoints require a valid anonymous installation ID in production, enforce Upstash-backed hourly limits, cap payload sizes, and optionally require `VOYA_CLIENT_API_KEY`. The shared client key deters unsophisticated external traffic but is extractable from an app binary. App Attest is the next security upgrade once real usage justifies its challenge/assertion infrastructure.

## 3. iOS Release configuration

- `VOYA_API_BASE_URL`: `https://voya-lime.vercel.app`
- `VOYA_CLIENT_API_KEY`: the same value as Vercel, injected by local/CI Release configuration
- Bundle ID: `com.aglamov.voya`
- Push Notifications capability enabled for the App ID and distribution profile
- `aps-environment=production` in the archived/TestFlight entitlement

Do not test production APNs with a simulator token. Install a TestFlight or signed Release build on a physical device.

## 4. FlightAware activation

When the app first registers an upcoming flight, `/api/flight-watch` automatically:

1. verifies that Redis, APNs token, installation ID, public URL, webhook secret, and AeroAPI key are present;
2. configures the account-wide `/alerts/endpoint` callback;
3. creates one date-specific alert rule and reuses its stored identifier;
4. expires Redis watch records shortly after the flight.

The callback rejects requests when `FLIGHTAWARE_ALERT_WEBHOOK_SECRET` is absent or incorrect. Invalid APNs tokens are removed from flight watch sets.

## 5. Weather activation and budget

QStash invokes `/api/weather-monitor` every ten minutes with `POST` and `Authorization: Bearer <WEATHER_MONITOR_SECRET>`. The endpoint prevents overlapping executions, groups nearby coordinates, deduplicates alert delivery, and rotates through at most `WEATHER_MAX_GROUPS_PER_RUN` groups per execution.

Create the schedule with cron expression `*/10 * * * *`, destination `https://voya-lime.vercel.app/api/weather-monitor`, and zero custom retries if you want to stay strictly within predictable request counts; the free tier otherwise has ample room for its default retries.

OpenWeather One Call 4.0 includes a finite free daily allowance. Start with the default limit of 12, inspect usage after TestFlight, and lower it if destinations become numerous. Invalid APNs tokens remove their weather watches automatically.

## 6. Diagnostics

Configuration health, without secret values:

```bash
curl --fail-with-body \
  --url "https://voya-lime.vercel.app/api/health" \
  --header "Authorization: Bearer YOUR_VOYA_ADMIN_SECRET"
```

Manual weather run:

```bash
curl --fail-with-body \
  --request POST \
  --url "https://voya-lime.vercel.app/api/weather-monitor" \
  --header "Authorization: Bearer YOUR_WEATHER_MONITOR_SECRET"
```

`/api/health` returns HTTP 200 only when every retained production provider, Redis, APNs production mode, weather-schedule protection, callback secret, and public URL are configured and Redis responds. It reports the optional shared client-key protection separately.

## 7. Release smoke test

1. Import a real but redacted flight/hotel confirmation and verify the review screen before saving.
2. Confirm the flight is enriched with the expected route/date and that its alert watch reports subscribed.
3. Open a transfer and verify Google route duration, map handoff, and the local time-to-leave notification.
4. Open an itinerary item and verify weather and Ticketmaster cards do not show provider-configuration warnings.
5. Confirm the device token created both flight and weather watches in the endpoint responses/logs.
6. Send one APNs test through the same production credentials or use a controlled FlightAware callback fixture.
7. Check QStash delivery logs and Vercel function logs after at least one ten-minute interval.
8. Verify `/api/health` returns HTTP 200.

## 8. App Store essentials

Before external TestFlight or review, provide a public privacy policy and support URL, complete App Privacy answers for booking documents, diagnostics, approximate itinerary locations, and device identifiers, explain notification value before the system prompt, and include a clear disclaimer that weather and travel warnings supplement rather than replace official emergency and carrier information.
