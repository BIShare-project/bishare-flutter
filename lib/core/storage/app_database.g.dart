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

class $KnownDevicesTable extends KnownDevices
    with TableInfo<$KnownDevicesTable, KnownDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnownDevicesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceModelMeta = const VerificationMeta(
    'deviceModel',
  );
  @override
  late final GeneratedColumn<String> deviceModel = GeneratedColumn<String>(
    'device_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceTypeMeta = const VerificationMeta(
    'deviceType',
  );
  @override
  late final GeneratedColumn<String> deviceType = GeneratedColumn<String>(
    'device_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastIpMeta = const VerificationMeta('lastIp');
  @override
  late final GeneratedColumn<String> lastIp = GeneratedColumn<String>(
    'last_ip',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capabilitiesMeta = const VerificationMeta(
    'capabilities',
  );
  @override
  late final GeneratedColumn<String> capabilities = GeneratedColumn<String>(
    'capabilities',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fingerprint,
    alias,
    deviceModel,
    deviceType,
    lastSeen,
    lastIp,
    capabilities,
    workspaceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'known_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnownDevice> instance, {
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
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('device_model')) {
      context.handle(
        _deviceModelMeta,
        deviceModel.isAcceptableOrUnknown(
          data['device_model']!,
          _deviceModelMeta,
        ),
      );
    }
    if (data.containsKey('device_type')) {
      context.handle(
        _deviceTypeMeta,
        deviceType.isAcceptableOrUnknown(data['device_type']!, _deviceTypeMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    if (data.containsKey('last_ip')) {
      context.handle(
        _lastIpMeta,
        lastIp.isAcceptableOrUnknown(data['last_ip']!, _lastIpMeta),
      );
    }
    if (data.containsKey('capabilities')) {
      context.handle(
        _capabilitiesMeta,
        capabilities.isAcceptableOrUnknown(
          data['capabilities']!,
          _capabilitiesMeta,
        ),
      );
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fingerprint};
  @override
  KnownDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnownDevice(
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      deviceModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_model'],
      ),
      deviceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_type'],
      ),
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      )!,
      lastIp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_ip'],
      ),
      capabilities: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capabilities'],
      ),
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      ),
    );
  }

  @override
  $KnownDevicesTable createAlias(String alias) {
    return $KnownDevicesTable(attachedDatabase, alias);
  }
}

