import '../models/steam_confirmation.dart';

/// Legacy UI fixtures — not used by the live confirmations page.
const mockConfirmations = <SteamConfirmation>[
  SteamConfirmation(
    id: 'mock-1',
    nonce: 'mock-nonce-1',
    accountId: 'mock-primary',
    kind: ConfirmationKind.login,
    title: '新设备登录',
    subtitle: 'Chrome · 上海',
    timeLabel: '2 分钟前',
    risk: ConfirmationRisk.medium,
    accountName: 'demo_primary',
  ),
  SteamConfirmation(
    id: 'mock-2',
    nonce: 'mock-nonce-2',
    accountId: 'mock-trading',
    kind: ConfirmationKind.trade,
    title: '交易报价 #48219',
    subtitle: '对方给出 3 件物品',
    timeLabel: '刚刚',
    risk: ConfirmationRisk.high,
    accountName: 'demo_trading',
  ),
  SteamConfirmation(
    id: 'mock-3',
    nonce: 'mock-nonce-3',
    accountId: 'mock-primary',
    kind: ConfirmationKind.market,
    title: '市场上架 AK-47 | Redline',
    subtitle: '售价 \$12.40',
    timeLabel: '18 分钟前',
    risk: ConfirmationRisk.low,
    accountName: 'demo_primary',
  ),
];
