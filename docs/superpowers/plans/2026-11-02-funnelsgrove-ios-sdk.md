# FunnelsGroveSDK для iOS: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swift Package `FunnelsGroveSDK` принимает ссылку из воронки FunnelsGrove с любого домена и с любой схемой, хранит `user_id` и `email` из неё в Keychain, проверяет подписку и по вызову приложения записывает «Logged into app». Демо-приложение проверяет всю цепочку на устройстве.

**Architecture:**
- Публичный API — `@MainActor` фасад `FunnelsGrove` над тремя внутренними частями:
  - `LinkParser` достаёт из ссылки `LinkedUser` (`user_id` и `email`);
  - `UserStore` хранит `LinkedUser` одной записью Keychain с синком через iCloud;
  - `FunnelsGroveClient` вызывает `verify_subscription` и `track_login` с publishable key.
- Код перенесён из AppsiloveSDK с правками: без `linkHost`, страницы управления и входа по коду, с email из ссылки и публичным `trackLogin()`.
- Зависимости передаются через internal init, поэтому тесты работают на фейках и на `URLProtocol`-стабе.
- Демо-приложение генерируется XcodeGen и подключает пакет как локальный.

**Tech Stack:** Swift 6.3.3 (Xcode 26.6), `swift-tools-version: 6.0`, XCTest, XcodeGen 2.46.

**Spec:** [docs/superpowers/specs/2026-11-02-funnelsgrove-ios-sdk-design.md](../specs/2026-11-02-funnelsgrove-ios-sdk-design.md)

---

## Перед началом

- **Где работать.** Репозиторий `/Users/e/work2/appsilove/funnelsgrove-ios-sdk`, ветка `feat/sdk-prototype`. В ней пока один коммит со спекой (`b75bc0e`), ветки `main` нет ни локально, ни на GitHub (`git@github.com:The-Solid-Grove/funnelsgrove-ios-sdk.git`, репозиторий приватный и пустой). Вся работа идёт в `feat/sdk-prototype`. Push не делаем, его решает владелец (задача 8, шаг 7).
- **Источник.** AppsiloveSDK лежит в `/Users/e/work2/appsilove/appsilove-ios-sdk`. Весь код ниже приведён целиком, копировать оттуда ничего не нужно.
- **Задачи 1–6 и шаги 1–9 задачи 7** выполняются локально без доступов.
- **Шаг 10 задачи 7 и задача 8 требуют участия владельца:**
  - Apple Team ID и подпись в Xcode;
  - тестовый FG-проект с опубликованной воронкой и его publishable key;
  - для задачи 8 — iPhone.
- **Проверка кода.** Код прогнан в scratch-копии 2 ноября:
  - после каждой задачи собирается и проходит своё число тестов, в конце 65 тестов на macOS (`swift test`) и на iOS-симуляторе (`xcodebuild test`), без предупреждений в Swift 6 language mode;
  - демо-приложение собирается без подписи; на симуляторе ссылка `fgdemo://open?user_id=u_sim_check&email=buyer%2Bqa%40example.com` из Safari сохраняет `u_sim_check` и `buyer+qa@example.com`;
  - примеры кода из README компилируются против iOS SDK.
- **Keychain юнит-тестами не покрывается.** Неподписанный тестовый бандл получает `errSecMissingEntitlement` (-34018) и на macOS, и на симуляторе, это проверено для AppsiloveSDK. Юнит-тесты проверяют формат записи и логику на фейке, реальное хранение — задачи 7 и 8 на подписанном демо-приложении.

## Карта файлов

| Файл | Ответственность |
| --- | --- |
| `Package.swift` | Пакет `FunnelsGroveSDK`: iOS 15+, macOS 12 для `swift test` |
| `Sources/FunnelsGroveSDK/FunnelsGroveError.swift` | Публичные ошибки |
| `Sources/FunnelsGroveSDK/LinkedUser.swift` | `user_id` и `email` покупателя, формат записи в Keychain |
| `Sources/FunnelsGroveSDK/LinkParser.swift` | Ссылка → `LinkedUser` или `nil`, правила для `user_id` и `email` |
| `Sources/FunnelsGroveSDK/FunnelsGroveClient.swift` | HTTP-клиент FG: `verify_subscription`, `track_login`, повтор на 503, маппинг ошибок |
| `Sources/FunnelsGroveSDK/UserStore.swift` | Протокол хранилища и реализация на Keychain |
| `Sources/FunnelsGroveSDK/SubscriptionStatus.swift` | Публичный результат проверки |
| `Sources/FunnelsGroveSDK/FunnelsGrove.swift` | Фасад: `configure`, `shared`, `handle`, `userId`, `email`, `checkSubscription`, `trackLogin`, `reset` |
| `Tests/FunnelsGroveSDKTests/*.swift` | Тесты и тестовые дублёры |
| `README.md` | Подключение SDK, настройка FG-проекта, поведение, демо, тесты |
| `Examples/FunnelsGroveDemo/…` | Демо-приложение: XcodeGen `project.yml`, xcconfig-файлы, entitlements для Universal Links, исходники SwiftUI |

---

### Task 1: Каркас пакета

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/FunnelsGroveSDK/FunnelsGroveError.swift`
- Create: `Tests/FunnelsGroveSDKTests/.gitkeep`

- [ ] **Step 1: Проверить ветку**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && git branch --show-current && git log --oneline
```

Ожидается: `feat/sdk-prototype` и один коммит `b75bc0e docs: design the FunnelsGrove iOS SDK`.

- [ ] **Step 2: Написать `Package.swift`**

Имя модуля отличается от имени главного типа `FunnelsGrove`: иначе Swift не разберёт квалифицированные имена вроде `FunnelsGrove.SubscriptionStatus`.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FunnelsGroveSDK",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "FunnelsGroveSDK", targets: ["FunnelsGroveSDK"]),
    ],
    targets: [
        .target(name: "FunnelsGroveSDK"),
        .testTarget(name: "FunnelsGroveSDKTests", dependencies: ["FunnelsGroveSDK"]),
    ]
)
```

- [ ] **Step 3: Написать `.gitignore`**

```gitignore
.DS_Store
.build/
.swiftpm/
DerivedData/
xcuserdata/

# Demo app: generated by XcodeGen, plus local signing settings
Examples/FunnelsGroveDemo/FunnelsGroveDemo.xcodeproj/
Examples/FunnelsGroveDemo/Support/
Examples/FunnelsGroveDemo/Config/Local.xcconfig
```

- [ ] **Step 4: Написать `Sources/FunnelsGroveSDK/FunnelsGroveError.swift`**

```swift
import Foundation

/// Errors thrown by FunnelsGroveSDK.
public enum FunnelsGroveError: Error, Equatable, Sendable {
    /// FunnelsGrove rejected the request with 400 or 401, usually because of a wrong `publishableKey`. From
    /// `trackLogin()`, a 400 can also mean that the user ID exists in several funnels of the project.
    case configuration(String)
    /// FunnelsGrove answered with another non-2xx status or a body the SDK cannot read. `statusCode` is 0 when the
    /// answer was not HTTP.
    case server(statusCode: Int)
    /// No answer came from FunnelsGrove: no connection, a timeout or a lost connection. The request may still have
    /// reached it.
    case network(URLError)
    /// `trackLogin()`: FunnelsGrove has no such user in the project of `publishableKey`, for example after a link
    /// from another project's funnel.
    case unknownUser
}
```

- [ ] **Step 5: Собрать**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && mkdir -p Tests/FunnelsGroveSDKTests && touch Tests/FunnelsGroveSDKTests/.gitkeep && swift build
```

Ожидается: `Build complete!`. Предупреждение `Source files for target FunnelsGroveSDKTests should be located under 'Tests/FunnelsGroveSDKTests'` нормально до задачи 2: в тестовом таргете ещё нет исходников.

Без папки `Tests/FunnelsGroveSDKTests` SwiftPM 6.3 берёт `Sources/` как исходники тестового таргета и падает с `target 'FunnelsGroveSDKTests' has overlapping sources`. Пустую папку git не хранит, поэтому в ней лежит `.gitkeep` до задачи 2.

- [ ] **Step 6: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add Package.swift .gitignore Sources/FunnelsGroveSDK/FunnelsGroveError.swift Tests/FunnelsGroveSDKTests/.gitkeep
git commit -m "chore: scaffold the FunnelsGroveSDK package" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Ссылка: `user_id` и `email`

**Files:**
- Create: `Sources/FunnelsGroveSDK/LinkedUser.swift`
- Create: `Sources/FunnelsGroveSDK/LinkParser.swift`
- Test: `Tests/FunnelsGroveSDKTests/LinkParserTests.swift`
- Delete: `Tests/FunnelsGroveSDKTests/.gitkeep`

Правила из спеки (раздел «handle» и «Email из ссылки»):
- подходит любая схема и любой хост, в том числе URL без хоста; путь не проверяется;
- `user_id` — первый параметр с именем ровно `user_id`, после percent-decoding: непустой, до 256 байт в UTF-8, без пробелов и управляющих символов;
- `email` — первый параметр с именем ровно `email`, после percent-decoding и обрезки пробелов по краям: непустой, до 254 байт, с `@`, без пробелов и управляющих символов; негодный email считается отсутствующим, а `user_id` остаётся;
- ссылка без годного `user_id` не подходит, даже если в ней есть email.

`URLComponents.queryItems` декодирует `%2B` и `%40`, а литеральный `+` оставляет `+`: это и нужно для email.

- [ ] **Step 1: Написать падающий тест**

`Tests/FunnelsGroveSDKTests/LinkParserTests.swift`:

```swift
import XCTest
@testable import FunnelsGroveSDK

final class LinkParserTests: XCTestCase {
    private func user(_ link: String) -> LinkedUser? {
        LinkParser.user(from: URL(string: link)!)
    }

    func testReadsTheUserAndEmailFromAFunnelsGroveLink() {
        XCTAssertEqual(
            user("https://go.example.com/open?user_id=u_123&email=buyer%40example.com&utm_source=fg"),
            LinkedUser(userId: "u_123", email: "buyer@example.com")
        )
    }

    func testAcceptsAnyHostAndScheme() {
        for link in [
            "https://any.example.org/some/path?user_id=u_1",
            "https://GO.Example.com/open?user_id=u_1",
            "http://example.com/?user_id=u_1",
            "fgdemo://open?user_id=u_1",
            "fgdemo:?user_id=u_1",
        ] {
            XCTAssertEqual(user(link), LinkedUser(userId: "u_1"), link)
        }
    }

    func testTakesTheFirstUserIdAndEmail() {
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&user_id=u_2")?.userId, "u_1")
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=a%40b.co&email=c%40d.co")?.email, "a@b.co")
        // The first email counts even when it cannot be an address.
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=nonsense&email=c%40d.co"), LinkedUser(userId: "u_1"))
    }

    func testRejectsMissingOrMalformedUserIds() {
        XCTAssertNil(user("https://go.example.com/open"))
        XCTAssertNil(user("https://go.example.com/open?user_id"))
        XCTAssertNil(user("https://go.example.com/open?user_id="))
        XCTAssertNil(user("https://go.example.com/open?User_Id=u_1"))
        XCTAssertNil(user("https://go.example.com/open?user_id=u%201"))
        XCTAssertNil(user("https://go.example.com/open?user_id=u_1%0A"))
        // NUL is a control character but not whitespace.
        XCTAssertNil(user("https://go.example.com/open?user_id=u_1%00"))
        XCTAssertNil(user("https://go.example.com/open?user_id=" + String(repeating: "a", count: 257)))
        // One grapheme, 601 UTF-8 bytes: "a" followed by 300 combining acute accents.
        XCTAssertNil(user("https://go.example.com/open?user_id=a" + String(repeating: "%CC%81", count: 300)))
    }

    func testRejectsAnEmailWithoutAUserId() {
        XCTAssertNil(user("fgdemo://open?email=buyer%40example.com"))
    }

    func testAcceptsTheLongestAllowedUserId() {
        let longest = String(repeating: "a", count: 256)
        XCTAssertEqual(user("https://go.example.com/open?user_id=" + longest)?.userId, longest)
    }

    func testDecodesAndTrimsTheEmail() {
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=a%2Bb%40example.com")?.email, "a+b@example.com")
        // A literal + stays a +: FunnelsGrove encodes it, a hand-made link may not.
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=a+b@example.com")?.email, "a+b@example.com")
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=%20buyer%40example.com%20")?.email, "buyer@example.com")
    }

    func testDropsAnEmailThatCannotBeOneButKeepsTheUser() {
        for email in [
            "",
            "%20",
            "buyer.example.com",
            "a%20b%40example.com",
            "a%0A%40example.com",
            // A right-to-left override: a control character that is not whitespace.
            "a%E2%80%AE%40example.com",
            String(repeating: "a", count: 250) + "%40b.co",
            // 130 characters, 255 UTF-8 bytes.
            String(repeating: "%C3%BC", count: 125) + "%40b.co",
        ] {
            XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=" + email), LinkedUser(userId: "u_1"), email)
        }
    }

    func testAcceptsTheLongestAllowedEmail() {
        let longest = String(repeating: "a", count: 249) + "@b.co"
        XCTAssertEqual(longest.utf8.count, 254)
        XCTAssertEqual(user("fgdemo://open?user_id=u_1&email=" + longest)?.email, longest)
    }
}
```

