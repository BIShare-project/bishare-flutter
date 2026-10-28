/// BIShare design system: one shared kit, so feature pages stay short and
/// look the same everywhere (redesign-plan.md "Components"). Import this one
/// file to get the tokens, the type scale and every widget below.
///
/// - [AppTokens] via `context.tokens`, [AppType], [AppMotion]
/// - [AppCard]          the one emphasised block of a screen
/// - [AppListTile]      list row (leading / title / subtitle / trailing)
/// - [AppGroup]         groups rows (flat, or `card: true`)
/// - [AppRowDivider]    hairline between rows
/// - [AppSectionHeader] sentence-case section label
/// - [AppGlyph], [AppSwitchRow], [AppValueRow]  settings-style rows
/// - [AppTabBar], [AppSegmented], [AppChips]    tabs, segments, filters
/// - [AppSelectionBar], [AppSelectionSummary]   the floating selection bar
/// - [AppMediaTile], [AppRowCheck]              selectable photo tile / row check
/// - [AppDeviceAvatar]  device circle with progress ring
/// - [AppTextField]     text input for sheets (name, PIN)
/// - [AppCodeBoxes]     code input (room, transfer, Drive browser)
/// - [AppAvatar], [AppBadge], [AppStatusPill], [AppIconButton]
/// - [AppButton], [AppIconOnlyButton]
/// - [AppEmptyState]    glyph + title + message + optional action
/// - [AppShimmer], [AppSkeletonBox]  loading skeletons
/// - [showAppSheet] / [AppSheetAction]  sheet on phones, dialog on wide
library;

export '../theme/app_tokens.dart';
export '../theme/app_type.dart';
export 'app_avatar.dart';
export 'app_badge.dart';
export 'app_bottom_nav.dart';
export 'app_button.dart';
export 'app_card.dart';
export 'app_code_boxes.dart';
export 'app_device_avatar.dart';
export 'app_empty_state.dart';
export 'app_format.dart';
export 'app_media_tile.dart';
export 'app_rows.dart';
export 'app_selection_bar.dart';
export 'app_tabs.dart';
export 'app_text_field.dart';
export 'bishare_qr.dart';
export 'file_open.dart';
export 'file_preview.dart';
export 'app_icon_button.dart';
export 'app_list_tile.dart';
export 'app_nav_rail.dart';
export 'app_row_menu.dart';
export 'media_thumb.dart';
export 'app_responsive.dart';
export 'app_screen_header.dart';
export 'app_section.dart';
export 'app_search_field.dart';
export 'app_sheet.dart';
export 'app_shimmer.dart';
export 'app_source_pill.dart';
export 'app_svg_icon.dart';
