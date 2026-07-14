# OpenWeather alert monitoring

Voya uses OpenWeather One Call 4.0 for both current weather cards and official weather alerts. The iOS app registers upcoming trip destinations and non-flight itinerary locations with `POST /api/weather-watch`. Upstash Redis stores only the monitoring record, APNs token, coordinates, trip/item identifiers, and monitoring dates.

## Runtime flow

1. iOS receives an APNs device token.
2. Upcoming trip locations are registered through `POST /api/weather-watch`.
3. `POST /api/weather-monitor` is invoked every 10 minutes by Upstash QStash.
4. Watches are grouped by rounded coordinates so nearby itinerary items share one current-weather lookup.
5. Alert IDs from One Call `current` are resolved through `/onecall/alert/{alert_id}`.
6. Redis `SET NX` delivery keys prevent duplicate notifications for the same installation and alert.
7. APNs sends the first active alert to the device with provider, source, severity, validity, trip, and item metadata.

The monitor only checks a watch from 48 hours before its itinerary start until 12 hours after its end. Weather-watch records expire two days after the trip.

## Required environment variables

- `OPENWEATHER_API_KEY`
- `UPSTASH_REDIS_REST_URL`
- `UPSTASH_REDIS_REST_TOKEN`
- `WEATHER_MONITOR_SECRET`: a random value of at least 32 bytes, forwarded by QStash as a bearer token.
- `WEATHER_MAX_GROUPS_PER_RUN`: optional cost ceiling; defaults to 12 coordinate groups per run. Groups are processed round-robin.
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY`
- `APNS_ENV`: `development` for debug device builds or `production` for TestFlight/App Store.

`VOYA_API_BASE_URL` must point the iOS build to the production Vercel deployment.

## QStash schedule

Create one QStash schedule for `https://voya-lime.vercel.app/api/weather-monitor` using `*/10 * * * *`, method `POST`, and `Authorization: Bearer <WEATHER_MONITOR_SECRET>`. The free QStash allowance is enough for the 144 normal invocations per day and includes retries.

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