- [ ] **Step 2: Убедиться, что тест падает**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && rm Tests/FunnelsGroveSDKTests/.gitkeep && swift test
```

Ожидается: компиляция падает с `error: cannot find 'LinkedUser' in scope`.

- [ ] **Step 3: Написать `Sources/FunnelsGroveSDK/LinkedUser.swift`**

`LinkedUser` — и результат разбора ссылки, и значение записи в Keychain. `encode(to:)` пишет `"email": null` явно, как в спеке; чтение принимает и запись без ключа `email`.

```swift
import Foundation

/// A FunnelsGrove buyer: the user ID and, when a link carried one, the email they bought with. Also the keychain
/// record: the coding keys are a stored format, and renaming one loses the user saved by an earlier version. New keys
/// are safe, since older versions ignore them; a changed type makes older versions drop the user.
struct LinkedUser: Codable, Equatable, Sendable {
    let userId: String
    /// Not verified: the address the buyer typed in the funnel, known to anyone who has the link.
    let email: String?

    init(userId: String, email: String? = nil) {
        self.userId = userId
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case userId
        case email
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        // An explicit null rather than a missing key.
        try container.encode(email, forKey: .email)
    }
}
```

- [ ] **Step 4: Написать `Sources/FunnelsGroveSDK/LinkParser.swift`**

```swift
import Foundation

enum LinkParser {
    static let maxUserIdLength = 256
    static let maxEmailLength = 254

    /// Returns the buyer a FunnelsGrove link carries, or `nil` when the first `user_id` in its query is missing or
    /// not valid.
    /// Any scheme and host pass: the app's entitlements, its AASA file and its URL types decide which links open it.
    static func user(from url: URL) -> LinkedUser? {
        guard
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let userId = items.first(where: { $0.name == "user_id" })?.value,
            isValidUserId(userId)
        else {
            return nil
        }
        return LinkedUser(userId: userId, email: validEmail(items.first(where: { $0.name == "email" })?.value))
    }

    /// Non-empty, at most 256 UTF-8 bytes, no whitespace or control characters. The byte limit keeps a letter
    /// with a thousand combining marks from passing as one character.
    static func isValidUserId(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maxUserIdLength && !value.unicodeScalars.contains(where: isForbidden)
    }

    /// The trimmed value if it passes a loose check: at most 254 UTF-8 bytes, an `@`, no whitespace or control
    /// characters inside. It keeps blanks, line breaks and invisible characters out of the app, but `@` alone still
    /// passes, and it does not prove that the address works or belongs to the user.
    static func validEmail(_ value: String?) -> String? {
        guard
            let email = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !email.isEmpty,
            email.utf8.count <= maxEmailLength,
            email.contains("@"),
            !email.unicodeScalars.contains(where: isForbidden)
        else {
            return nil
        }
        return email
    }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
    }
}
```

- [ ] **Step 5: Убедиться, что тесты проходят**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test
```

Ожидается: `Executed 9 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add Sources/FunnelsGroveSDK/LinkedUser.swift Sources/FunnelsGroveSDK/LinkParser.swift Tests/FunnelsGroveSDKTests/LinkParserTests.swift Tests/FunnelsGroveSDKTests/.gitkeep
git commit -m "feat: read the FunnelsGrove user and email from a link of any scheme and host" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`git add` для удалённого `.gitkeep` записывает его удаление.

---

### Task 3: Клиент FunnelsGrove

**Files:**
- Create: `Tests/FunnelsGroveSDKTests/StubURLProtocol.swift`
- Create: `Tests/FunnelsGroveSDKTests/SleepRecorder.swift`
- Create: `Tests/FunnelsGroveSDKTests/Assertions.swift`
- Test: `Tests/FunnelsGroveSDKTests/FunnelsGroveClientTests.swift`
- Create: `Sources/FunnelsGroveSDK/FunnelsGroveClient.swift`

Контракт FG (спека, «Что уже есть в FG»):
- оба запроса — `POST` с `Content-Type: application/json`, `X-SDK-Publishable-Key` и телом `{"userId": "<id>"}`, таймаут 10 секунд, без редиректов на уровне кода (их выполняет `URLSession`, как в AppsiloveSDK);
- на 503 с `Retry-After` от 0 до 10 секунд — одно ожидание и повтор; HTTP-дата, отрицательное и большее значение дают `.server(503)`;
- 400 и 401 — `.configuration`, остальные не-2xx — `.server`, `URLError` — `.network`, отмена — `CancellationError`;
- `verify_subscription`: тело 2xx, которое не разбирается, — `.server` с этим кодом;
- `track_login`: 404 — `.unknownUser`, тело ответа не разбирается. В отличие от AppsiloveSDK, 503 повторяется: FG не дублирует событие входа.

- [ ] **Step 1: Написать тестовые помощники**

`Tests/FunnelsGroveSDKTests/StubURLProtocol.swift` (тот же, что в AppsiloveSDK):

```swift
import Foundation

