extends Node
## AIClient：最小可解析占位（WP-02）。
## WP-07/08 才接入本机 AI 网关；本轮明确处于 disabled/offline 状态，不发起任何网络请求。

var status := "disabled" # disabled | offline | ready
