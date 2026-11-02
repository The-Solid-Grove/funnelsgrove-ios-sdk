# FunnelsGrove iOS SDK: дизайн

Дата: 2 ноября 2026. Статус: дизайн согласован, следующий шаг — план реализации.

Репозиторий `funnelsgrove-ios-sdk` (приватный): Swift Package `FunnelsGroveSDK`, демо-приложение и эта спека.

Основа — AppsiloveSDK (`appsilove-ios-sdk`) и его спека [links.appsilove.co и iOS SDK](https://github.com/The-Solid-Grove/appsilove/blob/main/docs/superpowers/specs/2026-10-25-links-and-ios-sdk-design.md). Логика та же, отличия перечислены в разделе «Чем отличается от AppsiloveSDK». AppsiloveSDK не меняется.

## Цель

Покупатель оплачивает подписку в веб-воронке FunnelsGrove (FG) и попадает в iOS-приложение уже с доступом. Покупку и приложение связывает публичный id пользователя FG (`u_…`), который FG сам дописывает к ссылке в приложение. SDK подходит любому клиенту FG: ссылка может прийти с любого домена и с любой схемой.

Готово, когда:

1. Ссылка с экрана воронки после оплаты открывает установленное приложение, SDK сохраняет `user_id` и `email` из ссылки и получает статус подписки от FG.
2. Приложение после своего входа или регистрации вызывает `trackLogin()`, и FG показывает у этого пользователя «Logged into app».
3. После удаления и повторной установки приложения SDK находит тот же `user_id` и снова получает статус.

## Чем отличается от AppsiloveSDK

| | AppsiloveSDK | FunnelsGroveSDK |
| --- | --- | --- |
| Какие ссылки принимает | `https` на `linkHost` | любой URL с `user_id`: `https` с любого домена и свои схемы вроде `myapp://` |
| `email` из ссылки | игнорирует | сохраняет вместе с `user_id` |
| `track_login` | SDK вызывает сам при каждой ссылке | публичный `trackLogin()`, вызывает приложение |
| Страница управления подпиской | `manageSubscriptionURL` на `linkHost` | нет |
| Вход по коду из письма | через API сервиса `links` | нет |
| Настройка | `linkHost` и publishable key | только publishable key |

Страница управления и вход по коду работают через сервис `links` appsilove. У FG SDK своего сервера нет, а у FG нет публичного API для кодов входа, поэтому в v1 их нет.

## Что уже есть в FG

Проверено по исходникам FG (`main`, 25 октября 2026).

- **Ссылка в приложение.** Экран после оплаты (`SubscriptionHandoffScreen`, ссылки строит `resolveSubscriptionHandoff` в `apps/funnel-runtime/src/runtime/subscription-handoff.ts`) берёт ссылки из настроек проекта:
  - **App Store deeplink** (`NEXT_PUBLIC_FUNNEL_IOS_DEEP_LINK`) — любая ссылка, обычно своя схема приложения;
  - **Web link** (`NEXT_PUBLIC_FUNNEL_UNIVERSAL_LINK`) — обычно Universal Link;
  - ссылка на App Store.

  На iOS кнопка «Open app now» ведёт на первую заданную в этом порядке: App Store deeplink, Web link, App Store. Ссылка в письме — Web link, иначе App Store deeplink.
- **Параметры ссылки.** К каждой из этих ссылок FG добавляет `user_id`, если его там ещё нет. К App Store deeplink и Web link он добавляет ещё `email` и first-touch атрибуцию (`utm_*` и другие), к ссылке на App Store — нет. Значения проходят через `URLSearchParams`, поэтому `@` и `+` в email приходят как `%40` и `%2B`. Шаблоны `{user_id}` и `{email}` в настройках подставляются, но `user_id` в query есть всегда.
- **Авто-переход.** Один раз за сессию экран сам переходит по ссылке через `window.location.assign`, без тапа.
- **Формат `user_id`.** Обычно `u_` и 32 hex-символа, но бывают и другие: `u_<время>_<hex>` в браузерах без `crypto.randomUUID`, а `bootstrap` принимает id от клиента. Поэтому SDK формат не проверяет.
- **Проверка подписки.** `POST https://sdk-api.funnelsgrove.com/sdk/public/users/verify_subscription` с заголовком `X-SDK-Publishable-Key` и телом `{ "userId": "u_…" }` возвращает `{ "active", "test", "user": { "user_id" } | null }`. Сначала ищет live-пользователя, затем test. Запрос ничего не меняет и отвечает `Cache-Control: no-store`.
- **Учёт входа.** `POST /sdk/public/users/track_login` с телом `{ "userId" }` и тем же заголовком (`createRegistrationLoginRoute`):
  - записывает событие `registration_completed`, в интерфейсе FG — «Logged into app». Гайд интеграции FG просит слать его после успешного входа или регистрации в приложении;
  - id события строится из воркспейса, воронки, пользователя и среды, поэтому повторный вызов ничего не дублирует;
  - без заголовка `Origin` и без `runtimeEnvironment` ищет пользователя в live, затем в test;
  - отвечает 401 на неверный ключ, 404 `Funnel user not found`, если пользователя нет, и 400, если `userId` пустой или один `user_id` есть в нескольких воронках проекта (тогда нужен `funnelId`);
  - ответ 2xx: `{ "user": { "user_id" }, "login": { "tracked", "newlyTracked", "trackedAt" } }`.

## Архитектура

```text
FG-воронка → оплата → экран handoff
  «Open app now» на iOS = App Store deeplink || Web link || App Store
     + ?user_id=u_…&email=…&utm_…   (email только в App Store deeplink и Web link)
  ├─ приложение установлено, ссылка его открыла → onOpenURL / continue userActivity
  │    → SDK: user_id и email в Keychain → verify_subscription в FG → доступ
  │    → вход или регистрация в приложении → trackLogin() → track_login в FG
  └─ иначе → App Store; приложение запускается без user_id до следующего тапа
```

SDK ходит только в публичный API FG по publishable key. Своего сервера нет. Какие ссылки открывают приложение, решают entitlements приложения и AASA на его домене, а не SDK.

## Пакет

Swift Package в репо `funnelsgrove-ios-sdk`: `swift-tools-version: 6.0`, iOS 15+, без сторонних зависимостей. macOS 12 в списке платформ нужен только для того, чтобы гонять `swift test` на Mac. Библиотека и модуль называются `FunnelsGroveSDK`, главный тип — `FunnelsGrove`. Если модуль и тип назвать одинаково, Swift не сможет разобрать квалифицированные имена вроде `FunnelsGrove.SubscriptionStatus`.

Код переносится из AppsiloveSDK с правками: разбор ссылок, клиент FG, хранение в Keychain, опрос после свежей ссылки и тесты к ним. `LinksClient`, `ManageLink` и `EmailCode` не переносятся.

## API

```swift
@MainActor public final class FunnelsGrove {
  public static func configure(
    publishableKey: String,                  // SDK publishable key FG-проекта
    acceptTestSubscriptions: Bool = false,
    apiBaseURL: URL = URL(string: "https://sdk-api.funnelsgrove.com")!
  )
  public static var shared: FunnelsGrove { get }   // до configure — precondition failure

  @discardableResult public func handle(_ url: URL) -> Bool
  @discardableResult public func handle(_ userActivity: NSUserActivity) -> Bool
  public var userId: String? { get }
  public var email: String? { get }
  public func checkSubscription() async throws -> SubscriptionStatus
  @discardableResult public func trackLogin() async throws -> Bool
  public func reset()
}

public struct SubscriptionStatus: Sendable, Equatable {
  public let isActive: Bool      // active && (!test || acceptTestSubscriptions)
  public let isTest: Bool        // test из ответа FG
  public let isKnownUser: Bool   // FG вернул user, а не null
  public let userId: String?
}

public enum FunnelsGroveError: Error, Equatable, Sendable {
  case configuration(String)     // 400 или 401 от FG: неверный ключ или запрос
  case server(statusCode: Int)   // остальные не-2xx или тело ответа, которое не читается
  case network(URLError)
  case unknownUser               // track_login: FG не знает сохранённого пользователя в проекте ключа (404)
}
```

`configure` останавливает приложение (`precondition`), если ключ пустой, содержит пробельные символы или похож на секретный: начинается с `sdk_sec_` или `fg_key_`. Секретный ключ в сборке приложения достаётся любому, кто её скачал. Формат publishable key (`sdk_pub_…`) не проверяется, чтобы новый формат ключей FG не ронял приложения.

Подключение в приложении:

```swift
// SwiftUI: своя схема приходит в onOpenURL, Universal Link — в onOpenURL или onContinueUserActivity
.onOpenURL { FunnelsGrove.shared.handle($0) }
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { FunnelsGrove.shared.handle($0) }

// UIKit: scene(_:openURLContexts:), scene(_:continue:),
// при холодном старте connectionOptions.urlContexts и connectionOptions.userActivities
FunnelsGrove.shared.handle(context.url)
FunnelsGrove.shared.handle(userActivity)

// после своего входа или регистрации
Task { try? await FunnelsGrove.shared.trackLogin() }
```

## handle

`handle(_ userActivity:)` берёт `webpageURL`, если тип активности `NSUserActivityTypeBrowsingWeb`, и передаёт её в `handle(_ url:)`. Иначе возвращает `false`.

`handle(_ url:)` принимает ссылку с любой схемой и любым хостом, в том числе без хоста, если в query есть `user_id`. Берётся первый параметр с именем ровно `user_id`, значение после percent-decoding (`URLComponents.queryItems`). Оно должно быть непустым, не длиннее 256 байт в UTF-8 и без пробелов и управляющих символов. Лимит считается в байтах, а не в символах: иначе одна буква с тысячей комбинирующих знаков прошла бы как один символ. Это правило AppsiloveSDK без изменений.

Путь и хост не проверяются: какие ссылки открывают приложение, решают его entitlements, AASA и `CFBundleURLTypes`. Остальные параметры (`utm_*` и прочие) SDK игнорирует.

Если ссылка подошла, SDK:

1. берёт `email` из той же ссылки (раздел ниже);
2. сохраняет `user_id` и `email` в Keychain одной записью;
3. запоминает в памяти время прихода ссылки;
4. возвращает `true`.

`track_login` при этом не вызывается.

Если не подошла, SDK ничего не меняет и возвращает `false`: такую ссылку приложение обрабатывает само. Ссылка с `email`, но без `user_id` не подходит.

Свои ссылки приложение разбирает раньше SDK. Иначе ссылку приложения с параметром `user_id` в другом смысле SDK примет за ссылку FG. README говорит об этом прямо.

## Email из ссылки

- Берётся первый параметр с именем ровно `email`, значение после percent-decoding. `+` без кодирования остаётся `+`, а не превращается в пробел.
- Проверка мягкая: после обрезки пробелов по краям строка непустая, не длиннее 254 байт в UTF-8, содержит `@`, без пробелов и управляющих символов внутри. Адрес не нормализуется и не приводится к нижнему регистру: SDK хранит то, что прислал FG.
- Email, который не прошёл проверку, считается отсутствующим. `user_id` из той же ссылки всё равно сохраняется.
- Если в ссылке нет годного email:
  - для того же `user_id`, что уже сохранён, остаётся прежний email;
  - для другого `user_id` email становится `nil`: адрес прежнего покупателя не должен остаться рядом с новым id.
- Email из ссылки не подтверждён: это адрес, который покупатель ввёл в воронке, и он есть у любого, у кого есть ссылка. Годится, чтобы подставить в форму регистрации или показать «вы вошли как», но не как доказательство владения адресом.

## checkSubscription

1. Если `user_id` нет, сразу возвращается `SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil)`, без сети.
2. Иначе `POST {apiBaseURL}/sdk/public/users/verify_subscription` с заголовками `Content-Type: application/json` и `X-SDK-Publishable-Key`, тело `{ "userId": "<id>" }`, таймаут 10 секунд.
3. Если ссылка пришла меньше 120 секунд назад, а FG ответил `active: false`, запрос повторяется через 1, 2, 4 и 8 секунд, пока не придёт `active: true`. Вебхук оплаты может отставать.
4. На 503 с `Retry-After` не больше 10 секунд — одно ожидание и повтор. Иначе ошибка `.server(503)`.
5. Ответы 400 и 401 превращаются в `.configuration`, остальные не-2xx — в `.server`, ошибки `URLError` — в `.network`. Ответ 2xx с телом, которое не разбирается, тоже даёт `.server` с этим кодом.
6. Если FG ответил `user: null` на сохранённый id (чужой проект или окружение), возвращается `isActive: false`, `isKnownUser: false`, а `userId` остаётся сохранённым. Id не удаляется: чаще всего это ошибка конфигурации ключа, а не пользователя.

Если во время проверки пришла новая ссылка или вызван `reset()`, SDK не возвращает устаревший ответ: опрос старого пользователя прекращается, и проверка повторяется для текущего. Отмена задачи даёт `CancellationError`, а не сетевую ошибку.

`active` SDK не кэширует: FG советует перепроверять на каждой границе платного контента. Кэшировать может само приложение.

## trackLogin

Записывает «Logged into app» в FG для сохранённого пользователя.

1. Если `user_id` нет, возвращает `false` без сети. Так приложение может вызывать метод при каждом входе, не проверяя `userId`.
2. Иначе `POST {apiBaseURL}/sdk/public/users/track_login` с теми же заголовками и телом `{ "userId": "<id>" }`, таймаут 10 секунд. `funnelId` и `runtimeEnvironment` не отправляются: FG сам ищет в live, затем в test.
3. На 503 с `Retry-After` не больше 10 секунд — одно ожидание и повтор, как у `checkSubscription`. Повтор безопасен: FG не дублирует событие.
4. 2xx — возвращает `true`. Тело ответа не разбирается.
5. 404 — `.unknownUser`. 400 и 401 — `.configuration`. Остальные не-2xx — `.server`, `URLError` — `.network`, отмена задачи — `CancellationError`.

Отправляется `user_id`, сохранённый в момент вызова. Если новая ссылка пришла, пока запрос в пути, вход записывается для прежнего пользователя.

SDK сам `trackLogin()` не вызывает и не откладывает. README говорит, когда его вызывать:

- после своего входа или регистрации в приложении;
- если своего входа в приложении нет — сразу после `handle`, вернувшего `true`;
- если пользователь уже вошёл, а пришла ссылка — снова после `handle`, вернувшего `true`.

## Хранение

- Одна запись Keychain generic password: `kSecAttrService = "com.funnelsgrove.sdk"`, `kSecAttrAccount = "user"`, значение — JSON `{ "userId": "…", "email": "…" | null }`. Одна запись, а не две, чтобы `user_id` и email всегда менялись вместе.
- Доступность: `kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrSynchronizable = true`. Чтение и удаление идут с `kSecAttrSynchronizableAny`.
- Запись не перезаписывается, если она не изменилась: лишняя запись только гоняет синхронизацию iCloud Keychain.
- Запись, которую не удалось разобрать или в которой негодный `user_id`, считается отсутствующей, ошибка логируется. Негодный email в записи читается как `nil` по тем же правилам, что в ссылке.
- Если Keychain не дал записать, пара остаётся в памяти до перезапуска приложения, ошибка логируется.
- Пустое чтение, например до первой разблокировки после перезагрузки, не кэшируется: следующее обращение читает снова.
- Запись переживает удаление приложения: iOS ведёт себя так давно, но Apple это не гарантирует. Через iCloud Keychain она попадает на другие устройства того же Apple ID.
- `reset()` удаляет запись и забывает время прихода ссылки.
- Запись AppsiloveSDK (`co.appsilove.sdk`) не читается.
- Доступ к Keychain спрятан за протоколом, чтобы логику можно было тестировать на фейке.

## Логи

`os.Logger` с subsystem `com.funnelsgrove.sdk`. `user_id` и email логируются только с `privacy: .private`.

## Демо-приложение

`Examples/FunnelsGroveDemo` — SwiftUI-приложение в том же репо, проект собирается xcodegen, как AppsiloveDemo.

- **Подпись.** Team ID и bundle ID задаются в xcconfig (`Local.xcconfig` вне git, пример в `Local.xcconfig.example`). Предлагаемый bundle ID — `com.funnelsgrove.demo`. Там же publishable key.
- **Своя схема `fgdemo`** в `CFBundleURLTypes`. Ссылка `fgdemo://open?user_id=…` проверяется без AASA. В FG-проекте демо App Store deeplink — `fgdemo://open`.
- **Universal Link — по желанию.** Associated Domains включаются, только если в `Local.xcconfig` задан домен, который отдаёт AASA для bundle ID демо. Подойдёт строка `fgdemo` в `link_apps` appsilove: `applinks:fgdemo.links.appsilove.co`, в Debug с `?mode=developer`. Заодно это показывает, что SDK принимает домен, о котором ничего не знает.
- **Экран:**
  - сохранённые `user_id` и email, последний статус;
  - кнопки Check, Track login (с результатом: tracked, no user или ошибка) и Reset;
  - поле «вставить ссылку», которое вызывает `handle(_:)`, чтобы проверять на симуляторе без перехода по ссылке.
- `acceptTestSubscriptions: true`: демо работает с тестовыми покупками.

## README

На английском, для клиентов FG:

- что делает SDK и что ссылка работает как пропуск: не логировать и не отправлять в аналитику ссылку, `user_id` и email;
- требования и установка пакета (по ветке до первого тега);
- настройка FG-проекта (раздел ниже);
- своя схема (`CFBundleURLTypes`) и Associated Domains. AASA на своём домене приложение размещает само;
- примеры для SwiftUI и UIKit: `onOpenURL`, `onContinueUserActivity`, `scene(_:openURLContexts:)`, `scene(_:continue:)`, `connectionOptions.urlContexts` и `connectionOptions.userActivities` при холодном старте;
- свои ссылки приложение разбирает раньше SDK;
- когда вызывать `checkSubscription()` и `trackLogin()`;
- email из ссылки: когда он есть и что он не подтверждён;
- поведение, тестовые подписки, ошибки (`switch` с `default`: следующие версии могут добавить случаи), хранение и `reset()` при выходе;
- как проверять ссылку: тап в Notes или Messages, а не ввод в адресную строку Safari;
- демо и тесты.

## Настройка FG-проекта для приложения

1. В настройках FG-проекта задать ссылку в приложение:
   - **App Store deeplink** — своя схема приложения, например `myapp://open`;
   - и/или **Web link** — Universal Link на домене приложения, например `https://go.myapp.com/open`.

   На iOS «Open app now» ведёт на App Store deeplink, если он задан. Ссылка в письме — Web link. `user_id` и email FG добавит сам.
2. В приложении: своя схема в `CFBundleURLTypes` и/или Associated Domains с `applinks:<домен>` и AASA на этом домене, SDK с publishable key проекта.
3. Убедиться, что в опубликованной воронке «Open app now» открывает приложение и ссылка содержит `user_id`.

## Проверка

**SDK** (`swift test` и `xcodebuild test` на симуляторе, стабы через `URLProtocol`):

- разбор ссылок: принимаются `https` с любого хоста, `http`, своя схема и URL без хоста; не принимаются ссылки с отсутствующим, пустым, слишком длинным и с пробелами `user_id`; из двух `user_id` в одной ссылке берётся первый;
- email: сохраняется вместе с `user_id`; `%40` и `%2B` декодируются; негодный email игнорируется, а `user_id` сохраняется; ссылка с email без `user_id` не принимается; тот же `user_id` без email оставляет прежний email; другой `user_id` без email стирает его; `reset()` удаляет оба;
- клиент FG: заголовки и тело обоих запросов, повтор на 503, маппинг ошибок, 404 от `track_login` — `.unknownUser`;
- маппинг ответов `verify_subscription`: active, test при обоих значениях `acceptTestSubscriptions`, `user: null`;
- логика `FunnelsGrove`: без пользователя оба метода не ходят в сеть; опрос после свежей ссылки; новая ссылка или `reset()` во время проверки; отмена задачи; `handle` не вызывает `track_login`; `trackLogin` отправляет текущий id;
- `configure` отклоняет пустой и секретный ключ (тест логики проверки, без `precondition`);
- логика хранения на фейке.

Юнит-тест пакета до реального Keychain не доходит: неподписанный тестовый бандл получает `errSecMissingEntitlement` (-34018) и на macOS, и на iOS-симуляторе (проверено для AppsiloveSDK 25 октября). Реальная запись и чтение проверяются вручную в подписанном демо-приложении: перезапуск, удаление и повторная установка.

**E2E вручную на устройстве:**

1. Тестовый FG-проект с опубликованной воронкой и App Store deeplink `fgdemo://open`.
2. Тестовая покупка, затем тап «Open app now».
3. Демо открывается и показывает `user_id`, email покупки и активную test-подписку.
4. Track login — в FG у этого пользователя появляется «Logged into app». Повторный Track login новое событие не создаёт.
5. Удалить приложение и поставить заново: `user_id` и email на месте, Check снова показывает активную подписку.
6. По желанию — то же через Web link на домене с AASA.

## Риски, принятые для v1

1. **Ссылка равна доступу.** `user_id` в URL работает как пропуск: кто переслал ссылку, тот поделился подпиской. С ней же уходит email покупателя.
2. **Чужая ссылка заменяет пользователя.** Любой сайт может открыть схему приложения или дать Universal Link с чужим `user_id`, и SDK заменит сохранённого пользователя. Safari перед открытием своей схемы спрашивает, Universal Link требует тапа. Это тот же класс риска, что и пункт 1.
3. **Свои ссылки приложения с `user_id`.** Если приложение отдаёт SDK свою ссылку с параметром `user_id` в другом смысле, SDK примет её за ссылку FG. Защита — порядок разбора, описанный в README.
4. **«Logged into app» зависит от приложения.** Если приложение не вызывает `trackLogin()`, метрика в FG остаётся пустой.
5. **Один `user_id` в нескольких воронках проекта.** `track_login` тогда отвечает 400 и требует `funnelId`, которого в ссылке FG нет. `trackLogin()` бросает `.configuration`. Случай редкий, принят.
6. **Своя схема без установленного приложения.** Если задан App Store deeplink, а приложения нет, «Open app now» никуда не ведёт. Покупатель ставит приложение кнопкой App Store на том же экране и тапает «Open app now» ещё раз. Отложенного диплинка нет.
7. **Авто-переход FG и встроенные браузеры.** Переход без тапа и браузеры TikTok и Instagram часто не открывают приложение.
8. **Задержка CDN Apple.** Для Universal Links CDN запрашивает AASA в течение 24 часов, устройства перечитывают его примерно раз в неделю.
9. **Keychain не гарантирован.** Сохранность записи после удаления приложения — поведение iOS, а не гарантия Apple. Через iCloud Keychain запись попадает на другие устройства того же Apple ID, вместе с email.
10. **Проверка на клиенте.** На взломанном устройстве результат проверки можно подменить. Так у любого приложения без своего бэкенда.

## Вне объёма v1

- Страница управления подпиской и вход по коду из письма.
- Отложенный диплинк.
- Android.
- Хостинг AASA: домен Universal Links — забота приложения.
- Перенос сохранённых пользователей из AppsiloveSDK.
- `user_id` из других источников: AppsFlyer, свой бэкенд приложения.
- `funnelId` и `runtimeEnvironment` в `track_login`.
- app-open API и `click_id` из дизайна FG project universal links (`go.funnelsgrove.com`, 5 августа 2026).
- Изменения кода FG.
- Теги версий: до первого тега пакет подключается по ветке.

## Что нужно от владельца перед реализацией

- Apple Team ID и bundle ID демо-приложения.
- Тестовый FG-проект с опубликованной воронкой, App Store deeplink `fgdemo://open` и его publishable key.
- Для проверки Universal Link — по желанию: строка `fgdemo` в `link_apps` appsilove с Team ID и bundle ID демо.