/// Answers URLSession requests from a queue of canned responses and records the requests.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    // URLSession calls startLoading on its own thread while tests read `requests`.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queuedHandlers: [Handler] = []
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    static func reset() {
        lock.withLock {
            queuedHandlers = []
            recordedRequests = []
        }
    }

    private static func enqueue(_ handler: @escaping Handler) {
        lock.withLock { queuedHandlers.append(handler) }
    }

    private static func record(_ request: URLRequest) -> Handler? {
        lock.withLock {
            recordedRequests.append(request)
            return queuedHandlers.isEmpty ? nil : queuedHandlers.removeFirst()
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func respond(_ statusCode: Int, json: String, headers: [String: String] = [:]) {
        enqueue { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers.merging(["Content-Type": "application/json"]) { current, _ in current }
            )!
            return (response, Data(json.utf8))
        }
    }

    static func fail(_ code: URLError.Code) {
        enqueue { _ in throw URLError(code) }
    }

    /// Leaves the next request unanswered until its task is cancelled.
    static func hang() {
        enqueue { _ in throw Hang() }
    }

    private struct Hang: Error {}

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.record(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch is Hang {
            return
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLSession hands the body to URL protocols as a stream.
    func jsonBody() -> [String: String]? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
```

`Tests/FunnelsGroveSDKTests/SleepRecorder.swift`:

```swift
import Foundation

/// Stands in for `Task.sleep` and remembers the requested delays.
actor SleepRecorder {
    private(set) var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }
}
```

`Tests/FunnelsGroveSDKTests/Assertions.swift`. Помощник не изолирован от актора, поэтому в `@MainActor`-тестах фасада (задача 5) вместо него стоит `do/catch`: Swift 6 не даёт передать туда замыкание с `sdk`.

```swift
import XCTest
@testable import FunnelsGroveSDK

/// Fails unless `body` throws exactly `expected`.
func assertThrows(
    _ expected: FunnelsGroveError,
    message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Expected \(expected) \(message)", file: file, line: line)
    } catch let error as FunnelsGroveError {
        XCTAssertEqual(error, expected, message, file: file, line: line)
    } catch {
        XCTFail("Unexpected error \(error) \(message)", file: file, line: line)
    }
}
```

- [ ] **Step 2: Написать падающий тест**

`Tests/FunnelsGroveSDKTests/FunnelsGroveClientTests.swift`:

```swift
import XCTest
@testable import FunnelsGroveSDK

final class FunnelsGroveClientTests: XCTestCase {
    private var sleeps = SleepRecorder()
    private var client: FunnelsGroveClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        sleeps = SleepRecorder()
        let sleeps = sleeps
        client = FunnelsGroveClient(
            baseURL: URL(string: "https://sdk-api.example.com")!,
            publishableKey: "pk_test",
            session: StubURLProtocol.session(),
            sleep: { await sleeps.record($0) }
        )
    }

    func testVerifySendsThePublishableKeyAndUserId() async throws {
        StubURLProtocol.respond(200, json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#)

        let response = try await client.verifySubscription(userId: "u_1")

        XCTAssertEqual(response, VerifySubscriptionResponse(active: true, test: false, user: .init(userId: "u_1")))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sdk-api.example.com/sdk/public/users/verify_subscription")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SDK-Publishable-Key"), "pk_test")
        XCTAssertEqual(request.jsonBody(), ["userId": "u_1"])
    }

    func testVerifyReadsAnUnknownUser() async throws {
        StubURLProtocol.respond(200, json: #"{"active":false,"test":false,"user":null}"#)

        let response = try await client.verifySubscription(userId: "u_1")

        XCTAssertEqual(response, VerifySubscriptionResponse(active: false, test: false, user: nil))
    }

    func testVerifyMaps400And401ToConfiguration() async {
        for status in [400, 401] {
            StubURLProtocol.respond(status, json: #"{"error":"invalid key"}"#)

            await assertThrows(.configuration("FunnelsGrove answered \(status): check publishableKey")) {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
        }
    }

    func testVerifyMapsOtherStatusesToServer() async {
        // The status wins over a readable body, and only a 503 is retried, whatever Retry-After says.
        for status in [300, 403, 404, 429, 500] {
            StubURLProtocol.reset()
            StubURLProtocol.respond(
                status,
                json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#,
                headers: ["Retry-After": "1"]
            )

            await assertThrows(.server(statusCode: status), message: "\(status)") {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
            XCTAssertEqual(StubURLProtocol.requests.count, 1, "\(status)")
        }
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [])
    }

    func testVerifyMapsAnUnreadableBodyToServer() async {
        StubURLProtocol.respond(200, json: "not json")

        await assertThrows(.server(statusCode: 200)) {
            _ = try await self.client.verifySubscription(userId: "u_1")
        }
    }

    func testVerifyRetriesOnceAfterAShort503() async throws {
        for retryAfter in ["0", "10"] {
            StubURLProtocol.reset()
            StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": retryAfter])
            StubURLProtocol.respond(200, json: #"{"active":true,"test":false,"user":{"user_id":"u_1"}}"#)

            let response = try await client.verifySubscription(userId: "u_1")

            XCTAssertTrue(response.active, retryAfter)
            XCTAssertEqual(StubURLProtocol.requests.count, 2, retryAfter)
        }
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [0, 10])
    }

    func testVerifyReportsA503ThatAsksToWaitTooLongOrNamesNoUsableWait() async {
        for retryAfter in ["11", "-1", "Wed, 21 Oct 2026 07:28:00 GMT", nil] {
            let label = retryAfter ?? "no Retry-After"
            StubURLProtocol.reset()
            StubURLProtocol.respond(503, json: "{}", headers: retryAfter.map { ["Retry-After": $0] } ?? [:])

            await assertThrows(.server(statusCode: 503), message: label) {
                _ = try await self.client.verifySubscription(userId: "u_1")
            }
            XCTAssertEqual(StubURLProtocol.requests.count, 1, label)
        }
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [])
    }

    func testVerifyReportsASecond503() async {
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "1"])
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "1"])

        await assertThrows(.server(statusCode: 503)) {
            _ = try await self.client.verifySubscription(userId: "u_1")
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testVerifyMapsTransportFailuresToNetwork() async {
        StubURLProtocol.fail(.notConnectedToInternet)

        do {
            _ = try await client.verifySubscription(userId: "u_1")
            XCTFail("Expected a network error")
        } catch FunnelsGroveError.network(let error) {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testVerifyReportsCancellationAsCancellation() async throws {
        StubURLProtocol.hang()
        let client = try XCTUnwrap(client)
        let task = Task { try await client.verifySubscription(userId: "u_1") }
        for _ in 0..<500 where StubURLProtocol.requests.isEmpty {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testTrackLoginPostsTheUserId() async throws {
        StubURLProtocol.respond(200, json: #"{"user":{"user_id":"u_1"},"login":{"tracked":true,"newlyTracked":true}}"#)

        try await client.trackLogin(userId: "u_1")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sdk-api.example.com/sdk/public/users/track_login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-SDK-Publishable-Key"), "pk_test")
        XCTAssertEqual(request.jsonBody(), ["userId": "u_1"])
    }

    func testTrackLoginIgnoresTheResponseBody() async throws {
        for (status, body) in [(200, "not json"), (204, "")] {
            StubURLProtocol.respond(status, json: body)

            try await client.trackLogin(userId: "u_1")
        }
    }

    func testTrackLoginRetriesOnceAfterAShort503() async throws {
        StubURLProtocol.respond(503, json: "{}", headers: ["Retry-After": "1"])
        StubURLProtocol.respond(200, json: "{}")

        try await client.trackLogin(userId: "u_1")

        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1])
    }

    func testTrackLoginMaps404ToUnknownUser() async {
        StubURLProtocol.respond(404, json: #"{"error":"Funnel user not found"}"#)

        await assertThrows(.unknownUser) {
            try await self.client.trackLogin(userId: "u_1")
        }
    }

    func testTrackLoginMapsOtherErrors() async {
        StubURLProtocol.respond(400, json: #"{"error":"funnelId is required"}"#)
        await assertThrows(.configuration("FunnelsGrove answered 400: check publishableKey")) {
            try await self.client.trackLogin(userId: "u_1")
        }

        StubURLProtocol.respond(500, json: "{}")
        await assertThrows(.server(statusCode: 500)) {
            try await self.client.trackLogin(userId: "u_1")
        }
    }
}
```

- [ ] **Step 3: Убедиться, что тест падает**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test
```

Ожидается: компиляция падает с `error: cannot find 'VerifySubscriptionResponse' in scope` (и с той же ошибкой для `FunnelsGroveClient`).

- [ ] **Step 4: Написать `Sources/FunnelsGroveSDK/FunnelsGroveClient.swift`**

Отправка запроса и маппинг `URLError` живут прямо в клиенте: в AppsiloveSDK они были в `HTTP.swift`, потому что их делили два клиента, а здесь клиент один.

```swift
import Foundation

typealias Sleep = @Sendable (TimeInterval) async throws -> Void

func sleepSeconds(_ seconds: TimeInterval) async throws {
    // UInt64 traps on negative or non-finite values.
    guard seconds.isFinite, seconds > 0 else { return }
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

struct VerifySubscriptionResponse: Decodable, Equatable, Sendable {
    struct User: Decodable, Equatable, Sendable {
        let userId: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
        }
    }

    let active: Bool
    let test: Bool
    let user: User?
}

protocol FunnelsGroveAPI: Sendable {
    func verifySubscription(userId: String) async throws -> VerifySubscriptionResponse
    func trackLogin(userId: String) async throws
}

/// Calls the FunnelsGrove public SDK API with the project's publishable key.
struct FunnelsGroveClient: FunnelsGroveAPI {
    /// A 503 asking to wait longer than this is reported instead of retried.
    static let maxRetryAfter: TimeInterval = 10

    let baseURL: URL
    let publishableKey: String
    var session: URLSession = .shared
    var sleep: Sleep = sleepSeconds

    func verifySubscription(userId: String) async throws -> VerifySubscriptionResponse {
        let (data, response) = try await send("sdk/public/users/verify_subscription", userId: userId)
        try check(response)
        do {
            return try JSONDecoder().decode(VerifySubscriptionResponse.self, from: data)
        } catch {
            throw FunnelsGroveError.server(statusCode: response.statusCode)
        }
    }

    /// FunnelsGrove records one login per user, funnel and environment, so a repeated or retried call adds nothing.
    func trackLogin(userId: String) async throws {
        let (_, response) = try await send("sdk/public/users/track_login", userId: userId)
        if response.statusCode == 404 { throw FunnelsGroveError.unknownUser }
        try check(response)
    }

    /// Posts `{"userId": …}`, and once more after a 503 that asks for a short wait.
    private func send(_ path: String, userId: String) async throws -> (Data, HTTPURLResponse) {
        var (data, response) = try await post(path, userId: userId)
        if response.statusCode == 503, let delay = retryAfter(response), (0...Self.maxRetryAfter).contains(delay) {
            try await sleep(delay)
            (data, response) = try await post(path, userId: userId)
        }
        return (data, response)
    }

    private func post(_ path: String, userId: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "X-SDK-Publishable-Key")
        request.httpBody = try JSONEncoder().encode(["userId": userId])
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FunnelsGroveError.server(statusCode: 0)
            }
            return (data, httpResponse)
        } catch let error as URLError {
            // A SwiftUI `.task` whose view went away is not a network failure.
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            throw FunnelsGroveError.network(error)
        }
    }

    /// Seconds from `Retry-After`; an HTTP date is ignored.
    private func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
    }

    private func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 400, 401:
            throw FunnelsGroveError.configuration("FunnelsGrove answered \(response.statusCode): check publishableKey")
        default:
            throw FunnelsGroveError.server(statusCode: response.statusCode)
        }
    }
}
```

- [ ] **Step 5: Убедиться, что тесты проходят**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test
```

Ожидается: `Executed 24 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add Sources/FunnelsGroveSDK/FunnelsGroveClient.swift Tests/FunnelsGroveSDKTests/StubURLProtocol.swift Tests/FunnelsGroveSDKTests/SleepRecorder.swift Tests/FunnelsGroveSDKTests/Assertions.swift Tests/FunnelsGroveSDKTests/FunnelsGroveClientTests.swift
git commit -m "feat: call FunnelsGrove verify_subscription and track_login" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Хранение в Keychain

**Files:**
- Create: `Sources/FunnelsGroveSDK/UserStore.swift`
- Test: `Tests/FunnelsGroveSDKTests/UserStoreTests.swift`

Одна запись generic password: `kSecAttrService = "com.funnelsgrove.sdk"`, `kSecAttrAccount = "user"`, значение — JSON `LinkedUser`. Доступность `AfterFirstUnlock`, синхронизация через iCloud Keychain, чтение и удаление с `kSecAttrSynchronizableAny`. Неизменённая запись не перезаписывается. Запись, которую не удалось разобрать или в которой негодный `user_id`, считается отсутствующей; негодный email в записи читается как `nil`, теми же правилами, что в ссылке. Тесты проверяют формат записи; сами вызовы Keychain — в задаче 7.

- [ ] **Step 1: Написать падающий тест**

`Tests/FunnelsGroveSDKTests/UserStoreTests.swift`:

```swift
import XCTest
@testable import FunnelsGroveSDK

/// The keychain calls themselves need a signed app: see the demo app. These tests cover the stored data.
final class UserStoreTests: XCTestCase {
    func testStoresTheIdAndEmailAsJSON() throws {
        let data = try KeychainUserStore.encode(LinkedUser(userId: "u_1", email: "buyer@example.com"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["userId": "u_1", "email": "buyer@example.com"])
    }

    func testStoresAMissingEmailAsNull() throws {
        let data = try KeychainUserStore.encode(LinkedUser(userId: "u_1"))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["userId"] as? String, "u_1")
        XCTAssertTrue(object["email"] is NSNull)
    }

    func testReadsBackWhatItStores() throws {
        for user in [
            LinkedUser(userId: "u_1", email: "buyer@example.com"),
            LinkedUser(userId: "u_1"),
            LinkedUser(userId: String(repeating: "a", count: 256)),
            LinkedUser(userId: "u_1", email: String(repeating: "a", count: 249) + "@b.co"),
        ] {
            XCTAssertEqual(KeychainUserStore.decode(try KeychainUserStore.encode(user)), user)
        }
        // The stored email is read by the link rules, which trim it.
        XCTAssertEqual(
            KeychainUserStore.decode(Data(#"{"userId":"u_1","email":" buyer@example.com "}"#.utf8)),
            LinkedUser(userId: "u_1", email: "buyer@example.com")
        )
    }

    func testReadsAnItemWithoutAUsableEmail() {
        for email in [
            "",
            " ",
            "a b",
            "buyer.example.com",
            #"a\n@example.com"#,
            // A right-to-left override (JSON escape): a control character that is not whitespace.
            #"a\u202E@example.com"#,
            // 255 UTF-8 bytes.
            String(repeating: "a", count: 250) + "@b.co",
        ] {
            let json = #"{"userId":"u_1","email":""# + email + #""}"#
            XCTAssertEqual(KeychainUserStore.decode(Data(json.utf8)), LinkedUser(userId: "u_1"), json)
        }
        XCTAssertEqual(KeychainUserStore.decode(Data(#"{"userId":"u_1"}"#.utf8)), LinkedUser(userId: "u_1"))
    }

    func testTreatsDamagedDataAsNoUser() {
        for json in [
            "not json",
            "{}",
            #"{"userId":""}"#,
            #"{"userId":"u 1"}"#,
            #"{"userId":"u_1\n"}"#,
            // NUL is a control character but not whitespace.
            #"{"userId":"u_1\u0000"}"#,
            #"{"userId":""# + String(repeating: "a", count: 257) + #""}"#,
            #"{"userId":1}"#,
            // An email that is not a string makes the whole item unreadable, not just the email.
            #"{"userId":"u_1","email":5}"#,
            #""u_1""#,
        ] {
            XCTAssertNil(KeychainUserStore.decode(Data(json.utf8)), json)
        }
    }
}
```

- [ ] **Step 2: Убедиться, что тест падает**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test
```

Ожидается: компиляция падает с `error: cannot find 'KeychainUserStore' in scope`.

- [ ] **Step 3: Написать `Sources/FunnelsGroveSDK/UserStore.swift`**

```swift
import Foundation
import os
import Security

private let keychainLogger = Logger(subsystem: "com.funnelsgrove.sdk", category: "Keychain")

protocol UserStore {
    func read() -> LinkedUser?
    /// Writes `user` unless the stored one already reads as it. Pass a user that passes the link rules, as one from
    /// `LinkParser` or `read()` does: any other never matches `read()` and is rewritten on every save.
    func save(_ user: LinkedUser) throws
    func delete()
}

struct KeychainError: Error, Equatable, CustomStringConvertible {
    let status: OSStatus

    var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Keeps the linked user's ID and email in one keychain item, so they always change together, and lets iCloud
/// Keychain sync it. Keychain items outlive app deletion in practice; Apple does not guarantee it.
struct KeychainUserStore: UserStore {
    var service = "com.funnelsgrove.sdk"
    var account = "user"

    func read() -> LinkedUser? {
        var query = baseQuery()
        // Without SynchronizableAny the query skips iCloud-synced items.
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            log(status, action: "Reading the user")
            return nil
        }
        guard let user = Self.decode(data) else {
            keychainLogger.error("The stored user is unreadable: treating it as no user")
            return nil
        }
        return user
    }

    func save(_ user: LinkedUser) throws {
        // Rewriting an unchanged user would only churn iCloud Keychain sync.
        if read() == user { return }
        // Delete first so the add never hits errSecDuplicateItem, whatever the old item's sync state.
        delete()
        var attributes = baseQuery()
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = try Self.encode(user)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        log(SecItemDelete(query as CFDictionary), action: "Deleting the user")
    }

    static func encode(_ user: LinkedUser) throws -> Data {
        try JSONEncoder().encode(user)
    }

    /// The stored user, or `nil` for data that is not one: a damaged item must not turn into a user ID. The ID and
    /// the email pass the same checks as in a link, so tightening the ID check drops users stored under the old one.
    static func decode(_ data: Data) -> LinkedUser? {
        guard let user = try? JSONDecoder().decode(LinkedUser.self, from: data),
              LinkParser.isValidUserId(user.userId)
        else {
            return nil
        }
        return LinkedUser(userId: user.userId, email: LinkParser.validEmail(user.email))
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func log(_ status: OSStatus, action: String) {
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        keychainLogger.error("\(action, privacy: .public) failed: \(KeychainError(status: status).description, privacy: .public)")
    }
}
```

- [ ] **Step 4: Убедиться, что тесты проходят**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test
```

Ожидается: `Executed 29 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add Sources/FunnelsGroveSDK/UserStore.swift Tests/FunnelsGroveSDKTests/UserStoreTests.swift
git commit -m "feat: keep the user ID and email in one keychain item with iCloud sync" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Фасад `FunnelsGrove`

**Files:**
- Create: `Sources/FunnelsGroveSDK/SubscriptionStatus.swift`
- Create: `Sources/FunnelsGroveSDK/FunnelsGrove.swift`
- Create: `Tests/FunnelsGroveSDKTests/Fakes.swift`
- Test: `Tests/FunnelsGroveSDKTests/FunnelsGroveTests.swift`

Поведение из спеки:
- `configure` останавливает приложение, если ключ пустой, с пробельными символами или начинается с `sdk_sec_` или `fg_key_`. Проверка вынесена в `publishableKeyProblem(_:)`, чтобы тестировать её без `precondition`.
- `handle` сохраняет `LinkedUser`. Ссылка без годного email оставляет email того же `user_id` и стирает email другого. `handle` запоминает время ссылки и `track_login` не вызывает.
- `checkSubscription` — как в AppsiloveSDK без `manageSubscriptionURL`: опрос 1, 2, 4, 8 секунд в течение 120 секунд после ссылки, ответ для текущего пользователя.
- `trackLogin` без пользователя возвращает `false` без сети, иначе отправляет текущий `user_id` и возвращает `true`.
- `reset` удаляет запись и время ссылки.

- [ ] **Step 1: Написать тестовые дублёры**

`Tests/FunnelsGroveSDKTests/Fakes.swift`:

```swift
import Foundation
@testable import FunnelsGroveSDK

final class FakeUserStore: UserStore {
    var value: LinkedUser?
    var saveError: Error?

    func read() -> LinkedUser? { value }

    func save(_ user: LinkedUser) throws {
        if let saveError { throw saveError }
        value = user
    }

    func delete() { value = nil }
}

actor FakeFunnelsGrove: FunnelsGroveAPI {
    private var answers: [VerifySubscriptionResponse]
    private var verifyError: FunnelsGroveError?
    private var trackError: FunnelsGroveError?
    private var duringNextVerify: (@Sendable () async -> Void)?
    private(set) var verifiedUserIds: [String] = []
    private(set) var trackedUserIds: [String] = []

    init(answers: [VerifySubscriptionResponse]) {
        self.answers = answers
    }

    func failVerification(with error: FunnelsGroveError) {
        verifyError = error
    }

    func failTracking(with error: FunnelsGroveError) {
        trackError = error
    }

    /// Runs `action` while the next verify request is in flight.
    func duringNextVerify(_ action: @escaping @Sendable () async -> Void) {
        duringNextVerify = action
    }

    func verifySubscription(userId: String) async throws -> VerifySubscriptionResponse {
        verifiedUserIds.append(userId)
        if let action = duringNextVerify {
            duringNextVerify = nil
            await action()
        }
        if let verifyError { throw verifyError }
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }

    func trackLogin(userId: String) async throws {
        trackedUserIds.append(userId)
        if let trackError { throw trackError }
    }
}

final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}
```

- [ ] **Step 2: Написать падающий тест**

`Tests/FunnelsGroveSDKTests/FunnelsGroveTests.swift`:

```swift
import XCTest
@testable import FunnelsGroveSDK

@MainActor
final class FunnelsGroveTests: XCTestCase {
    private let link = URL(string: "https://go.example.com/open?user_id=u_1&email=buyer%40example.com")!
    private let active = VerifySubscriptionResponse(active: true, test: false, user: .init(userId: "u_1"))
    private let inactive = VerifySubscriptionResponse(active: false, test: false, user: .init(userId: "u_1"))
    private let activeTest = VerifySubscriptionResponse(active: true, test: true, user: .init(userId: "u_1"))
    private let unknown = VerifySubscriptionResponse(active: false, test: false, user: nil)

    private var store = FakeUserStore()
    private var clock = TestClock()
    private var sleeps = SleepRecorder()

    override func setUp() async throws {
        store = FakeUserStore()
        clock = TestClock()
        sleeps = SleepRecorder()
    }

    private func makeSDK(
        answers: [VerifySubscriptionResponse],
        acceptTestSubscriptions: Bool = false,
        sleep: Sleep? = nil
    ) -> (FunnelsGrove, FakeFunnelsGrove) {
        let fake = FakeFunnelsGrove(answers: answers)
        let clock = clock
        let sleeps = sleeps
        let sdk = FunnelsGrove(
            configuration: .init(acceptTestSubscriptions: acceptTestSubscriptions),
            store: store,
            client: fake,
            now: { clock.now },
            sleep: sleep ?? { await sleeps.record($0) }
        )
        return (sdk, fake)
    }

    // MARK: - Links

    func testHandleStoresTheUserAndEmailWithoutTrackingTheLogin() async throws {
        let (sdk, fake) = makeSDK(answers: [active])

        XCTAssertTrue(sdk.handle(link))

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
        XCTAssertEqual(sdk.userId, "u_1")
        XCTAssertEqual(sdk.email, "buyer@example.com")
        // A login sent from a task that handle started would arrive only after handle returns: give it time to.
        try await Task.sleep(nanoseconds: 100_000_000)
        let tracked = await fake.trackedUserIds
        XCTAssertEqual(tracked, [])
    }

    func testHandleAcceptsACustomScheme() {
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertTrue(sdk.handle(URL(string: "fgdemo://open?user_id=u_1")!))
        XCTAssertEqual(sdk.userId, "u_1")
        XCTAssertNil(sdk.email)
    }

    func testHandleIgnoresLinksWithoutAUserId() {
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertFalse(sdk.handle(URL(string: "https://go.example.com/open?email=buyer%40example.com")!))
        XCTAssertFalse(sdk.handle(URL(string: "myapp://profile?id=42")!))
        XCTAssertNil(store.value)
        XCTAssertNil(sdk.userId)
        XCTAssertNil(sdk.email)
    }

    func testHandleKeepsTheUserInMemoryWhenTheKeychainFails() {
        store.saveError = KeychainError(status: errSecIO)
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertTrue(sdk.handle(link))
        XCTAssertEqual(sdk.userId, "u_1")
        XCTAssertEqual(sdk.email, "buyer@example.com")
    }

    func testANewLinkReplacesTheStoredUserAndEmail() {
        store.value = LinkedUser(userId: "u_old", email: "old@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(link)

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
    }

    func testALinkWithoutAnEmailKeepsTheEmailOfTheSameUser() {
        store.value = LinkedUser(userId: "u_1", email: "buyer@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(URL(string: "fgdemo://open?user_id=u_1")!)

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
    }

    func testALinkWithAnUnusableEmailKeepsTheEmailOfTheSameUser() {
        store.value = LinkedUser(userId: "u_1", email: "buyer@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(URL(string: "fgdemo://open?user_id=u_1&email=nonsense")!)

        XCTAssertEqual(sdk.email, "buyer@example.com")
    }

    func testALinkWithoutAnEmailDropsTheEmailOfAnotherUser() {
        store.value = LinkedUser(userId: "u_old", email: "old@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(URL(string: "fgdemo://open?user_id=u_1")!)

        XCTAssertEqual(store.value, LinkedUser(userId: "u_1"))
        XCTAssertNil(sdk.email)
    }

    func testANewEmailReplacesTheEmailOfTheSameUser() {
        store.value = LinkedUser(userId: "u_1", email: "old@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        sdk.handle(link)

        XCTAssertEqual(sdk.email, "buyer@example.com")
    }

    func testHandleAcceptsABrowsingWebActivity() {
        let (sdk, _) = makeSDK(answers: [active])
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = link

        XCTAssertTrue(sdk.handle(activity))
        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
        XCTAssertFalse(sdk.handle(NSUserActivity(activityType: "com.funnelsgrove.other")))
    }

    func testHandleIgnoresOtherActivityTypesEvenWithAURL() {
        let (sdk, _) = makeSDK(answers: [active])
        let activity = NSUserActivity(activityType: "com.funnelsgrove.other")
        activity.webpageURL = link

        XCTAssertFalse(sdk.handle(activity))
        XCTAssertNil(store.value)
    }

    func testTheUserSurvivesANewInstance() {
        store.value = LinkedUser(userId: "u_saved", email: "saved@example.com")
        let (sdk, _) = makeSDK(answers: [active])

        XCTAssertEqual(sdk.userId, "u_saved")
        XCTAssertEqual(sdk.email, "saved@example.com")
    }

    func testTheUserIsReadAgainAfterAnEmptyRead() {
        let (sdk, _) = makeSDK(answers: [active])
        XCTAssertNil(sdk.userId)

        store.value = LinkedUser(userId: "u_later")

        XCTAssertEqual(sdk.userId, "u_later")
    }

    // MARK: - Subscription

    func testCheckWithoutAUserSkipsTheNetwork() async throws {
        let (sdk, fake) = makeSDK(answers: [active])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil))
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, [])
    }

    func testCheckReportsALiveSubscriptionWithoutCachingIt() async throws {
        store.value = LinkedUser(userId: "u_1")
        // The subscription ends between the two checks: a cached answer would still say active.
        let (sdk, fake) = makeSDK(answers: [active, inactive])

        let first = try await sdk.checkSubscription()
        let second = try await sdk.checkSubscription()

        XCTAssertEqual(first, SubscriptionStatus(isActive: true, isTest: false, isKnownUser: true, userId: "u_1"))
        XCTAssertEqual(second, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: true, userId: "u_1"))
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_1", "u_1"])
    }

    func testCheckRejectsTestSubscriptionsByDefault() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, _) = makeSDK(answers: [activeTest])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: true, isKnownUser: true, userId: "u_1"))
    }

    func testCheckAcceptsTestSubscriptionsWhenConfigured() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, _) = makeSDK(answers: [activeTest], acceptTestSubscriptions: true)

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: true, isTest: true, isKnownUser: true, userId: "u_1"))
    }

    func testCheckKeepsTheUserWhenFunnelsGroveDoesNotKnowIt() async throws {
        store.value = LinkedUser(userId: "u_1", email: "buyer@example.com")
        let (sdk, _) = makeSDK(answers: [unknown])

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: "u_1"))
        XCTAssertEqual(store.value, LinkedUser(userId: "u_1", email: "buyer@example.com"))
    }

    func testCheckPollsAfterAFreshLinkUntilActive() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive, inactive, active])
        sdk.handle(link)

        let status = try await sdk.checkSubscription()

        XCTAssertTrue(status.isActive)
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 3)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1, 2])
    }

    func testCheckStopsPollingAfterAllDelays() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)

        let status = try await sdk.checkSubscription()

        XCTAssertFalse(status.isActive)
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 5)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, [1, 2, 4, 8])
    }

    func testCheckDoesNotPollForAUserFromAnEarlierLaunch() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [inactive])

        _ = try await sdk.checkSubscription()

        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 1)
    }

    func testFreshLinkWindowIsTwoMinutes() async throws {
        for (age, expectedCalls) in [(119.0, 5), (120.0, 1)] {
            store = FakeUserStore()
            let (sdk, fake) = makeSDK(answers: [inactive])
            sdk.handle(link)
            clock.now += age

            _ = try await sdk.checkSubscription()

            let calls = await fake.verifiedUserIds
            XCTAssertEqual(calls.count, expectedCalls, "link age \(age) s")
        }
    }

    func testCheckPassesFunnelsGroveErrorsThrough() async {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])
        await fake.failVerification(with: .server(statusCode: 500))

        do {
            _ = try await sdk.checkSubscription()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FunnelsGroveError, .server(statusCode: 500))
        }
    }

    func testCheckReportsCancellationWhilePolling() async {
        // Task.sleep throws CancellationError when the calling task is cancelled.
        let (sdk, fake) = makeSDK(answers: [inactive], sleep: { _ in throw CancellationError() })
        sdk.handle(link)

        do {
            _ = try await sdk.checkSubscription()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls.count, 1)
    }

    func testCheckAnswersForALinkThatArrivedDuringTheRequest() async throws {
        store.value = LinkedUser(userId: "u_old")
        let (sdk, fake) = makeSDK(answers: [active])
        let newLink = URL(string: "fgdemo://open?user_id=u_new")!
        await fake.duringNextVerify { await MainActor.run { _ = sdk.handle(newLink) } }

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status.userId, "u_new")
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_old", "u_new"])
    }

    func testCheckReportsNoUserAfterAResetDuringTheRequest() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])
        await fake.duringNextVerify { await MainActor.run { sdk.reset() } }

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status, SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil))
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_1"])
    }

    func testCheckStopsPollingTheOldUserWhenANewLinkArrives() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)
        let newLink = URL(string: "fgdemo://open?user_id=u_2")!
        await fake.duringNextVerify { await MainActor.run { _ = sdk.handle(newLink) } }

        let status = try await sdk.checkSubscription()

        XCTAssertEqual(status.userId, "u_2")
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_1"] + Array(repeating: "u_2", count: 5))
    }

    // MARK: - Login

    func testTrackLoginWithoutAUserSkipsTheNetwork() async throws {
        let (sdk, fake) = makeSDK(answers: [active])

        let tracked = try await sdk.trackLogin()

        XCTAssertFalse(tracked)
        let calls = await fake.trackedUserIds
        XCTAssertEqual(calls, [])
    }

    func testTrackLoginRecordsTheStoredUser() async throws {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])

        let tracked = try await sdk.trackLogin()

        XCTAssertTrue(tracked)
        let calls = await fake.trackedUserIds
        XCTAssertEqual(calls, ["u_1"])
    }

    func testTrackLoginRecordsTheUserOfTheLatestLink() async throws {
        store.value = LinkedUser(userId: "u_old")
        let (sdk, fake) = makeSDK(answers: [active])
        sdk.handle(link)

        try await sdk.trackLogin()

        let calls = await fake.trackedUserIds
        XCTAssertEqual(calls, ["u_1"])
    }

    func testTrackLoginPassesErrorsThrough() async {
        store.value = LinkedUser(userId: "u_1")
        let (sdk, fake) = makeSDK(answers: [active])
        await fake.failTracking(with: .unknownUser)

        do {
            try await sdk.trackLogin()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FunnelsGroveError, .unknownUser)
        }
    }

    // MARK: - Reset

    func testResetForgetsTheUserAndEmail() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)

        sdk.reset()
        let status = try await sdk.checkSubscription()
        let tracked = try await sdk.trackLogin()

        XCTAssertNil(store.value)
        XCTAssertNil(sdk.userId)
        XCTAssertNil(sdk.email)
        XCTAssertNil(status.userId)
        XCTAssertFalse(tracked)
        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, [])
    }

    func testResetAlsoForgetsWhenTheLinkArrived() async throws {
        let (sdk, fake) = makeSDK(answers: [inactive])
        sdk.handle(link)
        sdk.reset()
        store.value = LinkedUser(userId: "u_synced")

        _ = try await sdk.checkSubscription()

        let calls = await fake.verifiedUserIds
        XCTAssertEqual(calls, ["u_synced"])
    }

    // MARK: - Configuration

    func testAcceptsAPublishableKey() {
        XCTAssertNil(FunnelsGrove.publishableKeyProblem("sdk_pub_" + String(repeating: "a", count: 48)))
        // Not tied to today's format: a new kind of publishable key must not stop apps.
        XCTAssertNil(FunnelsGrove.publishableKeyProblem("pk_future_format"))
    }

    func testRefusesAnEmptyOrSpacedKey() {
        for key in ["", " sdk_pub_1", "sdk_pub_1\n", "sdk pub"] {
            XCTAssertEqual(
                FunnelsGrove.publishableKeyProblem(key),
                "publishableKey must be the SDK publishable key of your FunnelsGrove project, without spaces",
                key
            )
        }
    }

    func testRefusesSecretKeys() {
        for key in ["sdk_sec_123", "fg_key_123"] {
            XCTAssertEqual(
                FunnelsGrove.publishableKeyProblem(key),
                "publishableKey is a secret FunnelsGrove key: never ship it in an app, use the SDK publishable key",
                key
            )
        }
    }
}
```

- [ ] **Step 3: Убедиться, что тест падает**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test
```

