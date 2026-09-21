# TranslateAI — iPhone 離線 AI 翻譯 App

用 iPhone 內建的裝置端 AI 做翻譯，**不需要網路**。

## 架構決策

App 同時用到 Apple 的兩套裝置端 AI，各司其職：

| 元件 | 負責 | 需求 |
|---|---|---|
| **Translation framework** | 實際翻譯（主引擎），離線語言包 | iOS 18+，所有機型 |
| **Foundation Models framework** | 語氣改寫、語意解釋、OCR 文字整理 | iOS 26+ 且支援 Apple Intelligence（iPhone 15 Pro 以上） |
| **Speech framework** | 裝置端語音辨識（`requiresOnDeviceRecognition = true`） | iOS 18+ |
| **AVSpeechSynthesizer** | 譯文朗讀 | iOS 18+ |
| **Vision** | 相機文字辨識（OCR） | iOS 18+ |

**為什麼不直接用 Foundation Models 翻譯？** 它是通用的 ~3B 模型，長句、專有名詞、少見語言的翻譯品質不如專門訓練的 Translation framework，而且只有 Apple Intelligence 機型能跑。目前的分工讓 App 在**所有** iOS 18 機型上都完整可用，有 Apple Intelligence 的機型再多拿到加值功能。

## 功能

- 文字翻譯，輸入時即時翻譯（350ms debounce）
- 語音輸入 → 翻譯 → 朗讀，全程離線
- 相機／相簿拍照 OCR 翻譯
- 離線語言包管理（查看已下載、觸發下載）
- 本機翻譯紀錄與收藏（存成 JSON，不上雲）
- 語氣改寫：正式／口語／精簡／親切
- 語意解釋：說明俚語、成語、文化脈絡

## 專案結構

```
TranslateAI/
├── TranslateAIApp.swift              App 進入點，注入所有服務
├── Models/
│   ├── AppSettings.swift             語言選擇與偏好，存 UserDefaults
│   ├── Language.swift                Locale.Language 包裝與顯示名稱
│   └── TranslationRecord.swift       一筆翻譯紀錄
├── Services/
│   ├── TranslationEngine.swift       ★ 核心：Translation framework 包裝
│   ├── FoundationModelsAssistant.swift  裝置端 LLM 加值層
│   ├── SpeechService.swift           離線語音辨識 + 朗讀
│   ├── OCRService.swift              Vision 文字辨識
│   └── HistoryStore.swift            本機紀錄
└── Views/
    ├── RootView.swift                TabView，掛載共用 translationTask
    ├── LanguageBar.swift             語言選擇列 + 選擇器
    ├── TextTranslateView.swift       文字／語音翻譯
    ├── CameraTranslateView.swift     相機翻譯
    ├── OfflinePacksView.swift        語言包管理
    └── HistoryView.swift             紀錄
```

### TranslationEngine 為什麼這樣寫

Apple 的 Translation framework 有個彆扭的限制：`TranslationSession` **只能**從 `.translationTask` 這個 View modifier 拿到，而且只在那個 closure 存活期間有效，不能自己 `init` 一個存起來。

所以 `TranslationEngine` 用了一個佇列：

- 任何地方都可以 `await engine.translate(text)`，請求進 `AsyncStream`
- `RootView` 把 `.translationTask` 掛在 `TabView` 上，`engine.serve(session)` 持續消費佇列
- 切換語言時 `restartQueue()` 換掉 stream，並讓所有等待中的請求以錯誤結束（避免 continuation 洩漏）

這樣四個分頁共用同一個 session，不會各開各的。

## 開發環境

> **注意：iOS 開發需要 macOS + Xcode。** 你目前在 Windows 上，程式碼可以在這裡寫和版控，但編譯、模擬器、上架都必須在 Mac 上做。可行的選項是：借／買一台 Mac、租雲端 Mac（MacStadium、MacinCloud、AWS EC2 Mac），或用 GitHub Actions 的 macOS runner 做 CI build。

需求：

- Xcode 16 以上（`objectVersion = 77` 的同步資料夾格式）
- 想測 Foundation Models 功能：Xcode 26 + iOS 26 SDK，且要用**實機**（支援 Apple Intelligence 的機型）——模擬器沒有裝置端模型
- 想測 Translation framework：iOS 18 模擬器即可，但語言包下載在實機上比較可靠

## 在 Mac 上跑起來

```bash
git clone <this-repo> && cd translate
open TranslateAI.xcodeproj
```

然後在 Xcode 裡：

1. 選 target `TranslateAI` → Signing & Capabilities → 設你自己的 Team
2. 把 `PRODUCT_BUNDLE_IDENTIFIER` 從 `com.example.TranslateAI` 改成你自己的
3. 選實機 → Run

如果只有 iOS 18 SDK，`FoundationModelsAssistant` 會透過 `#if canImport(FoundationModels)` 整段停用，其餘功能照常編譯。

## 首次使用要下載的東西

離線翻譯不是憑空的，每種語言都要先下載資料：

| 功能 | 下載位置 |
|---|---|
| 翻譯語言包 | App 內「語言包」分頁，或 設定 → App → 翻譯 → 已下載的語言 |
| 離線聽寫 | 設定 → 一般 → 鍵盤 → 聽寫語言 |
| 朗讀語音 | 設定 → 輔助使用 → 朗讀內容 → 語音 |
| Apple Intelligence 模型 | 設定 → Apple Intelligence 與 Siri（約數 GB） |

## 已知限制

- Translation framework 不提供「直接下載語言 X」的 API，只能用 `prepareTranslation()` 觸發系統的下載提示。`OfflinePacksView` 就是這樣做的。
- 相機翻譯是拍照後辨識，不是即時 AR 疊字。要做即時疊字需要換成 `AVCaptureSession` + 每幀 Vision + 座標映射，成本高很多。
- `requiresOnDeviceRecognition = true` 代表沒下載離線聽寫資料的語言會直接失敗，不會 fallback 到網路 — 這是刻意的。
- 語音／相機分頁的紀錄來源判斷用 `speech.transcript.isEmpty`，長時間使用時可能誤判，之後應該改成明確的狀態旗標。

## 下一步可以做的

- 對話模式：雙向分割畫面，兩個人輪流講
- 自訂詞彙表：用 Foundation Models 的 guided generation 強制某些專有名詞的譯法
- Live Text 式的即時相機疊字
- App Intents / Shortcuts 整合，讓 Siri 能呼叫
- 分享選單擴充（Share Extension），在別的 App 裡選字直接翻譯
