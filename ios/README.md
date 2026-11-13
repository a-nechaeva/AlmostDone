
# Серверная сессия iOS

Чистый checkout запускается в режиме `demo` с `DemoStore`. Этот же режим
используют навигация и скриншоты в iOS GitHub Actions. Для получения пакета
при сборке нужен доступ к GitHub.

## Вход на устройстве

1. В Яндекс OAuth включите платформу iOS для приложения, чей Client ID указан
   на целевом backend в `ALMOSTDONE_YANDEX_CLIENT_ID`. Сервер принимает токены
   только этого OAuth-приложения. Для публичного стенда исходное значение
   задано в [server/Dockerfile](../server/Dockerfile). Укажите iOS App ID из App ID Prefix
   и bundle ID подписываемого приложения (`itmo.AlmostReady` по умолчанию),
   а также URL в App Store, который требует форма Яндекс OAuth.
2. Base URL публичного стенда — `https://51.250.76.77` ([настройка деплоя](../deploy/README.md)).
   Для другого стенда укажите его HTTPS-origin с путём прокси, если он есть.
   `APIClient` сам добавляет `/api/v1`. Убедитесь, что с устройства доступен
   `GET /api/v1/health/ready` и ответ содержит `checks.yandex: configured`.
3. В корне этого checkout создайте игнорируемый Git файл
   `.local/ios-server.xcconfig`:

   ```xcconfig
   ALMOSTREADY_MODE = server
   ALMOSTREADY_API_BASE_URL = https:/$()/51.250.76.77
   ALMOSTREADY_YANDEX_CLIENT_ID = <Client ID из настроек backend>

   ```

   `$()` сохраняет второй слеш в `https://` при разборе `xcconfig`.
   Для возврата к демо удалите локальный override или задайте `ALMOSTREADY_MODE = demo`.
4. Откройте `ios/AlmostReady/AlmostReady.xcodeproj` в Xcode и установите
   приложение на подписанное устройство. Нажмите «Войти через Яндекс ID»,
   пройдите вход. После успешного `GET /api/v1/me/state` откроется вкладка
   «Мои продукты». Закройте и запустите приложение снова для проверки
   восстановления сессии. В «Профиле» нажмите «Выйти» и дождитесь, пока
   на экране входа появится кнопка «Войти через Яндекс ID». Перезапустите
   приложение для проверки очистки сессии. Если сервер не подтвердил отзыв,
   экран входа сообщит об этом. Отдельно проверьте отмену входа в системном
   окне Яндекс ID.

Используется официальный `YandexLoginSDK` 3.2.0 через SwiftPM. `Info.plist`
регистрирует `yx<Client ID>`. В стратегии `.webOnly` системный
`ASWebAuthenticationSession` передаёт callback SDK. Associated Domains понадобятся при переходе на вход через приложения Яндекса.
Client ID задаётся локально. Client Secret приложению не нужен. OAuth-токен
передаётся в обмен и удаляется из кэша SDK. Серверная пара хранится одной записью
в Keychain для этого адреса и Client ID.

[Регистрация iOS-приложения](https://yandex.com/dev/id/doc/en/mobileauthsdk/ios/sdk-ios-main) ·
[Настройка URL scheme](https://yandex.ru/dev/id/doc/ru/mobileauthsdk/ios/2.1.1/sdk-ios-install) ·
[Справочник SDK](https://yandex.ru/dev/id/doc/ru/mobileauthsdk/ios/2.1.1/sdk-ios-methods) ·
[Исходники SDK 3.2.0](https://github.com/yandexmobile/yandex-login-sdk-ios/tree/3.2.0)

## Подключение экранов

`ServerRoot` передаёт общий `SessionStore` через SwiftUI Environment
и привязывает дерево к `session.account?.id`. При активной сессии `ServerRoot`
открывает `ContentView`, где по умолчанию выбрана вкладка «Мои продукты».
После выхода `ServerRoot` возвращает экран входа.

В точке входа экрана используйте
`@Environment(SessionStore.self) private var session: SessionStore?`.
При наличии `session.account` создайте серверный репозиторий с этим аккаунтом
и передайте его модели экрана. Демо-ветка получает существующий `DemoStore`.
Пример защищённого запроса в репозитории:

```swift
import Foundation

@MainActor
struct ProfileRepository {
    let session: SessionStore
    let account: AccountSession

    func profile<Profile: Decodable & Sendable>(
        _ type: Profile.Type
    ) async throws -> APIResponse<Profile> {
        try await session.json(type, for: APIRequest(path: ["me"]), account: account)
    }
}

```

- `SessionStore` подставляет Bearer, обновляет токены при 401 и повторяет
  GET один раз. Запись после 401, тайм-аута или другой ошибки экран разбирает
  по контракту конкретной операции. Сохраните исходный `Idempotency-Key`,
  если контракт разрешает повтор. При тайм-ауте или другом неопределённом
  исходе refresh нужен повторный вход. Подтверждённый ответ `429 rate_limited`
  откладывает новую попытку до истечения `Retry-After`.
- `session.revision` содержит общую известную версию. Для `If-Match` возьмите
  ETag снимка, на котором основано изменение, и сохраните его вместе с черновиком.
  При конфликте 412 вызовите `reloadRevision(for: account)`, перечитайте данные
  экрана и согласуйте изменение с новым снимком. После успешной мутации вызовите
  `confirmMutation(response.metadata, stateVersion: bodyVersion, account: account)`.
  Если у ответа только ETag, опустите `stateVersion`. Версия общая для всех
  экранов и не уменьшается от позднего ответа. Экран может перечитать свои
  данные при изменении `session.revision?.stateVersion`.
- При выходе или смене аккаунта дерево пересоздаётся. Держите состояние
  экрана и кэш в этом дереве. Для кэша за его пределами используйте
  `account.id` и удаляйте данные предыдущей сессии при смене ID. Если
  между получением результата и записью в модель есть ещё одна точка
  приостановки, проверьте `session.isCurrent(account)` перед записью.