Ожидается: компиляция падает с `error: cannot find 'SubscriptionStatus' in scope` и `cannot find 'FunnelsGrove' in scope`.

- [ ] **Step 4: Написать `Sources/FunnelsGroveSDK/SubscriptionStatus.swift`**

```swift
import Foundation

/// The result of `FunnelsGrove.checkSubscription()`.
public struct SubscriptionStatus: Sendable, Equatable {
    /// FunnelsGrove reports an active subscription, and it is either live or test subscriptions are accepted.
    public let isActive: Bool
    /// The subscription was bought in Stripe test mode.
    public let isTest: Bool
    /// FunnelsGrove knows the stored user in this project.
    public let isKnownUser: Bool
    /// The stored FunnelsGrove user ID, or `nil` before the first link or after `reset()`.
    public let userId: String?

    public init(isActive: Bool, isTest: Bool, isKnownUser: Bool, userId: String?) {
        self.isActive = isActive
        self.isTest = isTest
        self.isKnownUser = isKnownUser
        self.userId = userId
    }
}
```

- [ ] **Step 5: Написать `Sources/FunnelsGroveSDK/FunnelsGrove.swift`**

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.funnelsgrove.sdk", category: "FunnelsGrove")

/// Receives FunnelsGrove links, checks the subscription of the linked user and records app logins.
@MainActor
public final class FunnelsGrove {
    struct Configuration {
        let acceptTestSubscriptions: Bool
    }

