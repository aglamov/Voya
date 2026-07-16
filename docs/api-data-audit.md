# Ревизия данных внешних API

Дата ревизии: 16 июля 2026.

Область проверки: iOS-клиент `Voya`, Vercel API в `api/`, фоновые обработчики в `server/handlers/`, локальное SwiftData-хранилище и текущие экраны. Это статическая ревизия контрактов и всех точек использования; фактические production payloads и тарифные ограничения провайдеров не проверялись.

## Краткий вывод

Данные действительно теряются на нескольких границах:

1. **FlightAware → `/api/flight-lookup` → iOS.** Backend строит богатый `FlightStatusResponse`, но `/api/flight-lookup` сворачивает его в небольшой `candidate`. Полный `snapshot`, `schedule`, `intelligence`, `nextActions` и сведения о провайдере до iOS не доходят. Часть тех же данных отдельно превращается в текстовые карточки через `/api/enrich`, поэтому сейчас существуют два несогласованных представления одного рейса.
2. **Редизайн экрана деталей скрыл часть enrichment.** `imageURLs` приходят, декодируются и сохраняются в кэше, но активный `ItemInsightPanel` их не показывает. Единственный UI для них — неиспользуемый `TravelBriefCard`. Для рейса `DetailedInsightBrief` предпочитает четыре «полированные» секции (рейс, выход, задержка, погода) и не показывает многие уже полученные карточки.
3. **Push не обновляет данные приложения.** Weather push несёт `tripId`, `itemId`, источник, severity и времена предупреждения; flight push несёт номер рейса и gate. iOS при открытии уведомления читает только `tripId`. У flight push `tripId` вообще отсутствует, поэтому он не может открыть нужную поездку. Ни weather, ни flight push не обновляют сохранённый itinerary или кэш.
4. **Live-данные в основном эфемерны.** Flight lookup, mobility plan и assistant advice живут только в `@State`; после закрытия экрана или перезапуска они исчезают. Полностью сохраняется только enrichment JSON, импортированные поля поездки и URL hero image.
5. **Google Routes возвращает больше, чем показывает UI.** Не используются признаки подключения и времени генерации, labels, distance, cost/comfort/emissions, provider attribution, tone, vehicle type и расстояния отдельных шагов.
6. **OpenWeather и Ticketmaster обрезаются ещё на backend.** Из текущей погоды остаются температура, первое описание и IDs alert-ов. Из Ticketmaster остаются общее число результатов и только первое событие с одной ссылкой.

## Карта потоков

| Источник | Что получаем | Где преобразуем | Что сохраняем | Где используем |
|---|---|---|---|---|
| OpenAI extraction | Тип документа, заголовок, destination, primary time, confidence, warnings; items: kind, title, start/end, location, status, PNR, provider | `api/extract.ts` → `ConfirmationExtractor.swift` | После подтверждения: itinerary-поля, PNR/provider, source document; агрегатные type/confidence/warnings не сохраняются | Import preview; destination/title/dates поездки |
| OpenAI location normalization | Display name, city, country, provider queries, optional coordinates, confidence | Внутри `api/enrich.ts` | Не сохраняется отдельно | Только подготовка запросов OpenWeather/Ticketmaster |
| OpenAI travel brief | Summary, Markdown, sections, actions, route legs, image URLs | `api/enrich.ts` | Полный JSON в `ItineraryItem.enrichmentRawData` с TTL | Item companion/detail; изображения фактически скрыты текущим UI |
| OpenAI assistant | Summary, assessment, answer, packing, actions, next item, risks, confidence, usedAI | `api/assistant.ts` → `AssistantAIService.swift` | Не сохраняется | Assistant screen; `confidence` декодируется, но не используется |
| FlightAware status/schedule/history | Идентификаторы, codeshares, аэропорты, все scheduled/estimated/actual времена, gates/terminals/baggage, delays, aircraft/track, route, disruptions, weather, history, alerts | `api/_flight.ts`; затем `/api/flight-lookup` или `/api/enrich` | При импорте — только title/location/start/end/status. В detail/assistant — не сохраняется. Enrichment сохраняет текстовые карточки | Import validation, flight status card, assistant alerts, enrichment brief, push watches |
| FlightAware alert callbacks | Event, flight ID/number/date, gates/terminals, scheduled/estimated/actual gate times, descriptions | `api/flightaware-alerts.ts` | Последнее состояние gate/times и дедупликация в Redis | APNs text; iOS не применяет payload к itinerary |
| OpenWeather geocoding/current/alerts | Coordinates/name/country; temperature, description, alert IDs; alert source/event/description/start/end/severity | `api/_weather.ts`, `api/enrich.ts`, weather monitor | Watch: coordinates, label, trip/item IDs, dates; alert delivery dedupe | Weather enrichment card и APNs weather alerts |
| Google Routes | Route/static duration, distance, legs/steps, instructions, transit line/vehicle/stops/times | `api/_mobility.ts` | Не сохраняется | Timeline transfers, transfer detail, assistant transfer alerts |
| Ticketmaster Discovery | Total result count; до 5 events с name, URL, local date/time, first venue/city | `api/enrich.ts` | Только как часть enrichment JSON/AI brief | Nearby-events card/ссылка косвенно через detail brief |
| Wikipedia REST summary | `originalimage.source`, fallback `thumbnail.source` | `DestinationImageResolver.swift` | URL и статичный credit в `Trip` | Hero background |
| Upstash Redis REST | Значения rate limits, watches, alert state, locks/cursors, dedupe keys | `_storage.ts` и фоновые handlers | Серверное operational state | Rate limiting, watches, fan-out и дедупликация |
| APNs | HTTP status и error reason, включая invalid token | `_apns.ts` | Invalid tokens удаляются из watch sets | Доставка flight/weather push |
| Uber APIs | OAuth result, products, price/time estimate diagnostics | `api/uber-diagnostics.ts` | Не сохраняется | Только защищённая диагностика; продуктовый UI не использует |

