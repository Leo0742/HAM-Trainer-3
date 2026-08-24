# Финальная визуальная QA

Release-сборка `Build/HAM Trainer 3.app` отрисована встроенным opt-in snapshot hook из production SwiftUI views. Проверены light/dark appearance, regular/large/extra-large text и размеры 1000–2048 points.

| Файл | Сценарий |
|---|---|
| `01-dashboard-1366-light-large.png` | обзор, идентичность и 218 вопросов |
| `02-smart-before-1366-light-large.png` | Smart Study до ответа |
| `03-smart-after-1440-light-large.png` | обратная связь после ответа |
| `04-other-answers-1440-light-large.png` | разбор трёх неверных вариантов |
| `05-study-history-2048-dark-extra-large.png` | Back/Forward, dark, extra large |
| `06-weak-rounds-1440-light-large.png` | тренировка 1/3/5 кругов |
| `07-topics-list-1366-light-large.png` | чистый список тем |
| `08-topic-reference-1440-light-large.png` | ответы темы видны сразу, одна кнопка обучения |
| `09-topic-expanded-1440-light-large.png` | раскрытая справочная карточка |
| `10-questions-1440-light-large.png` | глобальный список и компактные фильтры |
| `11-question-detail-1440-light-large.png` | глобальная справочная карточка |
| `12-mock-question-1366-light-large.png` | пробный экзамен, 25 вопросов |
| `13-mock-results-1440-dark-large.png` | результат 20/25 |
| `14-settings-1366-light-regular.png` | настройки и отдельное хранилище |
| `15`–`21` | runtime-вопросы 22, 23, 32, 173, 176, 177 и 180 с фигурами и вариантами |
| `22-glossary-superheterodyne-1000-light-large.png` | карточка термина |

Проверено: нет чёрных полей в прямых снимках, горизонтальной прокрутки и обрезанного русского текста в основных сценариях; длинные варианты переносятся; изображения читаемы и не содержат ответа; варианты вопросов 23 и 32 не содержат OCR-текста таблиц. Для каждого figure-question снимок показывает формулировку, изображение и варианты.

Снимки находятся в `docs/screenshots/final-qa/` и являются визуальным доказательством, а не заменой сценарных тестов.