    /// Within this time after a link, an inactive answer is polled again: the payment webhook may lag.
    static let freshLinkWindow: TimeInterval = 120
    static let freshLinkRetryDelays: [TimeInterval] = [1, 2, 4, 8]

    private static var instance: FunnelsGrove?

    /// The instance created by `configure`. Using it before `configure` stops the app.
    public static var shared: FunnelsGrove {
        guard let instance else {
            // fatalError, not preconditionFailure: a Release build drops a precondition's message.
            fatalError("Call FunnelsGrove.configure(publishableKey:) before FunnelsGrove.shared")
        }
        return instance
    }

    /// Call once at launch, before any link can arrive. Stops the app when `publishableKey` is empty, contains
    /// whitespace, or starts with `sdk_sec_` or `fg_key_`.
    /// - Parameters:
    ///   - publishableKey: The SDK publishable key of your FunnelsGrove project. Never a secret key.
    ///   - acceptTestSubscriptions: Treat Stripe test-mode subscriptions as active. Use only in QA builds.
    ///   - apiBaseURL: The FunnelsGrove SDK API origin.
    public static func configure(
        publishableKey: String,
        acceptTestSubscriptions: Bool = false,
        apiBaseURL: URL = URL(string: "https://sdk-api.funnelsgrove.com")!
    ) {
        if let problem = publishableKeyProblem(publishableKey) {
            fatalError(problem)
        }
        instance = FunnelsGrove(
            configuration: Configuration(acceptTestSubscriptions: acceptTestSubscriptions),
            store: KeychainUserStore(),
            client: FunnelsGroveClient(baseURL: apiBaseURL, publishableKey: publishableKey)
        )
    }

    /// Why `configure` refuses `key`, or `nil`. The format of publishable keys is not checked, so that a new
    /// FunnelsGrove key format cannot stop apps.
    static func publishableKeyProblem(_ key: String) -> String? {
        if key.isEmpty || key.contains(where: \.isWhitespace) {
            return "publishableKey must be the SDK publishable key of your FunnelsGrove project, without spaces"
        }
        // Anyone who downloads the app can read a key shipped in it.
        if key.hasPrefix("sdk_sec_") || key.hasPrefix("fg_key_") {
            return "publishableKey is a secret FunnelsGrove key: never ship it in an app, use the SDK publishable key"
        }
        return nil
    }

    private let configuration: Configuration
    private let store: UserStore
    private let client: FunnelsGroveAPI
    private let now: () -> Date
    private let sleep: Sleep
    private var cachedUser: LinkedUser?
    private var linkedAt: Date?

    init(
        configuration: Configuration,
        store: UserStore,
        client: FunnelsGroveAPI,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping Sleep = sleepSeconds
    ) {
        self.configuration = configuration
        self.store = store
        self.client = client
        self.now = now
        self.sleep = sleep
    }

    /// The FunnelsGrove user ID from the latest link, if any. A plain property, not observable: read it again after
    /// `handle` returns `true` and after `reset()`.
    public var userId: String? { user?.userId }

    /// The email the links carried for the stored user, if any. Not verified: it is the address the buyer typed in
    /// the funnel, and anyone with the link has it. Fine for a sign-up form or a "signed in as" label, not as proof
    /// that the user owns the address.
    public var email: String? { user?.email }

    private var user: LinkedUser? {
        // An empty read, for example before the first unlock after a reboot, is not cached: the next access tries again.
        if cachedUser == nil { cachedUser = store.read() }
        return cachedUser
    }

    /// Stores the user ID and email from a FunnelsGrove link: any URL, whatever its scheme and host, with a valid
    /// `user_id`. Returns `false` for any other URL, which the app handles itself; route your own links first.
    /// A link without a usable `email` keeps the stored email of the same user and clears another user's.
    /// After `true`, call `checkSubscription()` again: a check that already finished saw the previous user.
    /// No login is recorded: call `trackLogin()` when your app signs the user in.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard let linked = LinkParser.user(from: url) else {
            return false
        }
        let previous = user
        // A link without an email keeps the address of the same user, but never pairs another user's address with
        // the new ID.
        let email = linked.email ?? (previous?.userId == linked.userId ? previous?.email : nil)
        keep(LinkedUser(userId: linked.userId, email: email))
        linkedAt = now()
        return true
    }

    /// Handles a Universal Link delivered as a browsing-web user activity.
    @discardableResult
    public func handle(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL
        else {
            return false
        }
        return handle(url)
    }

    /// Asks FunnelsGrove whether the stored user has an active subscription. The answer is not cached. Without a
    /// stored user it answers `isActive: false` and `userId: nil` without a network call.
    ///
    /// Within 2 minutes of a link an inactive answer is asked again after waits of 1, 2, 4 and 8 seconds, because the
    /// payment webhook may lag: show progress instead of blocking launch on it. Throws `FunnelsGroveError`, or
    /// `CancellationError` when the calling task is cancelled (for example a SwiftUI `.task` whose view went away),
    /// which is no result rather than a failure. If a link or `reset()` arrives meanwhile, the answer is for the
    /// current user.
    public func checkSubscription() async throws -> SubscriptionStatus {
        while true {
            guard let checked = userId else {
                return SubscriptionStatus(isActive: false, isTest: false, isKnownUser: false, userId: nil)
            }
            var response = try await client.verifySubscription(userId: checked)
            if !response.active, isFreshLink {
                for delay in Self.freshLinkRetryDelays {
                    try await sleep(delay)
                    guard userId == checked else { break }
                    response = try await client.verifySubscription(userId: checked)
                    if response.active { break }
                }
            }
            // A link or reset() that arrived while waiting made this answer stale: ask again for the current user.
            guard userId == checked else { continue }
            return SubscriptionStatus(
                isActive: response.active && (!response.test || configuration.acceptTestSubscriptions),
                isTest: response.test,
                isKnownUser: response.user != nil,
                userId: checked
            )
        }
    }

    /// Records "Logged into app" in FunnelsGrove for the stored user. Call it when your app signs the user in or up;
    /// in an app without a sign-in of its own, after `handle` returns `true`; and again after `handle` returns `true`
    /// while the user is signed in. A repeated call for the same user records nothing new.
    ///
    /// Returns `false` without a network call when no user is stored, and `true` once FunnelsGrove has the login.
    /// The login goes to the user stored when the call starts. Throws `FunnelsGroveError.unknownUser` when
    /// FunnelsGrove has no such user in the project, another `FunnelsGroveError`, or `CancellationError`.
    @discardableResult
    public func trackLogin() async throws -> Bool {
        guard let userId else {
            return false
        }
        try await client.trackLogin(userId: userId)
        logger.info("Recorded the login of FunnelsGrove user \(userId, privacy: .private)")
        return true
    }

    /// Forgets the stored user and email. iCloud Keychain removes them from the user's other devices too, where the
    /// app forgets the user from its next launch.
    public func reset() {
        store.delete()
        cachedUser = nil
        linkedAt = nil
    }

    /// Stores the user, kept in memory when the keychain fails.
    private func keep(_ user: LinkedUser) {
        do {
            try store.save(user)
        } catch let error as KeychainError {
            logger.error("Keeping the user failed: \(error.description, privacy: .public)")
        } catch {
            // Only a keychain status is known to carry no user data.
            logger.error("Keeping the user failed: \(String(describing: error), privacy: .private)")
        }
        cachedUser = user
        logger.info("Linked FunnelsGrove user \(user.userId, privacy: .private)")
    }

    private var isFreshLink: Bool {
        guard let linkedAt else { return false }
        return now().timeIntervalSince(linkedAt) < Self.freshLinkWindow
    }
}
```

- [ ] **Step 6: Убедиться, что тесты проходят на macOS**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk && swift test 2>&1 | grep -E "warning:|error:|Executed 65"
```

Ожидается: `Executed 65 tests, with 0 failures` (XCTest печатает эту строку дважды: для бандла и для «All tests»), без `warning:` и `error:`.

- [ ] **Step 7: Убедиться, что тесты проходят на iOS-симуляторе**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
DEVICE_ID=$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}')
: "${DEVICE_ID:?no available iPhone simulator}"
xcodebuild test -scheme FunnelsGroveSDK -destination "platform=iOS Simulator,id=$DEVICE_ID" 2>&1 | grep -E "error:|Executed 65|TEST (SUCCEEDED|FAILED)"
```

Ожидается: `Executed 65 tests, with 0 failures` и `** TEST SUCCEEDED **`. Строка `appintentsmetadataprocessor … warning: Metadata extraction skipped` — шум `xcodebuild`, не от пакета.

- [ ] **Step 8: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add Sources/FunnelsGroveSDK/SubscriptionStatus.swift Sources/FunnelsGroveSDK/FunnelsGrove.swift Tests/FunnelsGroveSDKTests/Fakes.swift Tests/FunnelsGroveSDKTests/FunnelsGroveTests.swift
git commit -m "feat: add the FunnelsGrove facade for links, subscription checks and app logins" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: README

**Files:**
- Create: `README.md`

README пишется для клиентов FG, на английском. Дизайн и риски в нём не пересказываются, кроме того, что нужно для безопасной интеграции. Примеры кода из него компилируются: SwiftUI-пример и методы `SceneDelegate` проверены в демо-проекте 2 ноября.

- [ ] **Step 1: Написать `README.md`**

````markdown
# FunnelsGroveSDK

Links a FunnelsGrove web purchase to your iOS app. After checkout, the funnel's "Open app now" button and the purchase
email open your app with a link that carries the buyer's FunnelsGrove user ID and email, for example
`myapp://open?user_id=u_…&email=…`. The SDK keeps them in the keychain, asks FunnelsGrove whether the user's
subscription is active, and records "Logged into app" in FunnelsGrove when your app says the user signed in.

