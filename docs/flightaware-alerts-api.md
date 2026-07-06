# FlightAware AeroAPI Alerts Reference

Source: `https://www.flightaware.com/aeroapi/portal/documentation#post-/alerts`

Captured from pasted FlightAware documentation on 2026-07-06 for implementation reference.

## Create New Alert

`POST /alerts`

Create a new AeroAPI flight alert. When the alert is triggered, a callback mechanism will be used to notify the address set via the `/alerts/endpoint` endpoint. Each callback will be charged as a query and count towards usage for the AeroAPI key that created the alert. If this key is disabled or removed, the alert will no longer be available. If a `target_url` is provided, then this specific alert will be delivered to that address regardless of the address set via the `/alerts/endpoint` endpoint. Creating more than 50 duplicate alerts with the exact same configuration will result in a 400 error.

Authentication: API Key (`x-apikey`)

Request body: `application/json; charset=UTF-8`

Body: alert configuration structure

API server:

```text
https://aeroapi.flightaware.com/aeroapi
```

Responses:

- `201` Alert created successfully
- `400`

Response headers:

- `Location` string: URL of the newly created alert

## Get Specific Alert

`GET /alerts/{id}`

Returns the configuration data for an alert with the specified ID.

Authentication: API Key (`x-apikey`)

Path parameters:

- `id` integer: The ID of the alert to fetch or update

Responses:

- `200`
- `404`

Example response:

```json
{
  "id": 0,
  "description": "string",
  "ident": "string",
  "ident_icao": "string",
  "ident_iata": "string",
  "origin": "string",
  "origin_icao": "string",
  "origin_iata": "string",
  "origin_lid": "string",
  "destination": "string",
  "destination_icao": "string",
  "destination_iata": "string",
  "destination_lid": "string",
  "aircraft_type": "string",
  "created": "2021-12-31T19:59:59Z",
  "changed": "2021-12-31T19:59:59Z",
  "start": "1970-01-01",
  "end": "1970-01-01",
  "user_ident": "string",
  "eta": 0,
  "impending_arrival": [
    5,
    10,
    15
  ],
  "impending_departure": [
    5,
    10,
    15
  ],
  "events": {
    "arrival": false,
    "cancelled": false,
    "departure": false,
    "diverted": false,
    "filed": false,
    "out": false,
    "off": false,
    "on": false,
    "in": false,
    "hold_start": false,
    "hold_end": false
  },
  "target_url": "string",
  "enabled": false
}
```

## Modify Specific Alert

`PUT /alerts/{id}`

Modifies the configuration for an alert with the specified ID. If a target URL address is provided, then the alert will be delivered to that address even if it is different than the default account-wide address set through the `/alerts/endpoint` endpoint. Updating an alert that was created with a different AeroAPI key is possible, but will not change the AeroAPI key that the alert is associated with for usage.

Authentication: API Key (`x-apikey`)

Path parameters:

- `id` integer: The ID of the alert to fetch or update

Request body: `application/json; charset=UTF-8`

Body: alert configuration structure

Responses:

- `204` Alert modified
- `400`
- `404`

## Delete Specific Alert

`DELETE /alerts/{id}`

Deletes specific alert with given ID.

Authentication: API Key (`x-apikey`)

Path parameters:

- `id` integer: The ID of the alert to fetch or update

Responses:

- `204` Alert deleted
- `400`

## Get Configured Alert Callback URL

`GET /alerts/endpoint`

Returns URL that will be POSTed to for alerts that are delivered via AeroAPI.

Authentication: API Key (`x-apikey`)

Responses:

- `200`
- `400`

Example response:

```json
{
  "url": "http://example.com"
}
```

This is the default account-wide URL that all AeroAPI alerts will be delivered to if the alert does not have a specific alert URL configured for it.

## Set Alert Callback URL

`PUT /alerts/endpoint`

Updates the default URL that will be POSTed to for alerts that are delivered via AeroAPI. This sets the account-wide default URL that all alerts will be delivered to unless the specific alert has a different delivery address configured for it.

Authentication: API Key (`x-apikey`)

Request body: `application/json; charset=UTF-8`

Body: endpoint URL configuration structure

Endpoint URL configuration structure:

```json
{
  "url": "http://example.com"
}
```

Callbacks:

- `deliver_alert`: POST to registered endpoint

Callback request body:

- `application/json; charset=UTF-8`

Callback response:

- `200` Your server returns this code if it accepts the callback

Responses:

- `204` Endpoint updated successfully, empty response
- `400`

## Remove And Disable Default Account-Wide Alert Callback URL

`DELETE /alerts/endpoint`

Remove the default account-wide URL that will be POSTed to for alerts that are not configured with a specific URL. This means that any alerts that are not configured with a specific URL will not be delivered.

Authentication: API Key (`x-apikey`)

Responses:

- `204` Endpoint successfully removed
- `400`

## Implementation Notes

- Configure the account-wide callback with `PUT /alerts/endpoint`.
- Create watched flight alert rules with `POST /alerts`.
- A specific alert can override the account-wide callback via `target_url`.
- Alert callbacks are billable queries against the AeroAPI key that created the alert.
- Duplicate alert configurations are limited: more than 50 exact duplicates returns `400`.
