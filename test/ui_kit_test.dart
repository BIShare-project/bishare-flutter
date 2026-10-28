// redesign-plan.md task 1.7: every shared component lays out without an
// overflow in both themes, at 200% text and right to left.
import 'package:bishare/core/theme/app_theme.dart';
import 'package:bishare/core/ui/app_ui.dart';
import 'package:bishare/features/home/widgets/transfer_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {required bool dark, required bool rtl}) {
  return MaterialApp(
    theme: AppTheme.light('blue'),
    darkTheme: AppTheme.dark('blue'),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

final _kit = Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    const AppScreenHeader(title: 'Kotak Masuk', subtitle: '14 file diterima'),
    const AppSectionHeader('Menerima'),
    TransferCard(
      icon: AppIcons.downloadFile,
      title: 'Menerima dari MacBook Pro milik Cakra',
      subtitle: '2 dari 5 file · 42% · 38,1 MB/s · 12 dtk',
      badge: 'QUIC',
      fraction: 0.42,
      onClose: () {},
    ),
    TransferCard(
      icon: AppIcons.check,
      filled: true,
      title: '5 file diterima',
      subtitle: 'Dari MacBook Pro · 41,2 MB',
      action: ('Lihat', () {}),
      onClose: () {},
    ),
    AppGroup(
      card: true,
      child: Column(
        children: [
          AppSwitchRow(
            icon: AppIcons.wifi,
            title: 'Terlihat oleh semua',
            subtitle: 'Mati = tersembunyi, tidak dapat ditemukan',
            value: true,
            onChanged: (_) {},
          ),
          const AppRowDivider(indent: 52),
          AppValueRow(
            icon: AppIcons.verifiedCheck,
            title: 'Terima otomatis',
            value: 'Selalu tanya',
            onTap: () {},
          ),
        ],
      ),
    ),
    const SizedBox(
      height: 46,
      child: DefaultTabController(
        length: 3,
        child: AppTabBar(
          tabs: [AppTab('Foto', count: 3), AppTab('Video'), AppTab('Dokumen')],
        ),
      ),
    ),
    AppSegmented<int>(
      value: 0,
      options: const [(0, 'Diterima'), (1, 'Riwayat')],
      onChanged: (_) {},
    ),
    AppChips<int>(
      value: 0,
      options: const [(0, 'Semua'), (1, 'PDF'), (2, 'Arsip')],
      onChanged: (_) {},
    ),
    SizedBox(
      height: 120,
      child: Row(
        children: [
          Expanded(
            child: AppMediaTile(
              image: const ColoredBox(color: Colors.teal),
              semanticLabel: 'Foto',
              selected: true,
              order: 2,
              onTap: () {},
            ),
          ),
          const Expanded(
            child: AppMediaTile(
              image: ColoredBox(color: Colors.orange),
              semanticLabel: 'Video',
              durationSeconds: 194,
              sizeLabel: '562,6 MB',
            ),
          ),
        ],
      ),
    ),
    const Row(
      children: [
        AppDeviceAvatar(
          icon: AppIcons.smartphone,
          ring: AppTransferRing.running,
          progress: 0.6,
          favourite: true,
        ),
        AppDeviceAvatar(
          icon: AppIcons.monitor,
          ring: AppTransferRing.failed,
          progress: 0.4,
        ),
        AppDeviceAvatar(icon: AppIcons.monitor, ring: AppTransferRing.done),
      ],
    ),
    Center(
      child: AppCodeBoxes(
        controller: TextEditingController(text: 'K7Q'),
        length: 6,
        autofocus: false,
      ),
    ),
    AppButton(label: 'Kirim', onPressed: () {}, fullWidth: true),
    AppButton(
      label: 'Kirim',
      variant: AppButtonVariant.brand,
      onPressed: () {},
    ),
    const AppEmptyState(
      icon: AppIcons.notification,
      title: 'Kotak masuk Anda kosong',
      message: 'File yang Anda terima akan muncul di sini',
    ),
    AppSelectionBar(
      visible: true,
      onClear: () {},
      summary: const AppSelectionSummary(title: '3 item', subtitle: '11,1 MB'),
      primary: ('Kirim', () {}),
    ),
    AppSelectionBar(
      visible: true,
      onClear: () {},
      summary: const AppSelectionSummary(title: '2 dipilih'),
      actions: [
        AppBarAction(icon: AppIcons.imageDown, label: 'Simpan', onTap: () {}),
        AppBarAction(icon: AppIcons.trashDelete, label: 'Hapus', onTap: () {}),
      ],
    ),
  ],
);

void main() {
  for (final dark in [false, true]) {
    for (final rtl in [false, true]) {
      testWidgets('kit lays out: dark=$dark rtl=$rtl, 200% text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(_kit, dark: dark, rtl: rtl));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Kirim'), findsWidgets);
      });
    }
  }
}