class KnownDevice extends DataClass implements Insertable<KnownDevice> {
  final String fingerprint;
  final String alias;
  final String? deviceModel;
  final String? deviceType;
  final DateTime lastSeen;
  final String? lastIp;
  final String? capabilities;
  final String? workspaceId;
  const KnownDevice({
    required this.fingerprint,
    required this.alias,
    this.deviceModel,
    this.deviceType,
    required this.lastSeen,
    this.lastIp,
    this.capabilities,
    this.workspaceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fingerprint'] = Variable<String>(fingerprint);
    map['alias'] = Variable<String>(alias);
    if (!nullToAbsent || deviceModel != null) {
      map['device_model'] = Variable<String>(deviceModel);
    }
    if (!nullToAbsent || deviceType != null) {
      map['device_type'] = Variable<String>(deviceType);
    }
    map['last_seen'] = Variable<DateTime>(lastSeen);
    if (!nullToAbsent || lastIp != null) {
      map['last_ip'] = Variable<String>(lastIp);
    }
    if (!nullToAbsent || capabilities != null) {
      map['capabilities'] = Variable<String>(capabilities);
    }
    if (!nullToAbsent || workspaceId != null) {
      map['workspace_id'] = Variable<String>(workspaceId);
    }
    return map;
  }

  KnownDevicesCompanion toCompanion(bool nullToAbsent) {
    return KnownDevicesCompanion(
      fingerprint: Value(fingerprint),
      alias: Value(alias),
      deviceModel: deviceModel == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceModel),
      deviceType: deviceType == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceType),
      lastSeen: Value(lastSeen),
      lastIp: lastIp == null && nullToAbsent
          ? const Value.absent()
          : Value(lastIp),
      capabilities: capabilities == null && nullToAbsent
          ? const Value.absent()
          : Value(capabilities),
      workspaceId: workspaceId == null && nullToAbsent
          ? const Value.absent()
          : Value(workspaceId),
    );
  }

  factory KnownDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnownDevice(
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      alias: serializer.fromJson<String>(json['alias']),
      deviceModel: serializer.fromJson<String?>(json['deviceModel']),
      deviceType: serializer.fromJson<String?>(json['deviceType']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
      lastIp: serializer.fromJson<String?>(json['lastIp']),
      capabilities: serializer.fromJson<String?>(json['capabilities']),
      workspaceId: serializer.fromJson<String?>(json['workspaceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fingerprint': serializer.toJson<String>(fingerprint),
      'alias': serializer.toJson<String>(alias),
      'deviceModel': serializer.toJson<String?>(deviceModel),
      'deviceType': serializer.toJson<String?>(deviceType),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
      'lastIp': serializer.toJson<String?>(lastIp),
      'capabilities': serializer.toJson<String?>(capabilities),
      'workspaceId': serializer.toJson<String?>(workspaceId),
    };
  }

  KnownDevice copyWith({
    String? fingerprint,
    String? alias,
    Value<String?> deviceModel = const Value.absent(),
    Value<String?> deviceType = const Value.absent(),
    DateTime? lastSeen,
    Value<String?> lastIp = const Value.absent(),
    Value<String?> capabilities = const Value.absent(),
    Value<String?> workspaceId = const Value.absent(),
  }) => KnownDevice(
    fingerprint: fingerprint ?? this.fingerprint,
    alias: alias ?? this.alias,
    deviceModel: deviceModel.present ? deviceModel.value : this.deviceModel,
    deviceType: deviceType.present ? deviceType.value : this.deviceType,
    lastSeen: lastSeen ?? this.lastSeen,
    lastIp: lastIp.present ? lastIp.value : this.lastIp,
    capabilities: capabilities.present ? capabilities.value : this.capabilities,
    workspaceId: workspaceId.present ? workspaceId.value : this.workspaceId,
  );
  KnownDevice copyWithCompanion(KnownDevicesCompanion data) {
    return KnownDevice(
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      alias: data.alias.present ? data.alias.value : this.alias,
      deviceModel: data.deviceModel.present
          ? data.deviceModel.value
          : this.deviceModel,
      deviceType: data.deviceType.present
          ? data.deviceType.value
          : this.deviceType,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      lastIp: data.lastIp.present ? data.lastIp.value : this.lastIp,
      capabilities: data.capabilities.present
          ? data.capabilities.value
          : this.capabilities,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnownDevice(')
          ..write('fingerprint: $fingerprint, ')
          ..write('alias: $alias, ')
          ..write('deviceModel: $deviceModel, ')
          ..write('deviceType: $deviceType, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastIp: $lastIp, ')
          ..write('capabilities: $capabilities, ')
          ..write('workspaceId: $workspaceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    fingerprint,
    alias,
    deviceModel,
    deviceType,
    lastSeen,
    lastIp,
    capabilities,
    workspaceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnownDevice &&
          other.fingerprint == this.fingerprint &&
          other.alias == this.alias &&
          other.deviceModel == this.deviceModel &&
          other.deviceType == this.deviceType &&
          other.lastSeen == this.lastSeen &&
          other.lastIp == this.lastIp &&
          other.capabilities == this.capabilities &&
          other.workspaceId == this.workspaceId);
}

class KnownDevicesCompanion extends UpdateCompanion<KnownDevice> {
  final Value<String> fingerprint;
  final Value<String> alias;
  final Value<String?> deviceModel;
  final Value<String?> deviceType;
  final Value<DateTime> lastSeen;
  final Value<String?> lastIp;
  final Value<String?> capabilities;
  final Value<String?> workspaceId;
  final Value<int> rowid;
  const KnownDevicesCompanion({
    this.fingerprint = const Value.absent(),
    this.alias = const Value.absent(),
    this.deviceModel = const Value.absent(),
    this.deviceType = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.lastIp = const Value.absent(),
    this.capabilities = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnownDevicesCompanion.insert({
    required String fingerprint,
    required String alias,
    this.deviceModel = const Value.absent(),
    this.deviceType = const Value.absent(),
    required DateTime lastSeen,
    this.lastIp = const Value.absent(),
    this.capabilities = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : fingerprint = Value(fingerprint),
       alias = Value(alias),
       lastSeen = Value(lastSeen);
  static Insertable<KnownDevice> custom({
    Expression<String>? fingerprint,
    Expression<String>? alias,
    Expression<String>? deviceModel,
    Expression<String>? deviceType,
    Expression<DateTime>? lastSeen,
    Expression<String>? lastIp,
    Expression<String>? capabilities,
    Expression<String>? workspaceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (alias != null) 'alias': alias,
      if (deviceModel != null) 'device_model': deviceModel,
      if (deviceType != null) 'device_type': deviceType,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (lastIp != null) 'last_ip': lastIp,
      if (capabilities != null) 'capabilities': capabilities,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnownDevicesCompanion copyWith({
    Value<String>? fingerprint,
    Value<String>? alias,
    Value<String?>? deviceModel,
    Value<String?>? deviceType,
    Value<DateTime>? lastSeen,
    Value<String?>? lastIp,
    Value<String?>? capabilities,
    Value<String?>? workspaceId,
    Value<int>? rowid,
  }) {
    return KnownDevicesCompanion(
      fingerprint: fingerprint ?? this.fingerprint,
      alias: alias ?? this.alias,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceType: deviceType ?? this.deviceType,
      lastSeen: lastSeen ?? this.lastSeen,
      lastIp: lastIp ?? this.lastIp,
      capabilities: capabilities ?? this.capabilities,
      workspaceId: workspaceId ?? this.workspaceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (deviceModel.present) {
      map['device_model'] = Variable<String>(deviceModel.value);
    }
    if (deviceType.present) {
      map['device_type'] = Variable<String>(deviceType.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (lastIp.present) {
      map['last_ip'] = Variable<String>(lastIp.value);
    }
    if (capabilities.present) {
      map['capabilities'] = Variable<String>(capabilities.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnownDevicesCompanion(')
          ..write('fingerprint: $fingerprint, ')
          ..write('alias: $alias, ')
          ..write('deviceModel: $deviceModel, ')
          ..write('deviceType: $deviceType, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastIp: $lastIp, ')
          ..write('capabilities: $capabilities, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClipboardHistoryTable extends ClipboardHistory
    with TableInfo<$ClipboardHistoryTable, ClipboardHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClipboardHistoryTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textContentMeta = const VerificationMeta(
    'textContent',
  );
  @override
  late final GeneratedColumn<String> textContent = GeneratedColumn<String>(
    'text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _previewPathMeta = const VerificationMeta(
    'previewPath',
  );
  @override
  late final GeneratedColumn<String> previewPath = GeneratedColumn<String>(
    'preview_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderAliasMeta = const VerificationMeta(
    'senderAlias',
  );
  @override
  late final GeneratedColumn<String> senderAlias = GeneratedColumn<String>(
    'sender_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderFingerprintMeta = const VerificationMeta(
    'senderFingerprint',
  );
  @override
  late final GeneratedColumn<String> senderFingerprint =
      GeneratedColumn<String>(
        'sender_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    textContent,
    mime,
    fileName,
    filePath,
    previewPath,
    senderAlias,
    senderFingerprint,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clipboard_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClipboardHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _textContentMeta,
        textContent.isAcceptableOrUnknown(data['text']!, _textContentMeta),
      );
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('preview_path')) {
      context.handle(
        _previewPathMeta,
        previewPath.isAcceptableOrUnknown(
          data['preview_path']!,
          _previewPathMeta,
        ),
      );
    }
    if (data.containsKey('sender_alias')) {
      context.handle(
        _senderAliasMeta,
        senderAlias.isAcceptableOrUnknown(
          data['sender_alias']!,
          _senderAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_senderAliasMeta);
    }
    if (data.containsKey('sender_fingerprint')) {
      context.handle(
        _senderFingerprintMeta,
        senderFingerprint.isAcceptableOrUnknown(
          data['sender_fingerprint']!,
          _senderFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClipboardHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClipboardHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      textContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      ),
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      previewPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview_path'],
      ),
      senderAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_alias'],
      )!,
      senderFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_fingerprint'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ClipboardHistoryTable createAlias(String alias) {
    return $ClipboardHistoryTable(attachedDatabase, alias);
  }
}

class ClipboardHistoryData extends DataClass
    implements Insertable<ClipboardHistoryData> {
  final int id;
  final String kind;
  final String? textContent;
  final String? mime;
  final String? fileName;
  final String? filePath;
  final String? previewPath;
  final String senderAlias;
  final String? senderFingerprint;
  final DateTime createdAt;
  const ClipboardHistoryData({
    required this.id,
    required this.kind,
    this.textContent,
    this.mime,
    this.fileName,
    this.filePath,
    this.previewPath,
    required this.senderAlias,
    this.senderFingerprint,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || textContent != null) {
      map['text'] = Variable<String>(textContent);
    }
    if (!nullToAbsent || mime != null) {
      map['mime'] = Variable<String>(mime);
    }
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    if (!nullToAbsent || previewPath != null) {
      map['preview_path'] = Variable<String>(previewPath);
    }
    map['sender_alias'] = Variable<String>(senderAlias);
    if (!nullToAbsent || senderFingerprint != null) {
      map['sender_fingerprint'] = Variable<String>(senderFingerprint);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ClipboardHistoryCompanion toCompanion(bool nullToAbsent) {
    return ClipboardHistoryCompanion(
      id: Value(id),
      kind: Value(kind),
      textContent: textContent == null && nullToAbsent
          ? const Value.absent()
          : Value(textContent),
      mime: mime == null && nullToAbsent ? const Value.absent() : Value(mime),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      previewPath: previewPath == null && nullToAbsent
          ? const Value.absent()
          : Value(previewPath),
      senderAlias: Value(senderAlias),
      senderFingerprint: senderFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(senderFingerprint),
      createdAt: Value(createdAt),
    );
  }

  factory ClipboardHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClipboardHistoryData(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      textContent: serializer.fromJson<String?>(json['textContent']),
      mime: serializer.fromJson<String?>(json['mime']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      previewPath: serializer.fromJson<String?>(json['previewPath']),
      senderAlias: serializer.fromJson<String>(json['senderAlias']),
      senderFingerprint: serializer.fromJson<String?>(
        json['senderFingerprint'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'textContent': serializer.toJson<String?>(textContent),
      'mime': serializer.toJson<String?>(mime),
      'fileName': serializer.toJson<String?>(fileName),
      'filePath': serializer.toJson<String?>(filePath),
      'previewPath': serializer.toJson<String?>(previewPath),
      'senderAlias': serializer.toJson<String>(senderAlias),
      'senderFingerprint': serializer.toJson<String?>(senderFingerprint),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ClipboardHistoryData copyWith({
    int? id,
    String? kind,
    Value<String?> textContent = const Value.absent(),
    Value<String?> mime = const Value.absent(),
    Value<String?> fileName = const Value.absent(),
    Value<String?> filePath = const Value.absent(),
    Value<String?> previewPath = const Value.absent(),
    String? senderAlias,
    Value<String?> senderFingerprint = const Value.absent(),
    DateTime? createdAt,
  }) => ClipboardHistoryData(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    textContent: textContent.present ? textContent.value : this.textContent,
    mime: mime.present ? mime.value : this.mime,
    fileName: fileName.present ? fileName.value : this.fileName,
    filePath: filePath.present ? filePath.value : this.filePath,
    previewPath: previewPath.present ? previewPath.value : this.previewPath,
    senderAlias: senderAlias ?? this.senderAlias,
    senderFingerprint: senderFingerprint.present
        ? senderFingerprint.value
        : this.senderFingerprint,
    createdAt: createdAt ?? this.createdAt,
  );
  ClipboardHistoryData copyWithCompanion(ClipboardHistoryCompanion data) {
    return ClipboardHistoryData(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      textContent: data.textContent.present
          ? data.textContent.value
          : this.textContent,
      mime: data.mime.present ? data.mime.value : this.mime,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      previewPath: data.previewPath.present
          ? data.previewPath.value
          : this.previewPath,
      senderAlias: data.senderAlias.present
          ? data.senderAlias.value
          : this.senderAlias,
      senderFingerprint: data.senderFingerprint.present
          ? data.senderFingerprint.value
          : this.senderFingerprint,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClipboardHistoryData(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('textContent: $textContent, ')
          ..write('mime: $mime, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('previewPath: $previewPath, ')
          ..write('senderAlias: $senderAlias, ')
          ..write('senderFingerprint: $senderFingerprint, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    textContent,
    mime,
    fileName,
    filePath,
    previewPath,
    senderAlias,
    senderFingerprint,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClipboardHistoryData &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.textContent == this.textContent &&
          other.mime == this.mime &&
          other.fileName == this.fileName &&
          other.filePath == this.filePath &&
          other.previewPath == this.previewPath &&
          other.senderAlias == this.senderAlias &&
          other.senderFingerprint == this.senderFingerprint &&
          other.createdAt == this.createdAt);
}

class ClipboardHistoryCompanion extends UpdateCompanion<ClipboardHistoryData> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String?> textContent;
  final Value<String?> mime;
  final Value<String?> fileName;
  final Value<String?> filePath;
  final Value<String?> previewPath;
  final Value<String> senderAlias;
  final Value<String?> senderFingerprint;
  final Value<DateTime> createdAt;
  const ClipboardHistoryCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.textContent = const Value.absent(),
    this.mime = const Value.absent(),
    this.fileName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.previewPath = const Value.absent(),
    this.senderAlias = const Value.absent(),
    this.senderFingerprint = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ClipboardHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    this.textContent = const Value.absent(),
    this.mime = const Value.absent(),
    this.fileName = const Value.absent(),
    this.filePath = const Value.absent(),
    this.previewPath = const Value.absent(),
    required String senderAlias,
    this.senderFingerprint = const Value.absent(),
    required DateTime createdAt,
  }) : kind = Value(kind),
       senderAlias = Value(senderAlias),
       createdAt = Value(createdAt);
  static Insertable<ClipboardHistoryData> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? textContent,
    Expression<String>? mime,
    Expression<String>? fileName,
    Expression<String>? filePath,
    Expression<String>? previewPath,
    Expression<String>? senderAlias,
    Expression<String>? senderFingerprint,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (textContent != null) 'text': textContent,
      if (mime != null) 'mime': mime,
      if (fileName != null) 'file_name': fileName,
      if (filePath != null) 'file_path': filePath,
      if (previewPath != null) 'preview_path': previewPath,
      if (senderAlias != null) 'sender_alias': senderAlias,
      if (senderFingerprint != null) 'sender_fingerprint': senderFingerprint,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ClipboardHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String?>? textContent,
    Value<String?>? mime,
    Value<String?>? fileName,
    Value<String?>? filePath,
    Value<String?>? previewPath,
    Value<String>? senderAlias,
    Value<String?>? senderFingerprint,
    Value<DateTime>? createdAt,
  }) {
    return ClipboardHistoryCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      textContent: textContent ?? this.textContent,
      mime: mime ?? this.mime,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      previewPath: previewPath ?? this.previewPath,
      senderAlias: senderAlias ?? this.senderAlias,
      senderFingerprint: senderFingerprint ?? this.senderFingerprint,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (textContent.present) {
      map['text'] = Variable<String>(textContent.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (previewPath.present) {
      map['preview_path'] = Variable<String>(previewPath.value);
    }
    if (senderAlias.present) {
      map['sender_alias'] = Variable<String>(senderAlias.value);
    }
    if (senderFingerprint.present) {
      map['sender_fingerprint'] = Variable<String>(senderFingerprint.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClipboardHistoryCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('textContent: $textContent, ')
          ..write('mime: $mime, ')
          ..write('fileName: $fileName, ')
          ..write('filePath: $filePath, ')
          ..write('previewPath: $previewPath, ')
          ..write('senderAlias: $senderAlias, ')
          ..write('senderFingerprint: $senderFingerprint, ')
          ..write('createdAt: $createdAt')
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
  late final $KnownDevicesTable knownDevices = $KnownDevicesTable(this);
  late final $ClipboardHistoryTable clipboardHistory = $ClipboardHistoryTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    transferRecords,
    favoriteDevices,
    knownDevices,
    clipboardHistory,
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
typedef $$KnownDevicesTableCreateCompanionBuilder =
    KnownDevicesCompanion Function({
      required String fingerprint,
      required String alias,
      Value<String?> deviceModel,
      Value<String?> deviceType,
      required DateTime lastSeen,
      Value<String?> lastIp,
      Value<String?> capabilities,
      Value<String?> workspaceId,
      Value<int> rowid,
    });
typedef $$KnownDevicesTableUpdateCompanionBuilder =
    KnownDevicesCompanion Function({
      Value<String> fingerprint,
      Value<String> alias,
      Value<String?> deviceModel,
      Value<String?> deviceType,
      Value<DateTime> lastSeen,
      Value<String?> lastIp,
      Value<String?> capabilities,
      Value<String?> workspaceId,
      Value<int> rowid,
    });

class $$KnownDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $KnownDevicesTable> {
  $$KnownDevicesTableFilterComposer({
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

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceModel => $composableBuilder(
    column: $table.deviceModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceType => $composableBuilder(
    column: $table.deviceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastIp => $composableBuilder(
    column: $table.lastIp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KnownDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $KnownDevicesTable> {
  $$KnownDevicesTableOrderingComposer({
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

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceModel => $composableBuilder(
    column: $table.deviceModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceType => $composableBuilder(
    column: $table.deviceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastIp => $composableBuilder(
    column: $table.lastIp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KnownDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnownDevicesTable> {
  $$KnownDevicesTableAnnotationComposer({
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

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<String> get deviceModel => $composableBuilder(
    column: $table.deviceModel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceType => $composableBuilder(
    column: $table.deviceType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<String> get lastIp =>
      $composableBuilder(column: $table.lastIp, builder: (column) => column);

  GeneratedColumn<String> get capabilities => $composableBuilder(
    column: $table.capabilities,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );
}

class $$KnownDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnownDevicesTable,
          KnownDevice,
          $$KnownDevicesTableFilterComposer,
          $$KnownDevicesTableOrderingComposer,
          $$KnownDevicesTableAnnotationComposer,
          $$KnownDevicesTableCreateCompanionBuilder,
          $$KnownDevicesTableUpdateCompanionBuilder,
          (
            KnownDevice,
            BaseReferences<_$AppDatabase, $KnownDevicesTable, KnownDevice>,
          ),
          KnownDevice,
          PrefetchHooks Function()
        > {
  $$KnownDevicesTableTableManager(_$AppDatabase db, $KnownDevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnownDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnownDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnownDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fingerprint = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<String?> deviceModel = const Value.absent(),
                Value<String?> deviceType = const Value.absent(),
                Value<DateTime> lastSeen = const Value.absent(),
                Value<String?> lastIp = const Value.absent(),
                Value<String?> capabilities = const Value.absent(),
                Value<String?> workspaceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownDevicesCompanion(
                fingerprint: fingerprint,
                alias: alias,
                deviceModel: deviceModel,
                deviceType: deviceType,
                lastSeen: lastSeen,
                lastIp: lastIp,
                capabilities: capabilities,
                workspaceId: workspaceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fingerprint,
                required String alias,
                Value<String?> deviceModel = const Value.absent(),
                Value<String?> deviceType = const Value.absent(),
                required DateTime lastSeen,
                Value<String?> lastIp = const Value.absent(),
                Value<String?> capabilities = const Value.absent(),
                Value<String?> workspaceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownDevicesCompanion.insert(
                fingerprint: fingerprint,
                alias: alias,
                deviceModel: deviceModel,
                deviceType: deviceType,
                lastSeen: lastSeen,
                lastIp: lastIp,
                capabilities: capabilities,
                workspaceId: workspaceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KnownDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnownDevicesTable,
      KnownDevice,
      $$KnownDevicesTableFilterComposer,
      $$KnownDevicesTableOrderingComposer,
      $$KnownDevicesTableAnnotationComposer,
      $$KnownDevicesTableCreateCompanionBuilder,
      $$KnownDevicesTableUpdateCompanionBuilder,
      (
        KnownDevice,
        BaseReferences<_$AppDatabase, $KnownDevicesTable, KnownDevice>,
      ),
      KnownDevice,
      PrefetchHooks Function()
    >;
typedef $$ClipboardHistoryTableCreateCompanionBuilder =
    ClipboardHistoryCompanion Function({
      Value<int> id,
      required String kind,
      Value<String?> textContent,
      Value<String?> mime,
      Value<String?> fileName,
      Value<String?> filePath,
      Value<String?> previewPath,
      required String senderAlias,
      Value<String?> senderFingerprint,
      required DateTime createdAt,
    });
typedef $$ClipboardHistoryTableUpdateCompanionBuilder =
    ClipboardHistoryCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String?> textContent,
      Value<String?> mime,
      Value<String?> fileName,
      Value<String?> filePath,
      Value<String?> previewPath,
      Value<String> senderAlias,
      Value<String?> senderFingerprint,
      Value<DateTime> createdAt,
    });

class $$ClipboardHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $ClipboardHistoryTable> {
  $$ClipboardHistoryTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textContent => $composableBuilder(
    column: $table.textContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previewPath => $composableBuilder(
    column: $table.previewPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderAlias => $composableBuilder(
    column: $table.senderAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderFingerprint => $composableBuilder(
    column: $table.senderFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClipboardHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ClipboardHistoryTable> {
  $$ClipboardHistoryTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textContent => $composableBuilder(
    column: $table.textContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previewPath => $composableBuilder(
    column: $table.previewPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderAlias => $composableBuilder(
    column: $table.senderAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderFingerprint => $composableBuilder(
    column: $table.senderFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClipboardHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClipboardHistoryTable> {
  $$ClipboardHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get textContent => $composableBuilder(
    column: $table.textContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get previewPath => $composableBuilder(
    column: $table.previewPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderAlias => $composableBuilder(
    column: $table.senderAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderFingerprint => $composableBuilder(
    column: $table.senderFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ClipboardHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClipboardHistoryTable,
          ClipboardHistoryData,
          $$ClipboardHistoryTableFilterComposer,
          $$ClipboardHistoryTableOrderingComposer,
          $$ClipboardHistoryTableAnnotationComposer,
          $$ClipboardHistoryTableCreateCompanionBuilder,
          $$ClipboardHistoryTableUpdateCompanionBuilder,
          (
            ClipboardHistoryData,
            BaseReferences<
              _$AppDatabase,
              $ClipboardHistoryTable,
              ClipboardHistoryData
            >,
          ),
          ClipboardHistoryData,
          PrefetchHooks Function()
        > {
  $$ClipboardHistoryTableTableManager(
    _$AppDatabase db,
    $ClipboardHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClipboardHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClipboardHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClipboardHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> textContent = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<String?> previewPath = const Value.absent(),
                Value<String> senderAlias = const Value.absent(),
                Value<String?> senderFingerprint = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ClipboardHistoryCompanion(
                id: id,
                kind: kind,
                textContent: textContent,
                mime: mime,
                fileName: fileName,
                filePath: filePath,
                previewPath: previewPath,
                senderAlias: senderAlias,
                senderFingerprint: senderFingerprint,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                Value<String?> textContent = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<String?> previewPath = const Value.absent(),
                required String senderAlias,
                Value<String?> senderFingerprint = const Value.absent(),
                required DateTime createdAt,
              }) => ClipboardHistoryCompanion.insert(
                id: id,
                kind: kind,
                textContent: textContent,
                mime: mime,
                fileName: fileName,
                filePath: filePath,
                previewPath: previewPath,
                senderAlias: senderAlias,
                senderFingerprint: senderFingerprint,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClipboardHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClipboardHistoryTable,
      ClipboardHistoryData,
      $$ClipboardHistoryTableFilterComposer,
      $$ClipboardHistoryTableOrderingComposer,
      $$ClipboardHistoryTableAnnotationComposer,
      $$ClipboardHistoryTableCreateCompanionBuilder,
      $$ClipboardHistoryTableUpdateCompanionBuilder,
      (
        ClipboardHistoryData,
        BaseReferences<
          _$AppDatabase,
          $ClipboardHistoryTable,
          ClipboardHistoryData
        >,
      ),
      ClipboardHistoryData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TransferRecordsTableTableManager get transferRecords =>
      $$TransferRecordsTableTableManager(_db, _db.transferRecords);
  $$FavoriteDevicesTableTableManager get favoriteDevices =>
      $$FavoriteDevicesTableTableManager(_db, _db.favoriteDevices);
  $$KnownDevicesTableTableManager get knownDevices =>
      $$KnownDevicesTableTableManager(_db, _db.knownDevices);
  $$ClipboardHistoryTableTableManager get clipboardHistory =>
      $$ClipboardHistoryTableTableManager(_db, _db.clipboardHistory);
}
