# 筋トレロック

運動が続かない人向けのiOSプロトタイプです。通知をトリガーにして、アプリ内のセッション画面でスクワットの回数をVisionで判定し、目標回数まで完了ボタンを出さない構成にしています。

## 現在の実装

- SwiftUIの5タブ構成: 今日 / ログ / 予定 / 収録 / 設定
- `UNCalendarNotificationTrigger`による毎日通知
- `AVCaptureSession`のフロントカメラプレビュー
- `VNDetectHumanBodyPoseRequest`による骨格検出
- ひざ角度ベースのスクワット回数カウント
- セッション中のアプリ内ロック
- ワークアウト完了時のカメラ映像を自動スナップショットとしてログ保存
- 回数・時間・自動スナップショットのログ表示
- Simulator確認用の手動カウントボタン
- 学習データ用の骨格ログ収録タブ

## 学習データ収録

スクワット精度改善用の収録手順は [docs/squat-data-collection-plan.md](docs/squat-data-collection-plan.md) にまとめています。

## iOS制約

iOSアプリは、任意時刻に自動でアプリを前面起動することはできません。実運用では通知からユーザーに開かせます。

他アプリのブロックはFamilyControls / ManagedSettings / DeviceActivity系APIで設計します。ただし、実機、Screen Time権限、AppleのFamily Controls entitlementが必要です。
