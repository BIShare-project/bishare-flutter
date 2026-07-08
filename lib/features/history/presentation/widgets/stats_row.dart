import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'stat_card.dart';

class StatsRow extends StatelessWidget {
  const StatsRow({super.key, 
    required this.total,
    required this.sent,
    required this.received,
  });
  final int total;
  final int sent;
  final int received;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Row(
        children: [
          Expanded(
            child: StatCard(label: 'history.total'.tr(), value: total),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatCard(label: 'history.sent'.tr(), value: sent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatCard(label: 'history.received'.tr(), value: received),
          ),
        ],
      ),
    );
  }
}