The link works like a bearer token: whoever opens it in your app gets its user's subscription, and the link carries
the buyer's email. A forwarded link shares the access, so don't treat `isActive` as proof that the person in the app
paid. Don't log the link, the user ID or the email, or send them to analytics, attribution or support tools.

## How a buyer reaches the app

- The buyer taps "Open app now" on the funnel's success page, or the link in the purchase email. If the app is
  installed, iOS opens it with the link.
- If the app is not installed, the link cannot open it. A custom-scheme link fails in the browser; a Web link opens
  its page on your domain, so make that page send the buyer to the App Store. The buyer installs the app and taps
  "Open app now" again: there is no deferred deep link.
- The funnel also opens the link once by itself. iOS often does not open the app for that, so the purchase is linked
  by a later tap.
- In-app browsers such as TikTok's or Instagram's often don't open the app at all.

## Requirements

- iOS 15+, Xcode 16+.
- The SDK publishable key of your FunnelsGrove project. Never put a secret key (`sdk_sec_…`) or an organization API
  key (`fg_key_…`) in an app: anyone who downloads it can read the key, so `configure` stops the app if you pass one,
  or an empty key.
- A FunnelsGrove project whose funnel links to your app, see below.

## Set up your FunnelsGrove project

In the project settings, point these fields at your app, then publish the funnel. Set both if you can, at least one:

- **App Store deeplink**: a link with your app's own scheme, for example `myapp://open`. On iOS, "Open app now"
  uses it first.
- **Web link**: a Universal Link on your domain, for example `https://go.myapp.com/open`. The purchase email uses it
  first.

With only an App Store deeplink, the purchase email carries your custom scheme, which many email apps don't open: a
buyer who installs the app after checkout may then have no working link to it.

FunnelsGrove adds `user_id`, `email` and the first-touch campaign parameters to both. Check that "Open app now" in the
published funnel opens your app and that the link carries `user_id`.

## Install

Add the package `https://github.com/The-Solid-Grove/funnelsgrove-ios-sdk.git` and link the `FunnelsGroveSDK`
product. The repository is private: ask the FunnelsGrove team for access, and add the GitHub account that has it in
Xcode → Settings → Accounts and on your CI. There is no release tag yet: add the package by branch `main`, then
pin a commit (Dependency Rule → Commit) before you release.

## Links into the app

The SDK accepts any link with a `user_id`, whatever its scheme and host. Which links open your app is up to you:

- **Custom scheme.** Add a URL type with your scheme: Target → Info → URL Types, or `CFBundleURLTypes`.
- **Universal Links.** Add the Associated Domains capability with `applinks:<your domain>` and serve an
  `apple-app-site-association` file at `https://<your domain>/.well-known/apple-app-site-association` that lists
  `<Team ID>.<bundle ID>` for the Web link's path, for example `/open`. Apple's CDN can take up to 24 hours to pick up
  a new file, so publish it before you ship the build.
  - Debug builds can use `applinks:<your domain>?mode=developer`. The device then reads the file from your server
    directly. This needs Developer Mode (Settings → Privacy & Security) and Settings → Developer → Associated
    Domains Development.
  - Release and TestFlight builds must use the plain `applinks:<your domain>`. One entitlements file can serve both:
    write `applinks:<your domain>$(APPLINKS_MODE)` and set the build setting `APPLINKS_MODE` to `?mode=developer` in
    Debug only. Check the entitlement of the archived app before you upload it.
  - Serve a page at the Web link's path, for example a redirect to your App Store page: buyers without the app, in
    in-app browsers or on another device land there. Its URL carries the user ID and the email, so keep analytics
    scripts off that page and the query out of your server and CDN logs.
  - Use a domain other than the funnel's: iOS opens a Universal Link tapped on a page of the same domain in the
    browser, not in the app.

If your app has its own links with a `user_id` parameter, handle them before the SDK: it takes any link with a valid
`user_id` for a FunnelsGrove link.

If `handle` returns `true`, don't pass the URL as is to attribution or deep-link SDKs such as AppsFlyer, Adjust or
Branch: they usually send the URLs they get to their servers, user ID and email included. Remove `user_id` and `email`
first if you need the campaign parameters there.

## Use

`FunnelsGrove` is `@MainActor`: call it from the main actor. SwiftUI views and the app and scene delegates already
are.

### SwiftUI

```swift
import FunnelsGroveSDK
import SwiftUI

@main
struct MyApp: App {
    // false until the first check answers: while it runs, show progress rather than the paywall (keep your own
    // checking state).
    @State private var hasAccess = false

    init() {
        FunnelsGrove.configure(publishableKey: "<FunnelsGrove SDK publishable key>")
    }

    var body: some Scene {
        WindowGroup {
            RootView(hasAccess: hasAccess)
                .task { await refreshAccess() }
                // A custom-scheme link arrives in onOpenURL. SwiftUI routes a Universal Link to one of these two
                // handlers; register both.
                .onOpenURL { url in
                    // Route your own links before this call: the SDK takes any link with a user_id.
                    if FunnelsGrove.shared.handle(url) { linked() }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Your own Universal Links first, here too.
                    if FunnelsGrove.shared.handle(activity) { linked() }
                }
        }
    }

    @MainActor
    private func linked() {
        // A check that already finished saw the previous user: check again.
        Task { await refreshAccess() }
        // This app has no sign-in of its own, so the link is the login. With your own sign-in, call trackLogin()
        // here only while the user is signed in: see "App login".
        Task { try? await FunnelsGrove.shared.trackLogin() }
    }

    @MainActor
    private func refreshAccess() async {
        do {
            hasAccess = try await FunnelsGrove.shared.checkSubscription().isActive
        } catch is CancellationError {
            // The task was cancelled, for example the view went away: keep the current state.
        } catch {
            // FunnelsGroveError: see "Errors" below.
        }
    }
}
```

Which of the two handlers receives a Universal Link depends on the SwiftUI version and on the other handlers in your
app, so the example registers both. If both ever fire for one link, the second `handle` stores the same user again
and FunnelsGrove records the login once, so nothing breaks. Check a cold and a warm start on a device.

### UIKit

```swift
// AppDelegate.application(_:didFinishLaunchingWithOptions:)
FunnelsGrove.configure(publishableKey: "<FunnelsGrove SDK publishable key>")

// SceneDelegate. Route your own links before each handle call.
private var hasAccess = false   // drive your UI from it

func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    // A cold start may come from a link; check access either way.
    let fromURL = connectionOptions.urlContexts.map { FunnelsGrove.shared.handle($0.url) }.contains(true)
    let fromActivity = connectionOptions.userActivities.map { FunnelsGrove.shared.handle($0) }.contains(true)
    if fromURL || fromActivity { linked() } else { refreshAccess() }
}

func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    // A custom-scheme link while the app runs.
    if URLContexts.map({ FunnelsGrove.shared.handle($0.url) }).contains(true) { linked() }
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    // A Universal Link while the app runs.
    if FunnelsGrove.shared.handle(userActivity) { linked() }
}

private func linked() {
    // A check that already finished saw the previous user: check again.
    refreshAccess()
    // This app has no sign-in of its own, so the link is the login. With your own sign-in, call trackLogin()
    // here only while the user is signed in: see "App login".
    Task { try? await FunnelsGrove.shared.trackLogin() }
}

private func refreshAccess() {
    Task {
        do {
            hasAccess = try await FunnelsGrove.shared.checkSubscription().isActive
        } catch is CancellationError {
            // The task was cancelled: keep the current state.
        } catch {
            // FunnelsGroveError: see "Errors" below.
        }
    }
}
```

Without scenes, handle the same links in `application(_:open:options:)` and
`application(_:continue:restorationHandler:)`; iOS calls them on a cold start too.

`FunnelsGrove.shared` stops the app if `configure` has not run, so configure it in
`application(_:didFinishLaunchingWithOptions:)`.

Check access at launch, when the app returns to the foreground, after every `handle` that returns `true`, and at
every paid-content boundary.

### App login

`trackLogin()` records "Logged into app" for the stored user in FunnelsGrove. The SDK never calls it by itself. Call
it:

- when the user signs in or up in your app (a session your app restores at launch needs no call);
- in an app without a sign-in of its own, after `handle` returns `true`, as in the examples above;
- again after `handle` returns `true` while the user is signed in: the link may be another FunnelsGrove user's.

```swift
// After your own sign-in succeeds.
Task { try? await FunnelsGrove.shared.trackLogin() }
```

It returns `false` without a network call when no user is stored, so you can call it on every sign-in, and `true` once
FunnelsGrove has the login. A repeated call for the same user records nothing new. The login goes to the user stored
when the call starts.

The SDK doesn't retry later. After `.network` or `.server`, call `trackLogin()` again at the next chance, for example
at the next launch: the first call may have reached FunnelsGrove, and a repeat records nothing new. `.unknownUser` and
`.configuration` won't succeed on a retry.

### Email from the link

`FunnelsGrove.shared.email` is the address the buyer bought with, when a link carried it. Use it to prefill a sign-up
form or to show who is signed in. It is not verified: it is what the buyer typed in the funnel, anyone with the link
has it, and anyone can make a link with any address. Never sign the user in to an existing account, or merge
accounts, by this email without verifying the address first. A newer link without an email keeps the address of the
same user and clears it for another user.

## Behaviour

- **`handle(_:)`** accepts any URL with a `user_id` query parameter (non-empty, at most 256 UTF-8 bytes, no
  whitespace or control characters; the first one counts). It stores the ID together with the link's `email`, and a
  newer link replaces them. It returns `true` and records no login. Any other URL returns `false` and is left to the
  app. `userId` and `email` read what is stored. They are plain properties, not observable: copy them into your own
  state after `handle` returns `true` and after `reset()`.
- **`handle(_ userActivity:)`** uses the activity's `webpageURL` when its type is `NSUserActivityTypeBrowsingWeb`,
  and returns `false` otherwise.
- **`checkSubscription()`**:
  - without a stored ID returns at once, without a network call;
  - within 2 minutes of a link asks again after waits of 1, 2, 4 and 8 s (15 s of waiting, plus the requests, each
    with a 10 s timeout) while FunnelsGrove still says inactive, because the payment webhook may lag: show progress
    instead of blocking launch on it;
  - retries a 503 once when `Retry-After` is 10 s or less;
  - answers `isKnownUser: false` when FunnelsGrove does not know the stored ID in your project, for example after a
    link from another project's funnel; the ID stays stored. If every user answers `isKnownUser: false`, the
    publishable key is probably from another project than the funnel;
  - never caches the answer;
  - if a link or `reset()` changes the stored user while it waits, answers for the current user;
  - throws `CancellationError` when its task is cancelled (for example a SwiftUI `.task` whose view went away):
    treat that as no result, not as a failure.
- **`trackLogin()`** returns `false` without a stored ID and `true` once FunnelsGrove has the login. It retries a 503
  once like `checkSubscription()`. It throws `.unknownUser` when FunnelsGrove does not know the user in your project,
  another `FunnelsGroveError` (see Errors), or `CancellationError` when its task is cancelled.
- **Test subscriptions.** `isActive` is `false` for Stripe test-mode subscriptions unless you pass
  `acceptTestSubscriptions: true` to `configure`. `isTest` is reported either way. Whoever reaches a test-mode funnel
  can pay with Stripe's test card, so a build that accepts test subscriptions gives paid access away. Pass a flag that
  only Debug or a separate QA build configuration sets, for example `acceptTestSubscriptions: isQABuild` with
  `isQABuild` set under `#if DEBUG || QA`, where `QA` is in the Active Compilation Conditions of your QA configuration
  only. Never set it in the configuration you archive for the App Store: its TestFlight build is the binary you then
  release. For App Review, give the reviewers the link of a live-mode user with an active subscription.
- **Errors.** Both calls throw `FunnelsGroveError`, or `CancellationError`, which is no result rather than a failure:
  - `.configuration`: FunnelsGrove answered 400 or 401, usually a wrong `publishableKey`. From `trackLogin()`, a 400
    can also mean that the same user ID exists in several funnels of the project: FunnelsGrove then needs a funnel ID
    that the link does not carry, and this version cannot record that user's login. Don't retry.
  - `.unknownUser`, from `trackLogin()` only: FunnelsGrove has no such user in your project. Don't retry.
  - `.server(statusCode:)` and `.network(URLError)`: try again later.

  Handle the cases you act on and end with `default`: later versions may add cases. The SDK does not cache the
  subscription answer, so offline every check for a stored user fails with `.network`: decide whether your app keeps
  the access it last saw or locks paid content. If you keep the last answer, store it with `status.userId` and use it
  only while `userId` is the same.
- **Storage.** The ID and the email live in one keychain item with iCloud Keychain sync. It outlives app deletion in
  practice; Apple does not guarantee that. A reinstall or a new device of the same Apple ID can therefore show the
  previous user's access until a new link arrives. Call `reset()` on sign-out. iCloud Keychain then removes the user
  from the user's other devices too, where the app forgets it from its next launch. Access returns only with a new
  link, for example the one in the purchase email.
