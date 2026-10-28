import 'package:easy_localization/easy_localization.dart';

/// A file on disk in the receive directory, enriched with drift metadata.
class ManagedFile {
  const ManagedFile({
    required this.name,
    required this.path,
    required this.size,
    required this.category,
    required this.sender,
    required this.modified,
    this.fileType,
    this.encrypted = false,
    this.recordId,
  });

  final String name;
  final String path;
  final int size;
  final String category;
  final String sender;
  final DateTime modified;
  final String? fileType;
  final bool encrypted;
  final int? recordId;

  String get id => path;
}

/// How the File Manager buckets files.
enum GroupMode {
  category,
  sender,
  date;

  String get label => switch (this) {
    GroupMode.category => 'files.by_folder'.tr(),
    GroupMode.sender => 'files.by_sender'.tr(),
    GroupMode.date => 'files.by_date'.tr(),
  };
}

/// How the File Manager orders files within a group.
enum SortMode {
  newest,
  oldest,
  largest,
  name;

  String get label => switch (this) {
    SortMode.newest => 'files.sort_newest'.tr(),
    SortMode.oldest => 'files.sort_oldest'.tr(),
    SortMode.largest => 'files.sort_largest'.tr(),
    SortMode.name => 'files.sort_name'.tr(),
  };
}

/// The shown name of a [ManagedFile.category] (the receiver's English
/// subfolder names).
String categoryLabel(String category) => switch (category) {
  'Images' => 'files.cat_images'.tr(),
  'Videos' => 'files.cat_videos'.tr(),
  'Audio' => 'files.cat_audio'.tr(),
  'Documents' => 'files.cat_documents'.tr(),
  'Archives' => 'files.cat_archives'.tr(),
  _ => 'files.cat_other'.tr(),
};