## Детально по источникам

### 1. OpenAI: импорт подтверждений

Контракт backend и Swift совпадает. Все item-поля доходят до preview:

- `kind`, `title`, `startsAt`, `endsAt`, `location`, `status`;
- `confirmationCode`, `providerName`;
- агрегатные `type`, `title`, `normalizedDestination`, `primaryTime`, `confidence`, `warnings`.

Использование:

- `type`, `confidence`, `warnings` и распознанные fields показываются только в preview;
- `normalizedDestination`, `title`, `primaryTime` участвуют в создании `Trip`;
- item-поля, PNR и provider сохраняются в SwiftData;
- оригинальный файл сохраняется как `SourceDocument`, если он был импортирован файлом;
- исходный распознанный текст и полный JSON extraction не сохраняются в `ItineraryItem.rawData/normalizedData` — эти поля остаются пустыми. Из-за этого assistant-поле `extractedBookingData` практически всегда пустое.

Вывод: потери после подтверждения ожидаемы для preview metadata, но отсутствие нормализованного extraction JSON снижает трассируемость и лишает assistant исходного структурированного контекста.

### 2. OpenAI: enrichment и travel brief

Backend возвращает и iOS декодирует все поля `ItemEnrichment`: `summary`, `cards`, `warnings`, `briefMarkdown`, `sections`, `actions`, `routeLegs`, `imageURLs`. Полный объект кэшируется в SwiftData.

Потери в текущем UI:

- `imageURLs` не отображаются: `TravelBriefCard` умеет их показывать, но нигде не создаётся;
- UI использует в основном первое warning; остальные могут остаться невидимыми;
- для flight активируется `polishedFlightSections()`. Если найдена хотя бы одна flight card, сгенерированные sections обходятся;
- из flight cards напрямую выбираются только Flight, Gate, Delay и Weather;
- отдельные карточки Times, Reliability, Disruptions, Route, Alerts и Aircraft не попадают в `DetailedInsightBrief`; Aircraft location частично показывается отдельно в companion card, а reliability — отдельно после ручного flight refresh;
- `actionURL` из enrichment работает, но fallback `imageURLs` формируется из action URLs, то есть может содержать не изображения. Это потенциально некорректный контракт даже если вернуть UI изображений.

### 3. OpenAI: assistant

Все содержательные поля используются:

- `assessmentTitle/assessmentDetail` заменяют локальную оценку;
- `packingAdvice` заменяет weather recommendation;
- `answer` используется для ответа на вопрос;
- `summary`, `nextActions`, `nextItemDescription`, `riskOverview`, `additionalRisks`, `usedAI` показываются на assistant screen.

Не используется только `confidence`. Advice не сохраняется, поэтому повторное открытие/перезапуск требует нового анализа.

### 4. FlightAware: полный статус и структурированный lookup

`api/_flight.ts` нормализует:

- provider flight ID/status, IATA/ICAO flight IDs, operating airline, codeshares;
- origin/destination IATA/ICAO;
- scheduled/estimated/actual out/off/on/in;
- departure/arrival terminal, gate, delays, baggage;
- aircraft type/registration, inbound aircraft, progress и track position;
- route distance, filed speed/altitude/route/ETE;
- history, disruptions, airport weather, typical gates/aircraft;
- alert capability, provider attribution, warnings и next actions.

#### Что теряется в `/api/flight-lookup`

