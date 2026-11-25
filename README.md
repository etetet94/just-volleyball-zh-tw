# just volleyball 繁體中文模組

適用於 [just volleyball 的 Windows Steam 版](https://store.steampowered.com/app/5037200/just_volleyball/)，提供繁體中文介面與玩法指南。這是社群製作的非官方模組。

**[下載最新安裝包](https://github.com/etetet94/just-volleyball-zh-tw/raw/refs/heads/main/downloads/JustVolleyball-zhTW-v1.0.1.zip)**

目前包含 **1,620 組翻譯**，涵蓋主選單、設定、基本教學、更衣室、商店、比賽介面、生涯、成就與重播。模組使用 Windows 上的中文字型作為原字型的後備字型。

## v1.0.1 補譯

- 補上練習場的個人／共用排球、無限體力、球路提示、玩家碰撞與 1 對 1～6 對 6 標示。
- 修正右側操作提示被誤判為玩家名稱，導致已有翻譯仍顯示英文的問題。
- 完整翻譯解除滑鼠鎖定、視角、召喚排球、接球、舉球、魚躍救球、跳躍、側移與衝刺等提示；保留按鍵圖示。
- 沿用玩家名稱與聊天輸入保護，不變更玩法數值或連線功能。

## 安裝

安裝包不需要 Python 或 Godot 編輯器。

1. 先在 Steam 安裝遊戲，並完全關閉遊戲。
2. 點選上方下載連結，取得 `JustVolleyball-zhTW-v*.zip`。
3. **完整解壓縮 ZIP** 到一般可寫入的資料夾；不要直接在壓縮檔內執行。
4. 按兩下 **`Install.cmd`**。安裝程式會自動尋找 Steam 遊戲目錄。
5. 顯示安裝完成後，照常從 Steam 啟動遊戲。

保留解壓縮後的資料夾，之後可以用其中的移除工具恢復原文。

### 手動指定遊戲位置

若安裝程式找不到遊戲，請在解壓縮後的資料夾開啟 PowerShell，執行下列指令，並替換遊戲路徑：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Install -GameDir "D:\SteamLibrary\steamapps\common\just volleyball"
```

選擇的資料夾必須同時包含 `volleyball.exe` 和 `volleyball.pck`。Steam 的「內容 → 已安裝檔案 → 瀏覽」可以開啟這個資料夾。

## 移除／恢復英文

1. 完全關閉遊戲。
2. 在解壓縮後的資料夾按兩下 **`Uninstall.cmd`**。
3. 再從 Steam 啟動遊戲。

手動指定位置移除：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup.ps1 -Action Uninstall -GameDir "D:\SteamLibrary\steamapps\common\just volleyball"
```

移除工具會停用本模組的載入項目。翻譯檔和首次安裝前的設定備份仍保留於遊戲目錄的 `jv_zh_tw` 資料夾，方便重新安裝或檢查；它不會用舊備份覆蓋後來新增的其他設定。

## 相容版本與範圍

- 製作與測試版本：遊戲 **v1.0.4.2／Steam Build `26924091`**。
- 安裝程式新增 `jv_zh_tw` 資料夾，並在 `override.cfg` 的 `[autoload]` 加入 `JVTraditionalChinese`。
- 模組處理顯示文字與字型，不修改遊戲執行檔、主要資源包或玩法數值；安裝與移除程式不編輯遊戲存檔。
- 既有 `override.cfg` 的其他設定與其他模組項目會保留。原設定的首次備份放在 `jv_zh_tw/backup`。
- 部分物品專有名稱、玩家自訂內容與特殊動態訊息可能保留原文。玩家名稱保護採介面節點辨識，特殊介面仍可能需要補強。
- 遊戲更新後可能出現未翻譯文字或介面差異；玩法指南補丁的內容以製作版本為準。更新後若出現異常，可先移除模組確認原版行為。
- 字型優先使用微軟正黑體等 Windows 字型。缺少中文字型的系統需先安裝支援繁體中文的字型。

本模組不封鎖線上介面。官方[線上條款](https://store.steampowered.com/eula/5037200_eula_0)第 3 條禁止在線上遊玩時修改遊戲；目前沒有確認語言模組是否獲得豁免。本專案不宣稱取得官方的線上使用許可。

## 常見問題

### 安裝後仍是英文

完全退出遊戲後重新啟動。安裝程式必須顯示「繁體中文模組已安裝」，並且安裝在 Steam 正在啟動的那份遊戲目錄；有多個 Steam 資料庫時可用上方手動指令指定路徑。

### 顯示權限不足

確認 ZIP 已完整解壓縮，然後右鍵點選 `Install.cmd` →「以系統管理員身分執行」。移除時若遇到相同問題，也可以用相同方式執行 `Uninstall.cmd`。

### 顯示已有同名資料夾或載入項目

安裝程式會停止，避免覆蓋無法辨識的內容。先確認該項目屬於哪個模組，並使用原模組的移除方式；保留自己的設定與備份後再處理。

### 中文顯示成方框

請確認 Windows 已安裝繁體中文語言／補充字型，且有微軟正黑體或其他支援繁體中文的系統字型。

## 原始碼與建置

直接安裝下載的 ZIP 不需要建置。要修改或自行打包，請使用 **Python 3.9 以上**，只需要標準函式庫：

```powershell
python scripts/build_guide_pack.py
python scripts/build_release.py --version v1.0.1
```

輸出為 `dist/JustVolleyball-zhTW-v1.0.1.zip` 與 `dist/SHA256SUMS.txt`。相同輸入檔案會產生相同的指南 PCK 和安裝 ZIP。

| 檔案 | 用途 |
| --- | --- |
| `jv_zh_tw/localize.gd` | Godot 載入、翻譯與字型處理 |
| `jv_zh_tw/translations.json` | 英文原文對應繁中譯文 |
| `jv_zh_tw/guide_zhTW.json` | 可閱讀、可編輯的繁中指南資料 |
| `jv_zh_tw/guide_zhTW.pck` | 由指南 JSON 產生的單一資源補丁 |
| `Setup.ps1` | 安裝、備份與停用載入項目 |
| `scripts/` | 不依賴原遊戲或私有路徑的建置工具 |

修正翻譯或回報問題前，請先閱讀 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 授權與來源

本專案自行編寫的模組程式與新增繁中翻譯貢獻採 [MIT License](LICENSE)。原遊戲、原英文文字、原資料結構、商標及其他原始素材的權利仍屬各自權利人；MIT 不授予這些原始內容的權利。指南資料是供合法遊戲使用的在地化衍生補丁。詳見 [NOTICE.md](NOTICE.md)。

本專案沒有附帶遊戲主程式、主要資源包、付費內容、第三方漢化切換器或 Windows 字型，也不代表 temkosoft 官方。
