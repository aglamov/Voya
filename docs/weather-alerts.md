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
- `WEATHER_MONITOR_SECRET`: a long random value used only between QStash and Voya.
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY`
- `APNS_ENV`: `development` for debug device builds or `production` for TestFlight/App Store.

`VOYA_API_BASE_URL` must point the iOS build to the production Vercel deployment.

## QStash schedule

Create one schedule that invokes the monitor every 10 minutes. Forward the monitor secret as a bearer token. Replace the example values locally; do not commit them.

```bash
curl --request POST \
  --url "https://qstash.upstash.io/v2/schedules/https://YOUR_VERCEL_DOMAIN/api/weather-monitor" \
  --header "Authorization: Bearer YOUR_QSTASH_TOKEN" \
  --header "Content-Type: application/json" \
  --header "Upstash-Cron: */10 * * * *" \
  --header "Upstash-Forward-Authorization: Bearer YOUR_WEATHER_MONITOR_SECRET" \
  --header "Upstash-Retries: 3" \
  --data '{}'
```

The endpoint also accepts `x-voya-monitor-secret`, which is useful for manual diagnostics:

```bash
curl --request POST \
  --url "https://YOUR_VERCEL_DOMAIN/api/weather-monitor" \
  --header "x-voya-monitor-secret: YOUR_WEATHER_MONITOR_SECRET"
```

The response reports indexed/active watches, grouped provider queries, matched alerts, sent pushes, and bounded errors. It never returns APNs device tokens.

## Operational notes

- OpenWeather recommends refreshing One Call 4.0 every 10 minutes.
- The free allowance is finite, so coordinate grouping is essential. Monitor the provider dashboard before expanding beyond active and near-term trips.
- Weather alerts come from national agencies, but coverage varies by country and event. Voya must present the source and must not claim to replace official emergency services.
- A failed APNs send releases its delivery key so the next monitoring run can retry it. Production observability should still alert on non-zero `errors` so repeated failures can be investigated.
