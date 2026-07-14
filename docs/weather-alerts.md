# OpenWeather alert monitoring

Voya uses OpenWeather One Call 4.0 for both current weather cards and official weather alerts. The iOS app registers upcoming trip destinations and non-flight itinerary locations with `POST /api/weather-watch`. Upstash Redis stores only the monitoring record, APNs token, coordinates, trip/item identifiers, and monitoring dates.

## Runtime flow

1. iOS receives an APNs device token.
2. Upcoming trip locations are registered through `POST /api/weather-watch`.
3. `GET /api/weather-monitor` is invoked every 10 minutes by Vercel Cron.
4. Watches are grouped by rounded coordinates so nearby itinerary items share one current-weather lookup.
5. Alert IDs from One Call `current` are resolved through `/onecall/alert/{alert_id}`.
6. Redis `SET NX` delivery keys prevent duplicate notifications for the same installation and alert.
7. APNs sends the first active alert to the device with provider, source, severity, validity, trip, and item metadata.

The monitor only checks a watch from 48 hours before its itinerary start until 12 hours after its end. Weather-watch records expire two days after the trip.

## Required environment variables

- `OPENWEATHER_API_KEY`
- `UPSTASH_REDIS_REST_URL`
- `UPSTASH_REDIS_REST_TOKEN`
- `CRON_SECRET`: a random value of at least 16 characters. Vercel automatically forwards it as a bearer token to cron endpoints.
- `WEATHER_MAX_GROUPS_PER_RUN`: optional cost ceiling; defaults to 12 coordinate groups per run. Groups are processed round-robin.
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY`
- `APNS_ENV`: `development` for debug device builds or `production` for TestFlight/App Store.

`VOYA_API_BASE_URL` must point the iOS build to the production Vercel deployment.

## Vercel Cron

[`vercel.json`](../vercel.json) registers `/api/weather-monitor` with the `*/10 * * * *` schedule. On Vercel Pro it runs with per-minute scheduling precision. Add `CRON_SECRET` to Production before deploying; Vercel sends it automatically in the `Authorization` header.

The endpoint also accepts `WEATHER_MONITOR_SECRET` through `x-voya-monitor-secret` as an optional manual-diagnostics secret:

```bash
curl --request POST \
  --url "https://YOUR_VERCEL_DOMAIN/api/weather-monitor" \
  --header "x-voya-monitor-secret: YOUR_WEATHER_MONITOR_SECRET"
```

The response reports indexed/active watches, grouped provider queries, matched alerts, sent pushes, and bounded errors. It never returns APNs device tokens.

## Operational notes

- OpenWeather recommends refreshing One Call 4.0 every 10 minutes.
- The free allowance is finite, so coordinate grouping is essential. Monitor the provider dashboard before expanding beyond active and near-term trips.
- A Redis lock suppresses overlapping monitor runs. Round-robin selection ensures a configured group cap does not permanently starve later destinations.
- Weather alerts come from national agencies, but coverage varies by country and event. Voya must present the source and must not claim to replace official emergency services.
- A failed APNs send releases its delivery key so the next monitoring run can retry it. Production observability should still alert on non-zero `errors` so repeated failures can be investigated.
