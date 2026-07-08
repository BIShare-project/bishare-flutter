// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TransferRecordsTable extends TransferRecords
    with TableInfo<$TransferRecordsTable, TransferRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedPathMeta = const VerificationMeta(
    'savedPath',
  );
  @override
  late final GeneratedColumn<String> savedPath = GeneratedColumn<String>(
    'saved_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileTypeMeta = const VerificationMeta(
    'fileType',
  );
  @override
  late final GeneratedColumn<String> fileType = GeneratedColumn<String>(
    'file_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceAliasMeta = const VerificationMeta(
    'deviceAlias',
  );
  @override
  late final GeneratedColumn<String> deviceAlias = GeneratedColumn<String>(
    'device_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceFingerprintMeta = const VerificationMeta(
    'deviceFingerprint',
  );
  @override
  late final GeneratedColumn<String> deviceFingerprint =
      GeneratedColumn<String>(
        'device_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _encryptedMeta = const VerificationMeta(
    'encrypted',
  );
  @override
  late final GeneratedColumn<bool> encrypted = GeneratedColumn<bool>(
    'encrypted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("encrypted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _verifiedMeta = const VerificationMeta(
    'verified',
  );
  @override
  late final GeneratedColumn<bool> verified = GeneratedColumn<bool>(
    'verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("verified" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fileName,
    savedPath,
    fileSize,
    fileType,
    direction,
    deviceAlias,
    deviceFingerprint,
    encrypted,
    verified,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('saved_path')) {
      context.handle(
        _savedPathMeta,
        savedPath.isAcceptableOrUnknown(data['saved_path']!, _savedPathMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('file_type')) {
      context.handle(
        _fileTypeMeta,
        fileType.isAcceptableOrUnknown(data['file_type']!, _fileTypeMeta),
      );
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('device_alias')) {
      context.handle(
        _deviceAliasMeta,
        deviceAlias.isAcceptableOrUnknown(
          data['device_alias']!,
          _deviceAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deviceAliasMeta);
    }
    if (data.containsKey('device_fingerprint')) {
      context.handle(
        _deviceFingerprintMeta,
        deviceFingerprint.isAcceptableOrUnknown(
          data['device_fingerprint']!,
          _deviceFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('encrypted')) {
      context.handle(
        _encryptedMeta,
        encrypted.isAcceptableOrUnknown(data['encrypted']!, _encryptedMeta),
      );
    }
    if (data.containsKey('verified')) {
      context.handle(
        _verifiedMeta,
        verified.isAcceptableOrUnknown(data['verified']!, _verifiedMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      savedPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_path'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      fileType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_type'],
      ),
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      deviceAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_alias'],
      )!,
      deviceFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_fingerprint'],
      ),
      encrypted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}encrypted'],
      )!,
      verified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}verified'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $TransferRecordsTable createAlias(String alias) {
    return $TransferRecordsTable(attachedDatabase, alias);
  }
}

class TransferRecord extends DataClass implements Insertable<TransferRecord> {
  final int id;
  final String fileName;
  final String? savedPath;
  final int fileSize;
  final String? fileType;
  final String direction;
  final String deviceAlias;
  final String? deviceFingerprint;
  final bool encrypted;
  final bool verified;
  final DateTime timestamp;
  const TransferRecord({
    required this.id,
    required this.fileName,
    this.savedPath,
    required this.fileSize,
    this.fileType,
    required this.direction,
    required this.deviceAlias,
    this.deviceFingerprint,
    required this.encrypted,
    required this.verified,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || savedPath != null) {
      map['saved_path'] = Variable<String>(savedPath);
    }
    map['file_size'] = Variable<int>(fileSize);
    if (!nullToAbsent || fileType != null) {
      map['file_type'] = Variable<String>(fileType);
    }
    map['direction'] = Variable<String>(direction);
    map['device_alias'] = Variable<String>(deviceAlias);
    if (!nullToAbsent || deviceFingerprint != null) {
      map['device_fingerprint'] = Variable<String>(deviceFingerprint);
    }
    map['encrypted'] = Variable<bool>(encrypted);
    map['verified'] = Variable<bool>(verified);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  TransferRecordsCompanion toCompanion(bool nullToAbsent) {
    return TransferRecordsCompanion(
      id: Value(id),
      fileName: Value(fileName),
      savedPath: savedPath == null && nullToAbsent
          ? const Value.absent()
          : Value(savedPath),
      fileSize: Value(fileSize),
      fileType: fileType == null && nullToAbsent
          ? const Value.absent()
          : Value(fileType),
      direction: Value(direction),
      deviceAlias: Value(deviceAlias),
      deviceFingerprint: deviceFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceFingerprint),
      encrypted: Value(encrypted),
      verified: Value(verified),
      timestamp: Value(timestamp),
    );
  }