- **Network.** The SDK sends only the stored user ID, with your publishable key, to `sdk-api.funnelsgrove.com`. The
  email leaves the device only through iCloud Keychain.

## Testing a link

Tap a Universal Link in Notes or Messages: typed into Safari's address bar, it opens the web page instead of the app.
If a Universal Link that worked starts opening Safari, the domain was opened in Safari once: long-press the link and
choose to open it in the app. On the simulator, `xcrun simctl openurl booted 'myapp://open?user_id=u_test'` opens a
custom-scheme link after you tap Open in the prompt. A made-up `user_id` answers `isKnownUser: false`, after about
15 s of polling, because the link is fresh.

## Demo app

```bash
brew install xcodegen
cd Examples/FunnelsGroveDemo
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set DEVELOPMENT_TEAM and FG_PUBLISHABLE_KEY
xcodegen generate
open FunnelsGroveDemo.xcodeproj
```

The demo needs iOS 17. On a device, also set a `PRODUCT_BUNDLE_IDENTIFIER` that your team can sign. The demo opens
`fgdemo://` links: set the App Store deeplink of your test FunnelsGrove project to `fgdemo://open`, or paste a link
into the demo. Universal Links are optional: see `Config/Local.xcconfig.example`. Track login records a real login in
that FunnelsGrove project. The demo accepts test subscriptions: don't copy its `configure` call.

## Tests

```bash
swift test
DEVICE_ID=$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}')
: "${DEVICE_ID:?no available iPhone simulator}"
xcodebuild test -scheme FunnelsGroveSDK -destination "platform=iOS Simulator,id=$DEVICE_ID"
```

The keychain is not unit-tested: an unsigned test bundle gets `errSecMissingEntitlement`. Check it in the demo app
(relaunch, then delete and reinstall).
````

- [ ] **Step 2: Проверить, что README называет весь публичный API**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
for name in 'configure(publishableKey' 'FunnelsGrove.shared' 'handle(' '`userId`' '`email`' 'checkSubscription()' 'trackLogin()' 'reset()' 'acceptTestSubscriptions' 'isKnownUser' 'unknownUser'; do grep -qF "$name" README.md && echo "ok   $name" || echo "MISS $name"; done
```

Ожидается: все 11 строк начинаются с `ok`.

- [ ] **Step 3: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add README.md
git commit -m "docs: explain integration, the FunnelsGrove project setup, behaviour, demo and tests" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Демо-приложение

**Files:**
- Create: `Examples/FunnelsGroveDemo/project.yml`
- Create: `Examples/FunnelsGroveDemo/Config/Shared.xcconfig`
- Create: `Examples/FunnelsGroveDemo/Config/Debug.xcconfig`
- Create: `Examples/FunnelsGroveDemo/Config/Release.xcconfig`
- Create: `Examples/FunnelsGroveDemo/Config/Local.xcconfig.example`
- Create: `Examples/FunnelsGroveDemo/Config/UniversalLinks.entitlements`
- Create: `Examples/FunnelsGroveDemo/FunnelsGroveDemo/FunnelsGroveDemoApp.swift`
- Create: `Examples/FunnelsGroveDemo/FunnelsGroveDemo/DemoConfig.swift`
- Create: `Examples/FunnelsGroveDemo/FunnelsGroveDemo/ContentView.swift`

XcodeGen генерирует `FunnelsGroveDemo.xcodeproj` и `Support/Info.plist`, оба в `.gitignore`. Publishable key попадает в Info.plist из xcconfig. Своя схема `fgdemo` прописана в `CFBundleURLTypes`, поэтому ссылку можно проверить без AASA.

Universal Links выключены по умолчанию: `CODE_SIGN_ENTITLEMENTS` пустой, и сборка подписывается любой командой, в том числе бесплатной. Владелец включает их в `Local.xcconfig`, задав `FG_DEMO_LINK_HOST` и `CODE_SIGN_ENTITLEMENTS = Config/UniversalLinks.entitlements`. Xcode подставляет build settings в entitlements при подписи, а `?mode=developer` стоит только в Debug.

- [ ] **Step 1: Проверить XcodeGen**

```bash
xcodegen --version || brew install xcodegen
```

Ожидается: `Version: 2.46.0` или новее.

- [ ] **Step 2: Написать `Examples/FunnelsGroveDemo/project.yml`**

```yaml
name: FunnelsGroveDemo
options:
  deploymentTarget:
    iOS: "17.0"
packages:
  FunnelsGroveSDK:
    path: ../..
targets:
  FunnelsGroveDemo:
    type: application
    platform: iOS
    sources:
      - FunnelsGroveDemo
    configFiles:
      Debug: Config/Debug.xcconfig
      Release: Config/Release.xcconfig
    dependencies:
      - package: FunnelsGroveSDK
    info:
      path: Support/Info.plist
      properties:
        CFBundleDisplayName: FunnelsGrove Demo
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        FGPublishableKey: "$(FG_PUBLISHABLE_KEY)"
        CFBundleURLTypes:
          - CFBundleURLName: "$(PRODUCT_BUNDLE_IDENTIFIER)"
            CFBundleURLSchemes:
              - fgdemo
    settings:
      base:
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
    scheme: {}
```

- [ ] **Step 3: Написать xcconfig-файлы и entitlements**

`Examples/FunnelsGroveDemo/Config/Shared.xcconfig`:

```
// Shared demo settings. Put your own values in Local.xcconfig (git-ignored).
PRODUCT_BUNDLE_IDENTIFIER = com.funnelsgrove.demo
FG_PUBLISHABLE_KEY =
DEVELOPMENT_TEAM =
// Universal Links are off unless Local.xcconfig sets both (see Local.xcconfig.example).
FG_DEMO_LINK_HOST =
CODE_SIGN_ENTITLEMENTS =

#include? "Local.xcconfig"
```

`Examples/FunnelsGroveDemo/Config/Debug.xcconfig`:

```
#include "Shared.xcconfig"

// With Universal Links on: read the AASA file from the server, bypassing Apple's CDN. Needs Developer Mode and
// Settings > Developer > Associated Domains Development on the device.
FG_DEMO_LINK_MODE = ?mode=developer
```

`Examples/FunnelsGroveDemo/Config/Release.xcconfig`:

```
#include "Shared.xcconfig"

FG_DEMO_LINK_MODE =
```

`Examples/FunnelsGroveDemo/Config/Local.xcconfig.example`:

```
// Copy to Local.xcconfig (git-ignored) and fill in.
DEVELOPMENT_TEAM = ABCDE12345
FG_PUBLISHABLE_KEY = your-funnelsgrove-project-sdk-publishable-key
// On a device, use a bundle ID that your team can sign:
// PRODUCT_BUNDLE_IDENTIFIER = com.example.funnelsgrove-demo

// Optional Universal Links: a domain you control whose apple-app-site-association file lists
// <Team ID>.<bundle ID> for the path /open. Needs a paid developer team: personal teams cannot sign
// Associated Domains. Uncomment both lines.
// FG_DEMO_LINK_HOST = go.example.com
// CODE_SIGN_ENTITLEMENTS = Config/UniversalLinks.entitlements
```

`Examples/FunnelsGroveDemo/Config/UniversalLinks.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:$(FG_DEMO_LINK_HOST)$(FG_DEMO_LINK_MODE)</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 4: Написать `Examples/FunnelsGroveDemo/FunnelsGroveDemo/FunnelsGroveDemoApp.swift`**

```swift
import FunnelsGroveSDK
import SwiftUI

@main
struct FunnelsGroveDemoApp: App {
    init() {
        // QA only: Stripe test-mode purchases show as active, and anyone can make one with a test card. A real app
        // passes a flag that only Debug or a QA configuration sets, never the one it archives (README, "Test
        // subscriptions").
        FunnelsGrove.configure(publishableKey: DemoConfig.publishableKey, acceptTestSubscriptions: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 5: Написать `Examples/FunnelsGroveDemo/FunnelsGroveDemo/DemoConfig.swift`**

```swift
import Foundation

/// Values come from Config/Local.xcconfig through Info.plist.
enum DemoConfig {
    static let publishableKey = value(for: "FGPublishableKey")

    private static func value(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            // fatalError, not preconditionFailure: a Release build drops a precondition's message.
            fatalError("\(key) is empty: fill in Config/Local.xcconfig")
        }
        return value
    }
}
```

- [ ] **Step 6: Написать `Examples/FunnelsGroveDemo/FunnelsGroveDemo/ContentView.swift`**

Экран: сохранённые `user_id` и email, статус и Check, Track login с результатом, полученные ссылки с обработчиком, поле для вставки ссылки и Reset. Демо не вызывает `trackLogin()` само после ссылки: в E2E вход проверяется отдельной кнопкой.

```swift
import FunnelsGroveSDK
import SwiftUI

struct ContentView: View {
    private static let loginHint = "Records Logged into app in FunnelsGrove for the stored user"
    private static let maxLoggedLinks = 10

    @State private var userId = FunnelsGrove.shared.userId
    @State private var email = FunnelsGrove.shared.email
    @State private var status = "Not checked"
    @State private var isChecking = false
    /// Counts checks, so that only the latest one shows its answer.
    @State private var checkGeneration = 0
    @State private var loginStatus = Self.loginHint
    @State private var isTracking = false
    @State private var pastedLink = ""
    // QA only: the links carry the user ID and email. A real app never shows, logs or stores them.
    @State private var linkLog: [String] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("FunnelsGrove user") {
                    Text(userId ?? "No link yet")
                        .textSelection(.enabled)
                    Text(email ?? "No email from the link")
                        .textSelection(.enabled)
                }
                Section("Subscription") {
                    Text(status)
                    Button(isChecking ? "Checking…" : "Check") {
                        Task { await check() }
                    }
                    .disabled(isChecking)
                }
                Section("App login") {
                    Text(loginStatus)
                        .font(.footnote)
                    Button(isTracking ? "Tracking…" : "Track login") {
                        isTracking = true
                        Task { await trackLogin() }
                    }
                    .disabled(isTracking)
                }
                Section("Last links received") {
                    Text(linkLog.isEmpty ? "None" : linkLog.joined(separator: "\n"))
                        .font(.footnote)
                        .textSelection(.enabled)
                }
                Section("Paste a link") {
                    TextField("Link", text: $pastedLink, prompt: Text(verbatim: "fgdemo://open?user_id=…&email=…"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(handlePastedLink)
                    Button("Handle link", action: handlePastedLink)
                }
                Section {
                    Button("Reset", role: .destructive) {
                        FunnelsGrove.shared.reset()
                        refreshUser()
                        // Drop the answer of a check still running.
                        checkGeneration += 1
                        isChecking = false
                        status = "Not checked"
                        loginStatus = Self.loginHint
                    }
                }
            }
            .navigationTitle("FunnelsGrove Demo")
        }
        // A custom scheme arrives in onOpenURL; SwiftUI routes a Universal Link to one of these two handlers.
        // "Last links received" shows which.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            log("onContinueUserActivity: \(activity.webpageURL?.absoluteString ?? "no URL")")
            // A real app routes its own links before handing the rest to the SDK.
            linked(FunnelsGrove.shared.handle(activity))
        }
        .onOpenURL { url in
            log("onOpenURL: \(url.absoluteString)")
            linked(FunnelsGrove.shared.handle(url))
        }
        .onChange(of: scenePhase) { _, phase in
            // iCloud Keychain may deliver a user in the background; the SDK reads it while it has none.
            guard phase == .active else { return }
            let isAnotherUser = FunnelsGrove.shared.userId != userId
            refreshUser()
            // The status on screen was checked for no user or for another one.
            if isAnotherUser {
                status = "Not checked"
                loginStatus = Self.loginHint
            }
        }
    }

    private func handlePastedLink() {
        let text = pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text) else {
            status = "Ignored: the pasted text is not a URL"
            return
        }
        log("Pasted: \(url.absoluteString)")
        linked(FunnelsGrove.shared.handle(url))
    }

    private func log(_ entry: String) {
        linkLog.append(entry)
        if linkLog.count > Self.maxLoggedLinks {
            linkLog.removeFirst(linkLog.count - Self.maxLoggedLinks)
        }
    }

    private func refreshUser() {
        userId = FunnelsGrove.shared.userId
        email = FunnelsGrove.shared.email
    }

    private func linked(_ handled: Bool) {
        guard handled else {
            status = "Ignored: no valid user_id in the link"
            return
        }
        refreshUser()
        // A check that already finished saw the previous user: check again.
        Task { await check() }
        // A real app calls trackLogin() here when it has no sign-in of its own, or while the user is signed in
        // (README, "App login"). The demo records the login with its own button, so that a test sees it apart
        // from the link.
    }

    /// Shows the answer of the latest check only: a link can start one while another runs.
    private func check() async {
        checkGeneration += 1
        let generation = checkGeneration
        isChecking = true
        status = "Checking…"
        let answer: String
        do {
            answer = describe(try await FunnelsGrove.shared.checkSubscription())
        } catch is CancellationError {
            answer = "Not checked"
        } catch {
            answer = "Error: \(error)"
        }
        guard generation == checkGeneration else { return }
        status = answer
        isChecking = false
    }

    private func describe(_ result: SubscriptionStatus) -> String {
        guard result.userId != nil else { return "No user" }
        guard result.isKnownUser else { return "Unknown to FunnelsGrove" }
        if result.isActive { return result.isTest ? "Active (test)" : "Active" }
        return result.isTest ? "Inactive (test)" : "Inactive"
    }

    private func trackLogin() async {
        defer { isTracking = false }
        loginStatus = "Tracking…"
        do {
            loginStatus = try await FunnelsGrove.shared.trackLogin() ? "Tracked" : "No user: open a link first"
        } catch FunnelsGroveError.unknownUser {
            loginStatus = "FunnelsGrove does not know this user in the project"
        } catch is CancellationError {
            loginStatus = Self.loginHint
        } catch {
            loginStatus = "Error: \(error)"
        }
    }
}
```

- [ ] **Step 7: Сгенерировать проект и собрать без подписи**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk/Examples/FunnelsGroveDemo
xcodegen generate
xcodebuild build -project FunnelsGroveDemo.xcodeproj -scheme FunnelsGroveDemo \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v appintents
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" Support/Info.plist
cd ../.. && git status --short --untracked-files=all
```