До iOS не доходят:

- `providerFlightId`, airline code и корректно структурированный operating airline;
- отдельные scheduled/estimated/actual времена и out/off/on/in;
- departure/arrival delay по отдельности, normalized status, cancellation/diversion context;
- route distance, filed speed/altitude/route/ETE;
- disruptions, airport weather, route insight;
- history period (`since/until`), типовые gates/aircraft, diverted count;
- `nextActions`, provider connected/attribution, full schedule/intelligence.

`candidate.departureAt/arrivalAt` выбирают **scheduled раньше estimated и actual**. Поэтому изменение ETA не обновляет основное время candidate, хотя полный status уже содержит новое время. В `api/_flight.ts` для plane context приоритет обратный и более корректный: actual → estimated → scheduled.

`operatingFlightNumber` заполняется первым `codeshare`, что семантически не гарантирует номер operating flight. Поле сейчас не используется, поэтому ошибка скрыта.

#### Что iOS декодирует, но не использует

- candidate: `flightIata`, `flightIcao`, `operatingFlightNumber`, `arrivalTerminal`, `arrivalGate`, `inboundProviderFlightId`;
- position: groundspeed, heading, update time (карта использует только lat/lon, assistant ещё altitude);
- plane: `currentFlight`, большая часть времён сегментов, `sourceUpdatedAt`;
- reliability: `divertedCount`, typical departure/arrival gates, typical aircraft types;
- gate: arrival terminal/gate, baggage в status card, changed и guidance;
- весь `alerting` в lookup response.

#### Где rich flight data всё же используется

`/api/enrich` вызывает полный `getFlightStatus()` напрямую и превращает историю, disruptions, route, airport weather, times и aircraft в текстовые cards. Эти cards кэшируются, но часть из них затем скрывает flight-specific UI, описанный выше.

### 5. FlightAware alerts и APNs

Backend корректно нормализует и сравнивает gate/terminal и estimated times, хранит последнее состояние в Redis и подавляет дубли.

Разрывы на клиенте:

- flight push payload содержит `provider`, `eventType`, `flightNumber`, `flightDate`, `gate`, но не `tripId/itemId`;
- weather push содержит `tripId/itemId`, но iOS читает только `tripId`;
- iOS не читает flight number, event type, gate, severity, alert ID, item ID или времена;
- push не инициирует refresh соответствующего item и не обновляет `status`, times или enrichment cache.

Таким образом уведомление информирует текстом, но полученные структурированные данные теряются сразу после показа.

### 6. Google Routes

Используется:

- mode/title, total/travel/buffer duration;
- departure/arrival/leave-by;
- summary/tradeoffs/map URL;
- transit steps: title/detail/line/stops/times;
- reliability для assistant severity;
- recommendation title/reason/mode.

Декодируется, но не используется:

- plan: `providerConnected`, `generatedAt`, `originLabel`, `destinationLabel`;
- option: `distanceMeters`, `costLevel`, `comfortLevel`, `emissionsLevel`, `providerAttribution`, `tone`;
- step: `distanceMeters`, `vehicleType`.

Планы находятся только в `TripsView.@State`, кэш между экранами/запусками отсутствует. При этом точное время route steps уже получено и активно используется для timeline.

### 7. OpenWeather

Backend намеренно оставляет из current conditions только:

- `temperatureCelsius`;
- первое weather description;
- alert IDs.

Остальные поля ответа One Call не входят даже во внутренний тип и теряются на чтении. Для alert detail сохраняются source, event, description, start/end и вычисленная severity; они используются для текста, дедупликации и APNs metadata.

В enrichment card отображаются температура, описание и названия alert-ов. Полные тексты alert-ов, источник и период действия в UI карточки не попадают. Weather watch сохраняет coordinates, но ответ регистрации iOS сворачивает до `accepted/stored/monitoring`, игнорируя возвращённую запись watch.

### 8. Ticketmaster

Запрашиваются до пяти событий, но наружу выходит одна card:

- `value`: общее число результатов;
- `detail`: name, first venue, city и local start первого события;
- `actionURL`: URL первого события.

Остальные четыре события, их URLs, venues и times теряются. Даже имена второго события вычисляются только для fallback-ветки, которая практически недостижима при наличии `firstEvent`.

### 9. Wikipedia hero image

Используются только `originalimage.source` и fallback `thumbnail.source`. URL и статичный credit сохраняются в `Trip` и показываются в hero. Остальные поля page summary намеренно не декодируются. При смене destination URL сбрасывается и загружается заново.

### 10. Operational APIs