  factory TransferRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferRecord(
      id: serializer.fromJson<int>(json['id']),
      fileName: serializer.fromJson<String>(json['fileName']),
      savedPath: serializer.fromJson<String?>(json['savedPath']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      fileType: serializer.fromJson<String?>(json['fileType']),
      direction: serializer.fromJson<String>(json['direction']),
      deviceAlias: serializer.fromJson<String>(json['deviceAlias']),
      deviceFingerprint: serializer.fromJson<String?>(
        json['deviceFingerprint'],
      ),
      encrypted: serializer.fromJson<bool>(json['encrypted']),
      verified: serializer.fromJson<bool>(json['verified']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fileName': serializer.toJson<String>(fileName),
      'savedPath': serializer.toJson<String?>(savedPath),
      'fileSize': serializer.toJson<int>(fileSize),
      'fileType': serializer.toJson<String?>(fileType),
      'direction': serializer.toJson<String>(direction),
      'deviceAlias': serializer.toJson<String>(deviceAlias),
      'deviceFingerprint': serializer.toJson<String?>(deviceFingerprint),
      'encrypted': serializer.toJson<bool>(encrypted),
      'verified': serializer.toJson<bool>(verified),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  TransferRecord copyWith({
    int? id,
    String? fileName,
    Value<String?> savedPath = const Value.absent(),
    int? fileSize,
    Value<String?> fileType = const Value.absent(),
    String? direction,
    String? deviceAlias,
    Value<String?> deviceFingerprint = const Value.absent(),
    bool? encrypted,
    bool? verified,
    DateTime? timestamp,
  }) => TransferRecord(
    id: id ?? this.id,
    fileName: fileName ?? this.fileName,
    savedPath: savedPath.present ? savedPath.value : this.savedPath,
    fileSize: fileSize ?? this.fileSize,
    fileType: fileType.present ? fileType.value : this.fileType,
    direction: direction ?? this.direction,
    deviceAlias: deviceAlias ?? this.deviceAlias,
    deviceFingerprint: deviceFingerprint.present
        ? deviceFingerprint.value
        : this.deviceFingerprint,
    encrypted: encrypted ?? this.encrypted,
    verified: verified ?? this.verified,
    timestamp: timestamp ?? this.timestamp,
  );
  TransferRecord copyWithCompanion(TransferRecordsCompanion data) {
    return TransferRecord(
      id: data.id.present ? data.id.value : this.id,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      savedPath: data.savedPath.present ? data.savedPath.value : this.savedPath,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      fileType: data.fileType.present ? data.fileType.value : this.fileType,
      direction: data.direction.present ? data.direction.value : this.direction,
      deviceAlias: data.deviceAlias.present
          ? data.deviceAlias.value
          : this.deviceAlias,
      deviceFingerprint: data.deviceFingerprint.present
          ? data.deviceFingerprint.value
          : this.deviceFingerprint,
      encrypted: data.encrypted.present ? data.encrypted.value : this.encrypted,
      verified: data.verified.present ? data.verified.value : this.verified,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferRecord(')
          ..write('id: $id, ')
          ..write('fileName: $fileName, ')
          ..write('savedPath: $savedPath, ')
          ..write('fileSize: $fileSize, ')
          ..write('fileType: $fileType, ')
          ..write('direction: $direction, ')
          ..write('deviceAlias: $deviceAlias, ')
          ..write('deviceFingerprint: $deviceFingerprint, ')
          ..write('encrypted: $encrypted, ')
          ..write('verified: $verified, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    fileName,
    savedPath,
    fileSize,
    fileType,
    direction,
    deviceAlias,
    deviceFingerprint,
    encrypted,
    verified,
    timestamp,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferRecord &&
          other.id == this.id &&
          other.fileName == this.fileName &&
          other.savedPath == this.savedPath &&
          other.fileSize == this.fileSize &&
          other.fileType == this.fileType &&
          other.direction == this.direction &&
          other.deviceAlias == this.deviceAlias &&
          other.deviceFingerprint == this.deviceFingerprint &&
          other.encrypted == this.encrypted &&
          other.verified == this.verified &&
          other.timestamp == this.timestamp);
}

class TransferRecordsCompanion extends UpdateCompanion<TransferRecord> {
  final Value<int> id;
  final Value<String> fileName;
  final Value<String?> savedPath;
  final Value<int> fileSize;
  final Value<String?> fileType;
  final Value<String> direction;
  final Value<String> deviceAlias;
  final Value<String?> deviceFingerprint;
  final Value<bool> encrypted;
  final Value<bool> verified;
  final Value<DateTime> timestamp;
  const TransferRecordsCompanion({
    this.id = const Value.absent(),
    this.fileName = const Value.absent(),
    this.savedPath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.fileType = const Value.absent(),
    this.direction = const Value.absent(),
    this.deviceAlias = const Value.absent(),
    this.deviceFingerprint = const Value.absent(),
    this.encrypted = const Value.absent(),
    this.verified = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  TransferRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String fileName,
    this.savedPath = const Value.absent(),
    required int fileSize,
    this.fileType = const Value.absent(),
    required String direction,
    required String deviceAlias,
    this.deviceFingerprint = const Value.absent(),
    this.encrypted = const Value.absent(),
    this.verified = const Value.absent(),
    required DateTime timestamp,
  }) : fileName = Value(fileName),
       fileSize = Value(fileSize),
       direction = Value(direction),
       deviceAlias = Value(deviceAlias),
       timestamp = Value(timestamp);
  static Insertable<TransferRecord> custom({
    Expression<int>? id,
    Expression<String>? fileName,
    Expression<String>? savedPath,
    Expression<int>? fileSize,
    Expression<String>? fileType,
    Expression<String>? direction,
    Expression<String>? deviceAlias,
    Expression<String>? deviceFingerprint,
    Expression<bool>? encrypted,
    Expression<bool>? verified,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fileName != null) 'file_name': fileName,
      if (savedPath != null) 'saved_path': savedPath,
      if (fileSize != null) 'file_size': fileSize,
      if (fileType != null) 'file_type': fileType,
      if (direction != null) 'direction': direction,
      if (deviceAlias != null) 'device_alias': deviceAlias,
      if (deviceFingerprint != null) 'device_fingerprint': deviceFingerprint,
      if (encrypted != null) 'encrypted': encrypted,
      if (verified != null) 'verified': verified,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  TransferRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? fileName,
    Value<String?>? savedPath,
    Value<int>? fileSize,
    Value<String?>? fileType,
    Value<String>? direction,
    Value<String>? deviceAlias,
    Value<String?>? deviceFingerprint,
    Value<bool>? encrypted,
    Value<bool>? verified,
    Value<DateTime>? timestamp,
  }) {
    return TransferRecordsCompanion(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      savedPath: savedPath ?? this.savedPath,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
      direction: direction ?? this.direction,
      deviceAlias: deviceAlias ?? this.deviceAlias,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
      encrypted: encrypted ?? this.encrypted,
      verified: verified ?? this.verified,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (savedPath.present) {
      map['saved_path'] = Variable<String>(savedPath.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (fileType.present) {
      map['file_type'] = Variable<String>(fileType.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (deviceAlias.present) {
      map['device_alias'] = Variable<String>(deviceAlias.value);
    }
    if (deviceFingerprint.present) {
      map['device_fingerprint'] = Variable<String>(deviceFingerprint.value);
    }
    if (encrypted.present) {
      map['encrypted'] = Variable<bool>(encrypted.value);
    }
    if (verified.present) {
      map['verified'] = Variable<bool>(verified.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferRecordsCompanion(')
          ..write('id: $id, ')
          ..write('fileName: $fileName, ')
          ..write('savedPath: $savedPath, ')
          ..write('fileSize: $fileSize, ')
          ..write('fileType: $fileType, ')
          ..write('direction: $direction, ')
          ..write('deviceAlias: $deviceAlias, ')
          ..write('deviceFingerprint: $deviceFingerprint, ')
          ..write('encrypted: $encrypted, ')
          ..write('verified: $verified, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $FavoriteDevicesTable extends FavoriteDevices
    with TableInfo<$FavoriteDevicesTable, FavoriteDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customNameMeta = const VerificationMeta(
    'customName',
  );
  @override
  late final GeneratedColumn<String> customName = GeneratedColumn<String>(
    'custom_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoAcceptMeta = const VerificationMeta(
    'autoAccept',
  );
  @override
  late final GeneratedColumn<bool> autoAccept = GeneratedColumn<bool>(
    'auto_accept',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_accept" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fingerprint,
    customName,
    autoAccept,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('custom_name')) {
      context.handle(
        _customNameMeta,
        customName.isAcceptableOrUnknown(data['custom_name']!, _customNameMeta),
      );
    }
    if (data.containsKey('auto_accept')) {
      context.handle(
        _autoAcceptMeta,
        autoAccept.isAcceptableOrUnknown(data['auto_accept']!, _autoAcceptMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fingerprint};
  @override
  FavoriteDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteDevice(
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      customName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_name'],
      ),
      autoAccept: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_accept'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoriteDevicesTable createAlias(String alias) {
    return $FavoriteDevicesTable(attachedDatabase, alias);
  }
}

class FavoriteDevice extends DataClass implements Insertable<FavoriteDevice> {
  final String fingerprint;
  final String? customName;
  final bool autoAccept;
  final DateTime addedAt;
  const FavoriteDevice({
    required this.fingerprint,
    this.customName,
    required this.autoAccept,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fingerprint'] = Variable<String>(fingerprint);
    if (!nullToAbsent || customName != null) {
      map['custom_name'] = Variable<String>(customName);
    }
    map['auto_accept'] = Variable<bool>(autoAccept);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteDevicesCompanion toCompanion(bool nullToAbsent) {
    return FavoriteDevicesCompanion(
      fingerprint: Value(fingerprint),
      customName: customName == null && nullToAbsent
          ? const Value.absent()
          : Value(customName),
      autoAccept: Value(autoAccept),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteDevice(
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      customName: serializer.fromJson<String?>(json['customName']),
      autoAccept: serializer.fromJson<bool>(json['autoAccept']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fingerprint': serializer.toJson<String>(fingerprint),
      'customName': serializer.toJson<String?>(customName),
      'autoAccept': serializer.toJson<bool>(autoAccept),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteDevice copyWith({
    String? fingerprint,
    Value<String?> customName = const Value.absent(),
    bool? autoAccept,
    DateTime? addedAt,
  }) => FavoriteDevice(
    fingerprint: fingerprint ?? this.fingerprint,
    customName: customName.present ? customName.value : this.customName,
    autoAccept: autoAccept ?? this.autoAccept,
    addedAt: addedAt ?? this.addedAt,
  );
  FavoriteDevice copyWithCompanion(FavoriteDevicesCompanion data) {
    return FavoriteDevice(
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      customName: data.customName.present
          ? data.customName.value
          : this.customName,
      autoAccept: data.autoAccept.present
          ? data.autoAccept.value
          : this.autoAccept,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteDevice(')
          ..write('fingerprint: $fingerprint, ')
          ..write('customName: $customName, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fingerprint, customName, autoAccept, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteDevice &&
          other.fingerprint == this.fingerprint &&
          other.customName == this.customName &&
          other.autoAccept == this.autoAccept &&
          other.addedAt == this.addedAt);
}

class FavoriteDevicesCompanion extends UpdateCompanion<FavoriteDevice> {
  final Value<String> fingerprint;
  final Value<String?> customName;
  final Value<bool> autoAccept;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteDevicesCompanion({
    this.fingerprint = const Value.absent(),
    this.customName = const Value.absent(),
    this.autoAccept = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteDevicesCompanion.insert({
    required String fingerprint,
    this.customName = const Value.absent(),
    this.autoAccept = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : fingerprint = Value(fingerprint),
       addedAt = Value(addedAt);
  static Insertable<FavoriteDevice> custom({
    Expression<String>? fingerprint,
    Expression<String>? customName,
    Expression<bool>? autoAccept,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (customName != null) 'custom_name': customName,
      if (autoAccept != null) 'auto_accept': autoAccept,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteDevicesCompanion copyWith({
    Value<String>? fingerprint,
    Value<String?>? customName,
    Value<bool>? autoAccept,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteDevicesCompanion(
      fingerprint: fingerprint ?? this.fingerprint,
      customName: customName ?? this.customName,
      autoAccept: autoAccept ?? this.autoAccept,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (customName.present) {
      map['custom_name'] = Variable<String>(customName.value);
    }
    if (autoAccept.present) {
      map['auto_accept'] = Variable<bool>(autoAccept.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteDevicesCompanion(')
          ..write('fingerprint: $fingerprint, ')
          ..write('customName: $customName, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TransferRecordsTable transferRecords = $TransferRecordsTable(
    this,
  );
  late final $FavoriteDevicesTable favoriteDevices = $FavoriteDevicesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    transferRecords,
    favoriteDevices,
  ];
}

typedef $$TransferRecordsTableCreateCompanionBuilder =
    TransferRecordsCompanion Function({
      Value<int> id,
      required String fileName,
      Value<String?> savedPath,
      required int fileSize,
      Value<String?> fileType,
      required String direction,
      required String deviceAlias,
      Value<String?> deviceFingerprint,
      Value<bool> encrypted,
      Value<bool> verified,
      required DateTime timestamp,
    });
typedef $$TransferRecordsTableUpdateCompanionBuilder =
    TransferRecordsCompanion Function({
      Value<int> id,
      Value<String> fileName,
      Value<String?> savedPath,
      Value<int> fileSize,
      Value<String?> fileType,
      Value<String> direction,
      Value<String> deviceAlias,
      Value<String?> deviceFingerprint,
      Value<bool> encrypted,
      Value<bool> verified,
      Value<DateTime> timestamp,
    });

class $$TransferRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TransferRecordsTable> {
  $$TransferRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedPath => $composableBuilder(
    column: $table.savedPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileType => $composableBuilder(
    column: $table.fileType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceAlias => $composableBuilder(
    column: $table.deviceAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceFingerprint => $composableBuilder(
    column: $table.deviceFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get encrypted => $composableBuilder(
    column: $table.encrypted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransferRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransferRecordsTable> {
  $$TransferRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedPath => $composableBuilder(
    column: $table.savedPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileType => $composableBuilder(
    column: $table.fileType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceAlias => $composableBuilder(
    column: $table.deviceAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceFingerprint => $composableBuilder(
    column: $table.deviceFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get encrypted => $composableBuilder(
    column: $table.encrypted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransferRecordsTable> {
  $$TransferRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get savedPath =>
      $composableBuilder(column: $table.savedPath, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get fileType =>
      $composableBuilder(column: $table.fileType, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get deviceAlias => $composableBuilder(
    column: $table.deviceAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceFingerprint => $composableBuilder(
    column: $table.deviceFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get encrypted =>
      $composableBuilder(column: $table.encrypted, builder: (column) => column);

  GeneratedColumn<bool> get verified =>
      $composableBuilder(column: $table.verified, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$TransferRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransferRecordsTable,
          TransferRecord,
          $$TransferRecordsTableFilterComposer,
          $$TransferRecordsTableOrderingComposer,
          $$TransferRecordsTableAnnotationComposer,
          $$TransferRecordsTableCreateCompanionBuilder,
          $$TransferRecordsTableUpdateCompanionBuilder,
          (
            TransferRecord,
            BaseReferences<
              _$AppDatabase,
              $TransferRecordsTable,
              TransferRecord
            >,
          ),
          TransferRecord,
          PrefetchHooks Function()
        > {
  $$TransferRecordsTableTableManager(
    _$AppDatabase db,
    $TransferRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String?> savedPath = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String?> fileType = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> deviceAlias = const Value.absent(),
                Value<String?> deviceFingerprint = const Value.absent(),
                Value<bool> encrypted = const Value.absent(),
                Value<bool> verified = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => TransferRecordsCompanion(
                id: id,
                fileName: fileName,
                savedPath: savedPath,
                fileSize: fileSize,
                fileType: fileType,
                direction: direction,
                deviceAlias: deviceAlias,
                deviceFingerprint: deviceFingerprint,
                encrypted: encrypted,
                verified: verified,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String fileName,
                Value<String?> savedPath = const Value.absent(),
                required int fileSize,
                Value<String?> fileType = const Value.absent(),
                required String direction,
                required String deviceAlias,
                Value<String?> deviceFingerprint = const Value.absent(),
                Value<bool> encrypted = const Value.absent(),
                Value<bool> verified = const Value.absent(),
                required DateTime timestamp,
              }) => TransferRecordsCompanion.insert(
                id: id,
                fileName: fileName,
                savedPath: savedPath,
                fileSize: fileSize,
                fileType: fileType,
                direction: direction,
                deviceAlias: deviceAlias,
                deviceFingerprint: deviceFingerprint,
                encrypted: encrypted,
                verified: verified,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransferRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransferRecordsTable,
      TransferRecord,
      $$TransferRecordsTableFilterComposer,
      $$TransferRecordsTableOrderingComposer,
      $$TransferRecordsTableAnnotationComposer,
      $$TransferRecordsTableCreateCompanionBuilder,
      $$TransferRecordsTableUpdateCompanionBuilder,
      (
        TransferRecord,
        BaseReferences<_$AppDatabase, $TransferRecordsTable, TransferRecord>,
      ),
      TransferRecord,
      PrefetchHooks Function()
    >;
typedef $$FavoriteDevicesTableCreateCompanionBuilder =
    FavoriteDevicesCompanion Function({
      required String fingerprint,
      Value<String?> customName,
      Value<bool> autoAccept,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$FavoriteDevicesTableUpdateCompanionBuilder =
    FavoriteDevicesCompanion Function({
      Value<String> fingerprint,
      Value<String?> customName,
      Value<bool> autoAccept,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$FavoriteDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoriteDevicesTable> {
  $$FavoriteDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoriteDevicesTable> {
  $$FavoriteDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoriteDevicesTable> {
  $$FavoriteDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoriteDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoriteDevicesTable,
          FavoriteDevice,
          $$FavoriteDevicesTableFilterComposer,
          $$FavoriteDevicesTableOrderingComposer,
          $$FavoriteDevicesTableAnnotationComposer,
          $$FavoriteDevicesTableCreateCompanionBuilder,
          $$FavoriteDevicesTableUpdateCompanionBuilder,
          (
            FavoriteDevice,
            BaseReferences<
              _$AppDatabase,
              $FavoriteDevicesTable,
              FavoriteDevice
            >,
          ),
          FavoriteDevice,
          PrefetchHooks Function()
        > {
  $$FavoriteDevicesTableTableManager(
    _$AppDatabase db,
    $FavoriteDevicesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fingerprint = const Value.absent(),
                Value<String?> customName = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteDevicesCompanion(
                fingerprint: fingerprint,
                customName: customName,
                autoAccept: autoAccept,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fingerprint,
                Value<String?> customName = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteDevicesCompanion.insert(
                fingerprint: fingerprint,
                customName: customName,
                autoAccept: autoAccept,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoriteDevicesTable,
      FavoriteDevice,
      $$FavoriteDevicesTableFilterComposer,
      $$FavoriteDevicesTableOrderingComposer,
      $$FavoriteDevicesTableAnnotationComposer,
      $$FavoriteDevicesTableCreateCompanionBuilder,
      $$FavoriteDevicesTableUpdateCompanionBuilder,
      (
        FavoriteDevice,
        BaseReferences<_$AppDatabase, $FavoriteDevicesTable, FavoriteDevice>,
      ),
      FavoriteDevice,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TransferRecordsTableTableManager get transferRecords =>
      $$TransferRecordsTableTableManager(_db, _db.transferRecords);
  $$FavoriteDevicesTableTableManager get favoriteDevices =>
      $$FavoriteDevicesTableTableManager(_db, _db.favoriteDevices);
}