Ожидается:
- `Created project at …/FunnelsGroveDemo.xcodeproj`, затем `** BUILD SUCCEEDED **` без `warning:`;
- PlistBuddy печатает `fgdemo`;
- `git status --short --untracked-files=all` показывает только `Examples/FunnelsGroveDemo/project.yml`, файлы `Config/` и исходники (без `--untracked-files=all` git сворачивает новую папку в `?? Examples/`). Проект, `Support/` и `Local.xcconfig` в статусе не появляются.

- [ ] **Step 8: Проверить ссылку на симуляторе (без подписи и без владельца)**

Пробный ключ проходит проверку `configure`, а FG отвечает на него 401: так видно и разбор ссылки, и маппинг ошибки.

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk/Examples/FunnelsGroveDemo
DEVICE_ID=$(xcrun simctl list devices available | grep -m1 -E '^\s+iPhone' | grep -oE '[0-9A-F-]{36}')
xcodebuild build -project FunnelsGroveDemo.xcodeproj -scheme FunnelsGroveDemo -destination "id=$DEVICE_ID" \
  -derivedDataPath ../../.build/fgdemo-dd CODE_SIGNING_ALLOWED=NO FG_PUBLISHABLE_KEY=sdk_pub_dummy 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null; xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
xcrun simctl install "$DEVICE_ID" ../../.build/fgdemo-dd/Build/Products/Debug-iphonesimulator/FunnelsGroveDemo.app
xcrun simctl launch "$DEVICE_ID" com.funnelsgrove.demo
xcrun simctl openurl "$DEVICE_ID" "fgdemo://open?user_id=u_sim_check&email=buyer%2Bqa%40example.com&utm_source=fg"
```

Если iOS спросит «Open in "FunnelsGrove Demo"?», нажать Open в окне симулятора. Когда демо уже на экране, вопроса может не быть.

Ожидается:
- «FunnelsGrove user»: `u_sim_check` и `buyer+qa@example.com`;
- «Last links received»: `onOpenURL: fgdemo://open?user_id=u_sim_check&email=buyer%2Bqa%40example.com&utm_source=fg`;
- «Subscription»: `Error: configuration("FunnelsGrove answered 401: check publishableKey")`;
- после нажатия Track login в «App login» — та же ошибка: запрос дошёл до `track_login` в FG.

Неподписанная сборка не может писать в Keychain (в консоли — ошибка `com.funnelsgrove.sdk`, категория Keychain), поэтому SDK держит пользователя в памяти. Хранение проверяется на шаге 10.

Затем убрать за собой:

```bash
xcrun simctl uninstall "$DEVICE_ID" com.funnelsgrove.demo && xcrun simctl shutdown "$DEVICE_ID"
```

- [ ] **Step 9: Commit**

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git add Examples/FunnelsGroveDemo/project.yml Examples/FunnelsGroveDemo/Config Examples/FunnelsGroveDemo/FunnelsGroveDemo
git commit -m "feat: add the demo app for links, subscription checks and app logins" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10 (с владельцем): Проверить реальный Keychain на симуляторе**

Владелец заполняет `Config/Local.xcconfig`: Team ID и publishable key тестового FG-проекта.

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk/Examples/FunnelsGroveDemo
cp Config/Local.xcconfig.example Config/Local.xcconfig   # вписать DEVELOPMENT_TEAM и FG_PUBLISHABLE_KEY
xcodegen generate
open FunnelsGroveDemo.xcodeproj
```

В Xcode запустить схему `FunnelsGroveDemo` на iPhone-симуляторе и проверить по шагам:

1. Вставить `fgdemo://open?user_id=u_keychain_check&email=keychain%40example.com` и нажать Handle link. Сразу появятся `u_keychain_check` и `keychain@example.com`. Примерно через 15 секунд статус станет «Unknown to FunnelsGrove»: такого пользователя в FG нет, а SDK после свежей ссылки ещё опрашивает FG.
2. Нажать Track login: «FunnelsGrove does not know this user in the project».
3. Вставить `fgdemo://open?user_id=u_keychain_check` (без email) и нажать Handle link: email остался `keychain@example.com`.
4. Остановить приложение в Xcode и запустить снова: `u_keychain_check` и email на месте, значит запись прочиталась из Keychain.
5. Удалить приложение с симулятора (долгое нажатие на иконку → Remove App) и снова запустить из Xcode: оба значения на месте.
6. Вставить `fgdemo://open?user_id=u_other` и нажать Handle link: `u_other` и «No email from the link».
7. Нажать Reset и перезапустить: «No link yet» и «No email from the link».

Если после перезапуска виден «No link yet», сначала посмотреть в консоли Xcode ошибки подсистемы `com.funnelsgrove.sdk` (категория Keychain). Симулятор — самое слабое место для синхронизируемых записей Keychain; окончательная проверка — шаг 5 задачи 8 на устройстве.

---

### Task 8: E2E на устройстве (с владельцем)

**Files:** нет, только проверка.

Что должно быть готово:
- Тестовый FG-проект: в настройках App Store deeplink `fgdemo://open` (в env — `NEXT_PUBLIC_FUNNEL_IOS_DEEP_LINK`), воронка опубликована. Если кнопка «Open app now» не поменялась, воронку нужно переопубликовать.
- В `Config/Local.xcconfig` указаны Team ID и publishable key этого FG-проекта.
- iPhone в Developer Mode, подключён к Mac.
- Для проверок через `curl` ключ лежит в переменной окружения: `export FG_KEY=<publishable key тестового FG-проекта>`. В выводе команд ключ не печатается. `u_…` в командах — id покупателя из «Last links received».

- [ ] **Step 1: Поставить Debug-сборку на iPhone**

В Xcode выбрать подключённый iPhone и запустить схему `FunnelsGroveDemo`.

- [ ] **Step 2: Проверить схему**

В Safari на iPhone ввести в адресную строку `fgdemo://open?user_id=u_probe&email=probe%40example.com` и подтвердить «Open in "FunnelsGrove Demo"?».

Ожидается: открывается демо-приложение и показывает `u_probe` и `probe@example.com`, «Last links received» — `onOpenURL: …`. Проверить и холодный старт (приложение закрыто), и тёплый (приложение открыто). Затем Reset.

- [ ] **Step 3: Тестовая покупка**

В Safari на iPhone пройти тестовую воронку и оплатить тестовой картой Stripe `4242 4242 4242 4242` (любая будущая дата, любой CVC). Открывать воронку по тестовому URL (превью или стандартный домен FG): на собственном боевом домене FG проводит оплату в live-режиме, и тестовая карта не пройдёт.

На экране успеха FG один раз сам переходит по ссылке: Safari спросит, открыть ли FunnelsGrove Demo. Если вопрос пропущен, тапнуть «Open app now».

Ожидается: демо-приложение показывает `u_…` покупателя и email, с которым покупали. Пока идёт опрос, статус — «Checking…», через несколько секунд — «Active (test)».

Если статус другой, сначала спросить FG напрямую, взяв `u_…` из «Last links received»:

```bash
curl -sS -X POST https://sdk-api.funnelsgrove.com/sdk/public/users/verify_subscription \
  -H 'Content-Type: application/json' -H "X-SDK-Publishable-Key: $FG_KEY" -d '{"userId":"u_…"}'
```

Ожидается `{"active":true,"test":true,"user":{"user_id":"u_…"}}`. Если FG отвечает иначе, проблема в воронке или оплате, а не в SDK. Если вместо этого «Ignored: no valid user_id in the link», в «Last links received» виден полученный URL: проверить, что в нём есть `user_id`.

- [ ] **Step 4: Учёт входа**

Нажать Track login.

Ожидается: «Tracked». В FG у этого пользователя появляется «Logged into app». Повторный Track login снова даёт «Tracked», а второго события в FG нет. То же видно через API: повторный вызов отвечает `"newlyTracked":false`, потому что вход уже записан демо-приложением.

```bash
curl -sS -X POST https://sdk-api.funnelsgrove.com/sdk/public/users/track_login \
  -H 'Content-Type: application/json' -H "X-SDK-Publishable-Key: $FG_KEY" -d '{"userId":"u_…"}'
```

- [ ] **Step 5: Переустановка**

Удалить демо-приложение с iPhone и поставить заново из Xcode.

Ожидается: при запуске видны тот же `u_…` и email. Check показывает «Active (test)».

- [ ] **Step 6 (по желанию): Universal Link с чужого для SDK домена**

1. В дашборде appsilove (`https://dashboard.appsilove.co`) или по SQL из `appsilove/links/README.md` завести строку `fgdemo` в `link_apps`: Team ID владельца, bundle ID `com.funnelsgrove.demo`, любой существующий `app_store_id`. Если в `Local.xcconfig` задан свой `PRODUCT_BUNDLE_IDENTIFIER`, в строке нужен он. Associated Domains подписывает только платная команда разработчика, не personal team.
2. Проверить, что `https://fgdemo.links.appsilove.co/.well-known/apple-app-site-association` отдаёт `<Team ID>.<bundle ID>`: `com.funnelsgrove.demo` или свой bundle ID из `Local.xcconfig`.
3. В `Config/Local.xcconfig` раскомментировать обе строки Universal Links, задать `FG_DEMO_LINK_HOST = fgdemo.links.appsilove.co` (оставить `CODE_SIGN_ENTITLEMENTS = Config/UniversalLinks.entitlements`), выполнить `xcodegen generate` и снова поставить Debug-сборку. Пример в `Local.xcconfig.example` нарочно нейтральный (`go.example.com`): файл видят клиенты FG.
4. На iPhone включить Settings → Developer → Associated Domains Development. В Settings → Developer → Universal Links → Diagnostics ввести `https://fgdemo.links.appsilove.co/open?user_id=u_ul` и убедиться, что ссылка сопоставлена с FunnelsGrove Demo.
5. Открыть эту ссылку тапом из Notes: демо показывает `u_ul`. В «Last links received» записать, какой обработчик её получил (`onContinueUserActivity` или `onOpenURL`), при холодном и тёплом старте.

Подпись проверяется так: entitlements сборки должны содержать `applinks:fgdemo.links.appsilove.co?mode=developer`. Ожидается строка `[String] applinks:fgdemo.links.appsilove.co?mode=developer`.

```bash
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/FunnelsGroveDemo-*/Build/Products/Debug-iphoneos/FunnelsGroveDemo.app | head -1)
echo "${APP:?no device build of FunnelsGroveDemo in DerivedData}"
codesign -d --entitlements - "$APP" 2>/dev/null | grep applinks
```

Если ссылка открылась в Safari, а не в приложении, проверить по порядку: AASA через `curl`, Team ID и bundle ID в строке `fgdemo`, entitlements сборки, включён ли Associated Domains Development.

- [ ] **Step 7: Зафиксировать результат**

Сделать скриншоты шагов 3, 4 и 5 и записать, что прошло, а что нет: в описание PR или в заметки задачи.

Push и PR решает владелец. На GitHub ещё нет ветки `main`, а PR нужна база. Один из вариантов — сделать `main` из коммита спеки, тогда в PR войдёт только реализация:

```bash
cd /Users/e/work2/appsilove/funnelsgrove-ios-sdk
git push origin b75bc0e:refs/heads/main
git push -u origin feat/sdk-prototype
```
