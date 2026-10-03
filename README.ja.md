# AeroSpace for Windows

[English](README.md) | 日本語

AeroSpace for Windows は、[Nikita Bobko 氏の AeroSpace](https://github.com/nikitabobko/AeroSpace) を基にした、**Windows 11 x64** 向けの i3 スタイルのタイル型ウィンドウマネージャーです。このリポジトリは Windows のみを対象としています。

AeroSpace のツリー構造によるレイアウト、タイル・アコーディオン配置、フローティングウィンドウ、キーボード操作モード、複数モニター対応、TOML 設定、CLI を引き継いでいます。システムトレイに常駐するアプリが、公開されている Win32 API を使ってウィンドウを管理します。

## インストールと起動

1. `AeroSpace-Windows-x64.zip` を、継続して利用するフォルダーに展開してください。実行ファイル、DLL、マニフェスト、リソースフォルダーは同じ場所にまとめて置いてください。
2. `AeroSpaceApp.exe` を起動してください。通知領域のメニューから、有効化・無効化、設定の再読み込み、終了を操作できます。
3. PowerShell から `aerospace.exe` を実行すると、起動中のアプリを操作できます。必要に応じて、展開先のフォルダーをユーザーの `PATH` に追加してください。

```powershell
Start-Process .\AeroSpaceApp.exe
.\aerospace.exe list-windows --all
.\aerospace.exe workspace 2
.\aerospace.exe enable off
```

Windows のファイル名は大文字・小文字を区別しないため、常駐アプリと CLI は異なるファイル名になっています。ZIP には必要な Swift と Microsoft C++ のランタイムが含まれているので、利用するだけなら Swift の開発環境をインストールする必要はありません。

タスクバーの AeroSpace ボタンと通知領域のアイコンには、現在フォーカスしているワークスペース名の先頭 1〜2 文字（`B`、`C`、`N`、`1` など）を表示します。名前全体はボタンのタイトルや通知領域アイコンのヒントで確認できます。AeroSpace を無効化すると「—」に変わります。タスクバーボタンの文字ラベルを表示したい場合は、Windows のタスクバー設定で「タスクバー ボタンを結合しラベルを非表示にする」を「なし」にしてください。

アプリの起動用にタスクバーへピン留めする場合は、`AeroSpaceApp.exe` を選んでください。ピン留めしたショートカットは青い `A` のアプリアイコンを使い、実行中はアイコンの右下に現在のワークスペース名を小さく重ねて表示します。無効化すると「—」に変わります。Windows のタスクバーを小さいアイコンに設定している場合、この重ね表示は使えないため、通常サイズのアイコンか通知領域の表示を使ってください。旧バージョンでピン留めしたアイコンが空白の場合は、ピン留めを解除して更新後のアプリをもう一度ピン留めしてください。

AeroSpace のワークスペースは、Windows 標準の仮想デスクトップとは独立しています。ワークスペースを切り替えると、元のワークスペースのウィンドウを非表示にし、移動先のウィンドウを表示します。各モニターには、それぞれ表示中のワークスペースがあります。AeroSpace を無効化または終了すると、AeroSpace が非表示にしたウィンドウを再表示します。予期せず終了した場合も、別の監視プロセスが復元します。復旧情報は `%LOCALAPPDATA%\AeroSpace` に記録されます。

## 設定

次の順序で設定を探し、最初に見つかったものを使用します。

1. `AeroSpaceApp.exe --config-path C:\path\aerospace.toml` で指定したファイル。
2. ホームディレクトリ内の `.aerospace.toml`（`HOME` を使用し、未設定なら `USERPROFILE` を使用）。
3. `%APPDATA%\AeroSpace\aerospace.toml`.
4. 同梱の標準設定。

[default-config.toml](docs/config-examples/default-config.toml) を、使用する設定ファイルの場所にコピーしてください。`auto-reload-config = true` にすると変更を監視して自動で再読み込みします。手動で再読み込みする場合は `aerospace reload-config` を実行してください。再読み込みに失敗した場合はエラーを報告し、直前の有効な設定とキー割り当てを維持します。Windows や別のアプリが予約しているホットキーは登録できません。

修飾キーには `alt`、`ctrl`、`shift`、`win` を使用できます。設定内の `exec-and-forget` は PowerShell スクリプトを実行します。

```toml
[mode.main.binding]
alt-enter = 'exec-and-forget Start-Process notepad.exe'
```

### 標準のキー割り当て

| キー操作 | 動作 |
| --- | --- |
| Alt + H / J / K / L | 左 / 下 / 上 / 右のウィンドウにフォーカスを移動 |
| Alt + Shift + H / J / K / L | ウィンドウを左 / 下 / 上 / 右に移動 |
| Alt + 1…5 / B / C / N / O / Y | ワークスペースを切り替え |
| Alt + Shift + 1…5 / B / C / N / O / Y | ウィンドウを指定のワークスペースに移動 |
| Alt + Ctrl + B | 直前のワークスペースに戻る |
| Alt + / | タイル配置の向きを切り替え |
| Alt + , | アコーディオン配置の向きを切り替え |
| Alt + Shift + Space | フローティング / タイル配置を切り替え |
| Alt + F | AeroSpace の fullscreen を切り替え |
| Alt + − / = | サイズを変更 |
| Alt + Shift + ; | サービスモードに移行 |
| サービスモードで Esc | 設定を再読み込みしてメインモードに戻る |

詳細は [Windows ガイド](docs/guide.adoc)、[コマンドリファレンス](docs/commands.adoc)、`aerospace <command> --help` を参照してください。フィルターや出力で使用するアプリケーション ID は、`notepad.exe` のような実行ファイル名です。出力項目には `%{app-id}`、`%{app-exec-path}`、`%{app-executable-directory}` などがあります。

## 対応範囲と制限

- Windows 標準の仮想デスクトップの作成・切り替えや、その間でのウィンドウ移動には対応していません。
- `macos-native-fullscreen`、`macos-native-minimize`、`volume`、`move-mouse`、`subscribe`、`debug-windows` は使用できません。`fullscreen` は AeroSpace のレイアウトを変更するコマンドです。
- `start-at-login`、`automatically-unhide-macos-hidden-apps`、`focus-follows-mouse` の設定項目には対応していません。自動起動には Windows のスタートアップ設定やショートカットを使用してください。
- 現在のユーザーセッションと Windows 仮想デスクトップにある、管理対象のデスクトップウィンドウを操作します。ダイアログやサイズ変更できないウィンドウはフローティングで開始し、シェルやツール用のウィンドウは対象から除外します。
- Windows のフォーカス移動制限やアプリの最小サイズ制限により、指定したフォーカスや位置・サイズを反映できない場合があります。管理者権限で動作するアプリのウィンドウを操作するには、AeroSpace も同じ権限で実行する必要がある場合があります。
- Windows の表示・非表示要求は非同期で処理されるため、復旧記録は対象のウィンドウやプロセスの識別情報が無効になるまで保持します。その後、アプリ自身がそのウィンドウを非表示にした場合でも、復旧時に再表示されることがあります。

## ビルドとテスト

Windows 用 Swift **6.4.0**、Visual Studio 2022 の「C++ によるデスクトップ開発」ワークロード、Windows SDK をインストールしてください。リポジトリのフォルダーで PowerShell 7（`pwsh`）を使用して実行します。

```powershell
.\build.ps1 -Test
.\build-release.ps1
```

デバッグ用の実行ファイルは `.build\x86_64-unknown-windows-msvc\debug` に、配布用 ZIP は `.release\AeroSpace-Windows-x64.zip` に生成されます。テストコマンドは Swift のモデル・パーサーのテストと、専用のテストウィンドウを使う Windows の動作確認を実行します。[開発手順](dev-docs/development.md) と [アーキテクチャ](dev-docs/architecture.md) も参照してください。

## ライセンスと原作者の表記

元の AeroSpace のコードと著作権表示は、[MIT ライセンス](LICENSE.txt) の下で保持しています。Windows 向けの変更も同じライセンスで配布します。依存ライブラリのライセンス情報は [legal](legal/README.md) を参照してください。この Windows 移植版は、元の macOS プロジェクトとは別のプロジェクトです。
