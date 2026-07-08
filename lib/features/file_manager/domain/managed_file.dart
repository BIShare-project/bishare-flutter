
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
    GroupMode.category => 'Category',
    GroupMode.sender => 'Sender',
    GroupMode.date => 'Date',
  };
}

/// How the File Manager orders files within a group.
enum SortMode {
  newest,
  oldest,
  largest,
  name;

  String get label => switch (this) {
    SortMode.newest => 'Newest',
    SortMode.oldest => 'Oldest',
    SortMode.largest => 'Largest',
    SortMode.name => 'Name',
  };
}
