# Calendar iOS Architecture (SwiftUI)

Этот документ описывает архитектуру iOS-версии приложения `Calendar`, которая должна быть зеркальным отражением Android-версии на Kotlin/Jetpack Compose.

## Основной стек технологий
*   **Язык:** Swift 6.0+
*   **UI Framework:** SwiftUI (аналог Jetpack Compose)
*   **Архитектурный паттерн:** MVVM (Model-View-ViewModel)
*   **DI (Dependency Injection):** Swift Property Wrappers или библиотеки (например, `Needle`)
*   **Backend:** Firebase (Messaging, Functions) — переиспользуем текущую инфраструктуру.

## Соответствие технологий (Android -> iOS)

| Компонент | Android (Kotlin/Compose) | iOS (Swift/SwiftUI) |
| :--- | :--- | :--- |
| **UI** | Jetpack Compose | SwiftUI |
| **Data Binding** | StateFlow / LiveData | `@Published` / `@State` / `@Binding` |
| **DI** | Hilt | Swift Property Wrappers / Custom Factories |
| **Networking** | Retrofit / Ktor | URLSession / Alamofire |
| **Async** | Coroutines | Swift Concurrency (`async/await`, `Task`) |
| **Local DB** | Room | SwiftData / CoreData |
| **Image Loading** | Coil / Glide | AsyncImage / SDWebImageSwiftUI |

## Структура проекта (Рекомендуемая)
```text
CalendarIos/
├── Sources/
│   ├── App/                # Точка входа (CalendarApp.swift)
│   ├── Domain/             # Бизнес-логика, Протоколы, Use Cases
│   ├── Data/               # Репозитории, Модели данных, Firebase API
│   ├── Presentation/       # View и ViewModels (SwiftUI)
│   └── Common/             # Утилиты, расширения, ресурсы
└── Tests/                  # Unit и UI тесты
```

---
*Проект инициирован 7 марта 2026 г.*