- **Upstash Redis REST:** ответы используются полностью как transport для rate limit, watches, locks, cursors и dedupe; product UI их не видит.
- **APNs:** используются success/error и invalid token. Остальные response headers не анализируются.
- **Uber diagnostics:** не подключён к приложению и существует только как admin diagnostic endpoint.
- **Google Maps URLs/redirects:** используются для извлечения координат/названия и handoff в Maps, но это не сохраняемый источник данных.

## Ревизия Voya endpoints

### Вызываются iOS-приложением

| Endpoint | Назначение | Состояние данных |
|---|---|---|
| `POST /api/extract` | Распознавание подтверждения | Items сохраняются после review; preview metadata — нет |
| `POST /api/enrich` | Weather/events/flight context + brief | Полностью кэшируется, но часть скрыта UI |
| `POST /api/assistant` | Итоговый анализ/ответ | Только память |
| `POST /api/flight-lookup` | Проверка и refresh рейса | Частично применяется при импорте; detail — только память |
| `POST /api/flight-discovery` | Поиск номера по route/time | Candidate затем проверяется lookup; напрямую не сохраняется |
| `POST /api/mobility` | Route options | Только память |
| `POST /api/flight-watch` | Регистрация APNs watch | Server state в Redis; часть response используется для toggle/status |
| `POST /api/weather-watch` | Регистрация weather watch | Server state в Redis; клиент использует только `stored` |

### Не вызываются iOS-приложением

- `/api/flight-status` — богатый полный контракт доступен только внешним/диагностическим клиентам; приложение получает урезанный `/flight-lookup`.
- `/api/booking-validation` — реализован, но product flow его не вызывает.
- `/api/uber-diagnostics`, `/api/health`, `/api/flightaware-alert-subscriptions`, `/api/weather-monitor` — operational/admin/background.
- `/api/flightaware-alerts` — входящий webhook FlightAware.

## Приоритеты исправления

### P0 — восстановить потерянную ценность

1. Сделать единый client-facing flight snapshot вместо двух несогласованных путей (`flight-lookup` и текстовые flight cards в enrichment). Передавать structured scheduled/estimated/actual times, normalized status, gates обеих сторон, baggage, delays, aircraft, route/history/disruptions и provider timestamp.
2. Исправить приоритет основного времени в `/api/flight-lookup`: actual → estimated → scheduled. Не перезаписывать пользовательский itinerary фактическим временем без явной политики, но показывать live ETA отдельно.
3. Вернуть `imageURLs` в активный экран либо перестать запрашивать/генерировать их. Проверять, что URL действительно ведёт на изображение.
4. Для flight detail явно отобразить или осознанно удалить cards Times, Disruptions, Route, Alerts, Aircraft и дополнительные warnings. Сейчас backend оплачивает и получает эти данные, но редизайн их скрывает.
5. Добавить `tripId` и `itemId` в flight watch/push, на открытии push переходить к item и делать targeted refresh. Weather push также должен использовать `itemId` и alert metadata.

### P1 — сохранить данные между сессиями

6. Ввести versioned persisted snapshots для flight и mobility с `fetchedAt/expiresAt/provider`. Не смешивать provider facts с редактируемыми полями подтверждения.
7. Сохранять normalized extraction JSON или отдельный provenance snapshot; сейчас `rawData/normalizedData` фактически пусты, а assistant лишён `extractedBookingData`.
8. Решить судьбу неиспользуемых Google Routes полей: показать distance/cost/emissions/vehicle или убрать их из field mask и client contract.
9. Возвращать массив Ticketmaster events, если продукту нужен выбор, либо запрашивать `size=1`, чтобы контракт честно отражал UI.

### P2 — защитить от повторной потери при редизайне

10. Добавить contract fixtures/tests для каждого endpoint: provider payload → backend response → Swift decode.
11. Добавить тест «каждое response field либо используется, либо помечено intentionally ignored» и snapshot-тесты ключевых экранов.
12. Добавить безопасную телеметрию полноты данных без PII: какие группы полей пришли, какие показаны, decode failures, cache age и provider timestamp.

## Рекомендуемая целевая модель

Разделить данные item на три слоя:

1. **Booking facts** — подтверждённые пользователем поля из документа: PNR, provider, исходные start/end/location.
2. **Live provider snapshot** — immutable/versioned снимок FlightAware/OpenWeather/Routes с `provider`, `fetchedAt`, `expiresAt`, полным structured payload и quality/confidence.
3. **Presentation/AI brief** — производный текст и cards, которые можно пересоздать из первых двух слоёв.

Сейчас второй и третий слои частично смешаны в `enrichmentRawData`, а богатый structured flight snapshot не сохраняется. Это главная архитектурная причина, по которой редизайн смог незаметно убрать информацию.
