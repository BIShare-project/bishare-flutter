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

class $SyncPairsTable extends SyncPairs
    with TableInfo<$SyncPairsTable, SyncPair> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPairsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rootPathMeta = const VerificationMeta(
    'rootPath',
  );
  @override
  late final GeneratedColumn<String> rootPath = GeneratedColumn<String>(
    'root_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerFingerprintMeta = const VerificationMeta(
    'peerFingerprint',
  );
  @override
  late final GeneratedColumn<String> peerFingerprint = GeneratedColumn<String>(
    'peer_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: false,
    defaultValue: const Constant('twoWay'),
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('lanOnly'),
  );
  static const VerificationMeta _pausedMeta = const VerificationMeta('paused');
  @override
  late final GeneratedColumn<bool> paused = GeneratedColumn<bool>(
    'paused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("paused" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _selectiveRootsMeta = const VerificationMeta(
    'selectiveRoots',
  );
  @override
  late final GeneratedColumn<String> selectiveRoots = GeneratedColumn<String>(
    'selective_roots',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptionMeta = const VerificationMeta(
    'encryption',
  );
  @override
  late final GeneratedColumn<String> encryption = GeneratedColumn<String>(
    'encryption',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('aesgcm-x25519'),
  );
  static const VerificationMeta _cloudFolderIdMeta = const VerificationMeta(
    'cloudFolderId',
  );
  @override
  late final GeneratedColumn<String> cloudFolderId = GeneratedColumn<String>(
    'cloud_folder_id',
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
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rootPath,
    peerFingerprint,
    direction,
    mode,
    paused,
    selectiveRoots,
    encryption,
    cloudFolderId,
    createdAt,
    lastSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pairs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPair> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('root_path')) {
      context.handle(
        _rootPathMeta,
        rootPath.isAcceptableOrUnknown(data['root_path']!, _rootPathMeta),
      );
    } else if (isInserting) {
      context.missing(_rootPathMeta);
    }
    if (data.containsKey('peer_fingerprint')) {
      context.handle(
        _peerFingerprintMeta,
        peerFingerprint.isAcceptableOrUnknown(
          data['peer_fingerprint']!,
          _peerFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerFingerprintMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    if (data.containsKey('paused')) {
      context.handle(
        _pausedMeta,
        paused.isAcceptableOrUnknown(data['paused']!, _pausedMeta),
      );
    }
    if (data.containsKey('selective_roots')) {
      context.handle(
        _selectiveRootsMeta,
        selectiveRoots.isAcceptableOrUnknown(
          data['selective_roots']!,
          _selectiveRootsMeta,
        ),
      );
    }
    if (data.containsKey('encryption')) {
      context.handle(
        _encryptionMeta,
        encryption.isAcceptableOrUnknown(data['encryption']!, _encryptionMeta),
      );
    }
    if (data.containsKey('cloud_folder_id')) {
      context.handle(
        _cloudFolderIdMeta,
        cloudFolderId.isAcceptableOrUnknown(
          data['cloud_folder_id']!,
          _cloudFolderIdMeta,
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
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncPair map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPair(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      rootPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_path'],
      )!,
      peerFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_fingerprint'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      paused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}paused'],
      )!,
      selectiveRoots: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selective_roots'],
      ),
      encryption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encryption'],
      )!,
      cloudFolderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_folder_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
    );
  }

  @override
  $SyncPairsTable createAlias(String alias) {
    return $SyncPairsTable(attachedDatabase, alias);
  }
}

class SyncPair extends DataClass implements Insertable<SyncPair> {
  /// UUID (not autoincrement) — stable across DB resets and referenced by every
  /// other sync table + the cloud manifest.
  final String id;
  final String rootPath;
  final String peerFingerprint;

  /// 'twoWay' (v1) | 'pushOnly' | 'pullOnly' — enum ready, only twoWay in v1.
  final String direction;

  /// 'lanOnly' | 'lanCloud'. lanOnly NEVER touches api.bishare.app for content
  /// (positioning claim). lanCloud enables the Pro-gated store-and-forward (M3).
  final String mode;
  final bool paused;

  /// JSON array of included subtree path prefixes (§8.2); null = whole root.
  final String? selectiveRoots;

  /// Cloud-blob encryption scheme (§7.1). Forward-compat field so a future
  /// scheme migrates cleanly; v1 is always 'aesgcm-x25519'.
  final String encryption;

  /// Backend `folder_id` holding this pair's content-addressed store (M3).
  final String? cloudFolderId;
  final DateTime createdAt;
  final DateTime? lastSyncAt;
  const SyncPair({
    required this.id,
    required this.rootPath,
    required this.peerFingerprint,
    required this.direction,
    required this.mode,
    required this.paused,
    this.selectiveRoots,
    required this.encryption,
    this.cloudFolderId,
    required this.createdAt,
    this.lastSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['root_path'] = Variable<String>(rootPath);
    map['peer_fingerprint'] = Variable<String>(peerFingerprint);
    map['direction'] = Variable<String>(direction);
    map['mode'] = Variable<String>(mode);
    map['paused'] = Variable<bool>(paused);
    if (!nullToAbsent || selectiveRoots != null) {
      map['selective_roots'] = Variable<String>(selectiveRoots);
    }
    map['encryption'] = Variable<String>(encryption);
    if (!nullToAbsent || cloudFolderId != null) {
      map['cloud_folder_id'] = Variable<String>(cloudFolderId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    return map;
  }

  SyncPairsCompanion toCompanion(bool nullToAbsent) {
    return SyncPairsCompanion(
      id: Value(id),
      rootPath: Value(rootPath),
      peerFingerprint: Value(peerFingerprint),
      direction: Value(direction),
      mode: Value(mode),
      paused: Value(paused),
      selectiveRoots: selectiveRoots == null && nullToAbsent
          ? const Value.absent()
          : Value(selectiveRoots),
      encryption: Value(encryption),
      cloudFolderId: cloudFolderId == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudFolderId),
      createdAt: Value(createdAt),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
    );
  }

  factory SyncPair.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPair(
      id: serializer.fromJson<String>(json['id']),
      rootPath: serializer.fromJson<String>(json['rootPath']),
      peerFingerprint: serializer.fromJson<String>(json['peerFingerprint']),
      direction: serializer.fromJson<String>(json['direction']),
      mode: serializer.fromJson<String>(json['mode']),
      paused: serializer.fromJson<bool>(json['paused']),
      selectiveRoots: serializer.fromJson<String?>(json['selectiveRoots']),
      encryption: serializer.fromJson<String>(json['encryption']),
      cloudFolderId: serializer.fromJson<String?>(json['cloudFolderId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rootPath': serializer.toJson<String>(rootPath),
      'peerFingerprint': serializer.toJson<String>(peerFingerprint),
      'direction': serializer.toJson<String>(direction),
      'mode': serializer.toJson<String>(mode),
      'paused': serializer.toJson<bool>(paused),
      'selectiveRoots': serializer.toJson<String?>(selectiveRoots),
      'encryption': serializer.toJson<String>(encryption),
      'cloudFolderId': serializer.toJson<String?>(cloudFolderId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
    };
  }

  SyncPair copyWith({
    String? id,
    String? rootPath,
    String? peerFingerprint,
    String? direction,
    String? mode,
    bool? paused,
    Value<String?> selectiveRoots = const Value.absent(),
    String? encryption,
    Value<String?> cloudFolderId = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> lastSyncAt = const Value.absent(),
  }) => SyncPair(
    id: id ?? this.id,
    rootPath: rootPath ?? this.rootPath,
    peerFingerprint: peerFingerprint ?? this.peerFingerprint,
    direction: direction ?? this.direction,
    mode: mode ?? this.mode,
    paused: paused ?? this.paused,
    selectiveRoots: selectiveRoots.present
        ? selectiveRoots.value
        : this.selectiveRoots,
    encryption: encryption ?? this.encryption,
    cloudFolderId: cloudFolderId.present
        ? cloudFolderId.value
        : this.cloudFolderId,
    createdAt: createdAt ?? this.createdAt,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
  );
  SyncPair copyWithCompanion(SyncPairsCompanion data) {
    return SyncPair(
      id: data.id.present ? data.id.value : this.id,
      rootPath: data.rootPath.present ? data.rootPath.value : this.rootPath,
      peerFingerprint: data.peerFingerprint.present
          ? data.peerFingerprint.value
          : this.peerFingerprint,
      direction: data.direction.present ? data.direction.value : this.direction,
      mode: data.mode.present ? data.mode.value : this.mode,
      paused: data.paused.present ? data.paused.value : this.paused,
      selectiveRoots: data.selectiveRoots.present
          ? data.selectiveRoots.value
          : this.selectiveRoots,
      encryption: data.encryption.present
          ? data.encryption.value
          : this.encryption,
      cloudFolderId: data.cloudFolderId.present
          ? data.cloudFolderId.value
          : this.cloudFolderId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPair(')
          ..write('id: $id, ')
          ..write('rootPath: $rootPath, ')
          ..write('peerFingerprint: $peerFingerprint, ')
          ..write('direction: $direction, ')
          ..write('mode: $mode, ')
          ..write('paused: $paused, ')
          ..write('selectiveRoots: $selectiveRoots, ')
          ..write('encryption: $encryption, ')
          ..write('cloudFolderId: $cloudFolderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rootPath,
    peerFingerprint,
    direction,
    mode,
    paused,
    selectiveRoots,
    encryption,
    cloudFolderId,
    createdAt,
    lastSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPair &&
          other.id == this.id &&
          other.rootPath == this.rootPath &&
          other.peerFingerprint == this.peerFingerprint &&
          other.direction == this.direction &&
          other.mode == this.mode &&
          other.paused == this.paused &&
          other.selectiveRoots == this.selectiveRoots &&
          other.encryption == this.encryption &&
          other.cloudFolderId == this.cloudFolderId &&
          other.createdAt == this.createdAt &&
          other.lastSyncAt == this.lastSyncAt);
}

class SyncPairsCompanion extends UpdateCompanion<SyncPair> {
  final Value<String> id;
  final Value<String> rootPath;
  final Value<String> peerFingerprint;
  final Value<String> direction;
  final Value<String> mode;
  final Value<bool> paused;
  final Value<String?> selectiveRoots;
  final Value<String> encryption;
  final Value<String?> cloudFolderId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastSyncAt;
  final Value<int> rowid;
  const SyncPairsCompanion({
    this.id = const Value.absent(),
    this.rootPath = const Value.absent(),
    this.peerFingerprint = const Value.absent(),
    this.direction = const Value.absent(),
    this.mode = const Value.absent(),
    this.paused = const Value.absent(),
    this.selectiveRoots = const Value.absent(),
    this.encryption = const Value.absent(),
    this.cloudFolderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPairsCompanion.insert({
    required String id,
    required String rootPath,
    required String peerFingerprint,
    this.direction = const Value.absent(),
    this.mode = const Value.absent(),
    this.paused = const Value.absent(),
    this.selectiveRoots = const Value.absent(),
    this.encryption = const Value.absent(),
    this.cloudFolderId = const Value.absent(),
    required DateTime createdAt,
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       rootPath = Value(rootPath),
       peerFingerprint = Value(peerFingerprint),
       createdAt = Value(createdAt);
  static Insertable<SyncPair> custom({
    Expression<String>? id,
    Expression<String>? rootPath,
    Expression<String>? peerFingerprint,
    Expression<String>? direction,
    Expression<String>? mode,
    Expression<bool>? paused,
    Expression<String>? selectiveRoots,
    Expression<String>? encryption,
    Expression<String>? cloudFolderId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rootPath != null) 'root_path': rootPath,
      if (peerFingerprint != null) 'peer_fingerprint': peerFingerprint,
      if (direction != null) 'direction': direction,
      if (mode != null) 'mode': mode,
      if (paused != null) 'paused': paused,
      if (selectiveRoots != null) 'selective_roots': selectiveRoots,
      if (encryption != null) 'encryption': encryption,
      if (cloudFolderId != null) 'cloud_folder_id': cloudFolderId,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPairsCompanion copyWith({
    Value<String>? id,
    Value<String>? rootPath,
    Value<String>? peerFingerprint,
    Value<String>? direction,
    Value<String>? mode,
    Value<bool>? paused,
    Value<String?>? selectiveRoots,
    Value<String>? encryption,
    Value<String?>? cloudFolderId,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastSyncAt,
    Value<int>? rowid,
  }) {
    return SyncPairsCompanion(
      id: id ?? this.id,
      rootPath: rootPath ?? this.rootPath,
      peerFingerprint: peerFingerprint ?? this.peerFingerprint,
      direction: direction ?? this.direction,
      mode: mode ?? this.mode,
      paused: paused ?? this.paused,
      selectiveRoots: selectiveRoots ?? this.selectiveRoots,
      encryption: encryption ?? this.encryption,
      cloudFolderId: cloudFolderId ?? this.cloudFolderId,
      createdAt: createdAt ?? this.createdAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rootPath.present) {
      map['root_path'] = Variable<String>(rootPath.value);
    }
    if (peerFingerprint.present) {
      map['peer_fingerprint'] = Variable<String>(peerFingerprint.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (paused.present) {
      map['paused'] = Variable<bool>(paused.value);
    }
    if (selectiveRoots.present) {
      map['selective_roots'] = Variable<String>(selectiveRoots.value);
    }
    if (encryption.present) {
      map['encryption'] = Variable<String>(encryption.value);
    }
    if (cloudFolderId.present) {
      map['cloud_folder_id'] = Variable<String>(cloudFolderId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPairsCompanion(')
          ..write('id: $id, ')
          ..write('rootPath: $rootPath, ')
          ..write('peerFingerprint: $peerFingerprint, ')
          ..write('direction: $direction, ')
          ..write('mode: $mode, ')
          ..write('paused: $paused, ')
          ..write('selectiveRoots: $selectiveRoots, ')
          ..write('encryption: $encryption, ')
          ..write('cloudFolderId: $cloudFolderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncEntriesTable extends SyncEntries
    with TableInfo<$SyncEntriesTable, SyncEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<String> pairId = GeneratedColumn<String>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mtimeMsMeta = const VerificationMeta(
    'mtimeMs',
  );
  @override
  late final GeneratedColumn<int> mtimeMs = GeneratedColumn<int>(
    'mtime_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirMeta = const VerificationMeta('isDir');
  @override
  late final GeneratedColumn<bool> isDir = GeneratedColumn<bool>(
    'is_dir',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dir" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _originFpMeta = const VerificationMeta(
    'originFp',
  );
  @override
  late final GeneratedColumn<String> originFp = GeneratedColumn<String>(
    'origin_fp',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _opCursorMeta = const VerificationMeta(
    'opCursor',
  );
  @override
  late final GeneratedColumn<int> opCursor = GeneratedColumn<int>(
    'op_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    pairId,
    path,
    size,
    mtimeMs,
    sha256,
    isDir,
    originFp,
    opCursor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('mtime_ms')) {
      context.handle(
        _mtimeMsMeta,
        mtimeMs.isAcceptableOrUnknown(data['mtime_ms']!, _mtimeMsMeta),
      );
    } else if (isInserting) {
      context.missing(_mtimeMsMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('is_dir')) {
      context.handle(
        _isDirMeta,
        isDir.isAcceptableOrUnknown(data['is_dir']!, _isDirMeta),
      );
    }
    if (data.containsKey('origin_fp')) {
      context.handle(
        _originFpMeta,
        originFp.isAcceptableOrUnknown(data['origin_fp']!, _originFpMeta),
      );
    }
    if (data.containsKey('op_cursor')) {
      context.handle(
        _opCursorMeta,
        opCursor.isAcceptableOrUnknown(data['op_cursor']!, _opCursorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pairId, path};
  @override
  SyncEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncEntry(
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pair_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      mtimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mtime_ms'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      isDir: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dir'],
      )!,
      originFp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_fp'],
      ),
      opCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}op_cursor'],
      )!,
    );
  }

  @override
  $SyncEntriesTable createAlias(String alias) {
    return $SyncEntriesTable(attachedDatabase, alias);
  }
}

class SyncEntry extends DataClass implements Insertable<SyncEntry> {
  final String pairId;
  final String path;
  final int size;
  final int mtimeMs;
  final String? sha256;
  final bool isDir;

  /// Fingerprint of the device that last authored this entry — feeds
  /// loop-prevention (`originFp`, §4.4).
  final String? originFp;

  /// Monotonic u64 op cursor (per pair per device) this entry was written at.
  final int opCursor;
  const SyncEntry({
    required this.pairId,
    required this.path,
    required this.size,
    required this.mtimeMs,
    this.sha256,
    required this.isDir,
    this.originFp,
    required this.opCursor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pair_id'] = Variable<String>(pairId);
    map['path'] = Variable<String>(path);
    map['size'] = Variable<int>(size);
    map['mtime_ms'] = Variable<int>(mtimeMs);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    map['is_dir'] = Variable<bool>(isDir);
    if (!nullToAbsent || originFp != null) {
      map['origin_fp'] = Variable<String>(originFp);
    }
    map['op_cursor'] = Variable<int>(opCursor);
    return map;
  }

  SyncEntriesCompanion toCompanion(bool nullToAbsent) {
    return SyncEntriesCompanion(
      pairId: Value(pairId),
      path: Value(path),
      size: Value(size),
      mtimeMs: Value(mtimeMs),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      isDir: Value(isDir),
      originFp: originFp == null && nullToAbsent
          ? const Value.absent()
          : Value(originFp),
      opCursor: Value(opCursor),
    );
  }

  factory SyncEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncEntry(
      pairId: serializer.fromJson<String>(json['pairId']),
      path: serializer.fromJson<String>(json['path']),
      size: serializer.fromJson<int>(json['size']),
      mtimeMs: serializer.fromJson<int>(json['mtimeMs']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      isDir: serializer.fromJson<bool>(json['isDir']),
      originFp: serializer.fromJson<String?>(json['originFp']),
      opCursor: serializer.fromJson<int>(json['opCursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pairId': serializer.toJson<String>(pairId),
      'path': serializer.toJson<String>(path),
      'size': serializer.toJson<int>(size),
      'mtimeMs': serializer.toJson<int>(mtimeMs),
      'sha256': serializer.toJson<String?>(sha256),
      'isDir': serializer.toJson<bool>(isDir),
      'originFp': serializer.toJson<String?>(originFp),
      'opCursor': serializer.toJson<int>(opCursor),
    };
  }

  SyncEntry copyWith({
    String? pairId,
    String? path,
    int? size,
    int? mtimeMs,
    Value<String?> sha256 = const Value.absent(),
    bool? isDir,
    Value<String?> originFp = const Value.absent(),
    int? opCursor,
  }) => SyncEntry(
    pairId: pairId ?? this.pairId,
    path: path ?? this.path,
    size: size ?? this.size,
    mtimeMs: mtimeMs ?? this.mtimeMs,
    sha256: sha256.present ? sha256.value : this.sha256,
    isDir: isDir ?? this.isDir,
    originFp: originFp.present ? originFp.value : this.originFp,
    opCursor: opCursor ?? this.opCursor,
  );
  SyncEntry copyWithCompanion(SyncEntriesCompanion data) {
    return SyncEntry(
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      path: data.path.present ? data.path.value : this.path,
      size: data.size.present ? data.size.value : this.size,
      mtimeMs: data.mtimeMs.present ? data.mtimeMs.value : this.mtimeMs,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      isDir: data.isDir.present ? data.isDir.value : this.isDir,
      originFp: data.originFp.present ? data.originFp.value : this.originFp,
      opCursor: data.opCursor.present ? data.opCursor.value : this.opCursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntry(')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('mtimeMs: $mtimeMs, ')
          ..write('sha256: $sha256, ')
          ..write('isDir: $isDir, ')
          ..write('originFp: $originFp, ')
          ..write('opCursor: $opCursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pairId,
    path,
    size,
    mtimeMs,
    sha256,
    isDir,
    originFp,
    opCursor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncEntry &&
          other.pairId == this.pairId &&
          other.path == this.path &&
          other.size == this.size &&
          other.mtimeMs == this.mtimeMs &&
          other.sha256 == this.sha256 &&
          other.isDir == this.isDir &&
          other.originFp == this.originFp &&
          other.opCursor == this.opCursor);
}

class SyncEntriesCompanion extends UpdateCompanion<SyncEntry> {
  final Value<String> pairId;
  final Value<String> path;
  final Value<int> size;
  final Value<int> mtimeMs;
  final Value<String?> sha256;
  final Value<bool> isDir;
  final Value<String?> originFp;
  final Value<int> opCursor;
  final Value<int> rowid;
  const SyncEntriesCompanion({
    this.pairId = const Value.absent(),
    this.path = const Value.absent(),
    this.size = const Value.absent(),
    this.mtimeMs = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.isDir = const Value.absent(),
    this.originFp = const Value.absent(),
    this.opCursor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncEntriesCompanion.insert({
    required String pairId,
    required String path,
    required int size,
    required int mtimeMs,
    this.sha256 = const Value.absent(),
    this.isDir = const Value.absent(),
    this.originFp = const Value.absent(),
    this.opCursor = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pairId = Value(pairId),
       path = Value(path),
       size = Value(size),
       mtimeMs = Value(mtimeMs);
  static Insertable<SyncEntry> custom({
    Expression<String>? pairId,
    Expression<String>? path,
    Expression<int>? size,
    Expression<int>? mtimeMs,
    Expression<String>? sha256,
    Expression<bool>? isDir,
    Expression<String>? originFp,
    Expression<int>? opCursor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pairId != null) 'pair_id': pairId,
      if (path != null) 'path': path,
      if (size != null) 'size': size,
      if (mtimeMs != null) 'mtime_ms': mtimeMs,
      if (sha256 != null) 'sha256': sha256,
      if (isDir != null) 'is_dir': isDir,
      if (originFp != null) 'origin_fp': originFp,
      if (opCursor != null) 'op_cursor': opCursor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncEntriesCompanion copyWith({
    Value<String>? pairId,
    Value<String>? path,
    Value<int>? size,
    Value<int>? mtimeMs,
    Value<String?>? sha256,
    Value<bool>? isDir,
    Value<String?>? originFp,
    Value<int>? opCursor,
    Value<int>? rowid,
  }) {
    return SyncEntriesCompanion(
      pairId: pairId ?? this.pairId,
      path: path ?? this.path,
      size: size ?? this.size,
      mtimeMs: mtimeMs ?? this.mtimeMs,
      sha256: sha256 ?? this.sha256,
      isDir: isDir ?? this.isDir,
      originFp: originFp ?? this.originFp,
      opCursor: opCursor ?? this.opCursor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pairId.present) {
      map['pair_id'] = Variable<String>(pairId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (mtimeMs.present) {
      map['mtime_ms'] = Variable<int>(mtimeMs.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (isDir.present) {
      map['is_dir'] = Variable<bool>(isDir.value);
    }
    if (originFp.present) {
      map['origin_fp'] = Variable<String>(originFp.value);
    }
    if (opCursor.present) {
      map['op_cursor'] = Variable<int>(opCursor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntriesCompanion(')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('mtimeMs: $mtimeMs, ')
          ..write('sha256: $sha256, ')
          ..write('isDir: $isDir, ')
          ..write('originFp: $originFp, ')
          ..write('opCursor: $opCursor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncTombstonesTable extends SyncTombstones
    with TableInfo<$SyncTombstonesTable, SyncTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<String> pairId = GeneratedColumn<String>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMsMeta = const VerificationMeta(
    'deletedAtMs',
  );
  @override
  late final GeneratedColumn<int> deletedAtMs = GeneratedColumn<int>(
    'deleted_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originFpMeta = const VerificationMeta(
    'originFp',
  );
  @override
  late final GeneratedColumn<String> originFp = GeneratedColumn<String>(
    'origin_fp',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [pairId, path, deletedAtMs, originFp];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('deleted_at_ms')) {
      context.handle(
        _deletedAtMsMeta,
        deletedAtMs.isAcceptableOrUnknown(
          data['deleted_at_ms']!,
          _deletedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMsMeta);
    }
    if (data.containsKey('origin_fp')) {
      context.handle(
        _originFpMeta,
        originFp.isAcceptableOrUnknown(data['origin_fp']!, _originFpMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pairId, path};
  @override
  SyncTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTombstone(
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pair_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      deletedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_ms'],
      )!,
      originFp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_fp'],
      ),
    );
  }

  @override
  $SyncTombstonesTable createAlias(String alias) {
    return $SyncTombstonesTable(attachedDatabase, alias);
  }
}

class SyncTombstone extends DataClass implements Insertable<SyncTombstone> {
  final String pairId;
  final String path;
  final int deletedAtMs;
  final String? originFp;
  const SyncTombstone({
    required this.pairId,
    required this.path,
    required this.deletedAtMs,
    this.originFp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pair_id'] = Variable<String>(pairId);
    map['path'] = Variable<String>(path);
    map['deleted_at_ms'] = Variable<int>(deletedAtMs);
    if (!nullToAbsent || originFp != null) {
      map['origin_fp'] = Variable<String>(originFp);
    }
    return map;
  }

  SyncTombstonesCompanion toCompanion(bool nullToAbsent) {
    return SyncTombstonesCompanion(
      pairId: Value(pairId),
      path: Value(path),
      deletedAtMs: Value(deletedAtMs),
      originFp: originFp == null && nullToAbsent
          ? const Value.absent()
          : Value(originFp),
    );
  }

  factory SyncTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTombstone(
      pairId: serializer.fromJson<String>(json['pairId']),
      path: serializer.fromJson<String>(json['path']),
      deletedAtMs: serializer.fromJson<int>(json['deletedAtMs']),
      originFp: serializer.fromJson<String?>(json['originFp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pairId': serializer.toJson<String>(pairId),
      'path': serializer.toJson<String>(path),
      'deletedAtMs': serializer.toJson<int>(deletedAtMs),
      'originFp': serializer.toJson<String?>(originFp),
    };
  }

  SyncTombstone copyWith({
    String? pairId,
    String? path,
    int? deletedAtMs,
    Value<String?> originFp = const Value.absent(),
  }) => SyncTombstone(
    pairId: pairId ?? this.pairId,
    path: path ?? this.path,
    deletedAtMs: deletedAtMs ?? this.deletedAtMs,
    originFp: originFp.present ? originFp.value : this.originFp,
  );
  SyncTombstone copyWithCompanion(SyncTombstonesCompanion data) {
    return SyncTombstone(
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      path: data.path.present ? data.path.value : this.path,
      deletedAtMs: data.deletedAtMs.present
          ? data.deletedAtMs.value
          : this.deletedAtMs,
      originFp: data.originFp.present ? data.originFp.value : this.originFp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstone(')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('deletedAtMs: $deletedAtMs, ')
          ..write('originFp: $originFp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pairId, path, deletedAtMs, originFp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTombstone &&
          other.pairId == this.pairId &&
          other.path == this.path &&
          other.deletedAtMs == this.deletedAtMs &&
          other.originFp == this.originFp);
}

class SyncTombstonesCompanion extends UpdateCompanion<SyncTombstone> {
  final Value<String> pairId;
  final Value<String> path;
  final Value<int> deletedAtMs;
  final Value<String?> originFp;
  final Value<int> rowid;
  const SyncTombstonesCompanion({
    this.pairId = const Value.absent(),
    this.path = const Value.absent(),
    this.deletedAtMs = const Value.absent(),
    this.originFp = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncTombstonesCompanion.insert({
    required String pairId,
    required String path,
    required int deletedAtMs,
    this.originFp = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pairId = Value(pairId),
       path = Value(path),
       deletedAtMs = Value(deletedAtMs);
  static Insertable<SyncTombstone> custom({
    Expression<String>? pairId,
    Expression<String>? path,
    Expression<int>? deletedAtMs,
    Expression<String>? originFp,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pairId != null) 'pair_id': pairId,
      if (path != null) 'path': path,
      if (deletedAtMs != null) 'deleted_at_ms': deletedAtMs,
      if (originFp != null) 'origin_fp': originFp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncTombstonesCompanion copyWith({
    Value<String>? pairId,
    Value<String>? path,
    Value<int>? deletedAtMs,
    Value<String?>? originFp,
    Value<int>? rowid,
  }) {
    return SyncTombstonesCompanion(
      pairId: pairId ?? this.pairId,
      path: path ?? this.path,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
      originFp: originFp ?? this.originFp,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pairId.present) {
      map['pair_id'] = Variable<String>(pairId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (deletedAtMs.present) {
      map['deleted_at_ms'] = Variable<int>(deletedAtMs.value);
    }
    if (originFp.present) {
      map['origin_fp'] = Variable<String>(originFp.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstonesCompanion(')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('deletedAtMs: $deletedAtMs, ')
          ..write('originFp: $originFp, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictsTable extends SyncConflicts
    with TableInfo<$SyncConflictsTable, SyncConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<String> pairId = GeneratedColumn<String>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loserCopyPathMeta = const VerificationMeta(
    'loserCopyPath',
  );
  @override
  late final GeneratedColumn<String> loserCopyPath = GeneratedColumn<String>(
    'loser_copy_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _winnerFpMeta = const VerificationMeta(
    'winnerFp',
  );
  @override
  late final GeneratedColumn<String> winnerFp = GeneratedColumn<String>(
    'winner_fp',
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
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pairId,
    path,
    loserCopyPath,
    winnerFp,
    createdAt,
    resolvedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('loser_copy_path')) {
      context.handle(
        _loserCopyPathMeta,
        loserCopyPath.isAcceptableOrUnknown(
          data['loser_copy_path']!,
          _loserCopyPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_loserCopyPathMeta);
    }
    if (data.containsKey('winner_fp')) {
      context.handle(
        _winnerFpMeta,
        winnerFp.isAcceptableOrUnknown(data['winner_fp']!, _winnerFpMeta),
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
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflict(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pair_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      loserCopyPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loser_copy_path'],
      )!,
      winnerFp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}winner_fp'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
    );
  }

  @override
  $SyncConflictsTable createAlias(String alias) {
    return $SyncConflictsTable(attachedDatabase, alias);
  }
}

class SyncConflict extends DataClass implements Insertable<SyncConflict> {
  final String id;
  final String pairId;
  final String path;
  final String loserCopyPath;
  final String? winnerFp;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  const SyncConflict({
    required this.id,
    required this.pairId,
    required this.path,
    required this.loserCopyPath,
    this.winnerFp,
    required this.createdAt,
    this.resolvedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pair_id'] = Variable<String>(pairId);
    map['path'] = Variable<String>(path);
    map['loser_copy_path'] = Variable<String>(loserCopyPath);
    if (!nullToAbsent || winnerFp != null) {
      map['winner_fp'] = Variable<String>(winnerFp);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    return map;
  }

  SyncConflictsCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictsCompanion(
      id: Value(id),
      pairId: Value(pairId),
      path: Value(path),
      loserCopyPath: Value(loserCopyPath),
      winnerFp: winnerFp == null && nullToAbsent
          ? const Value.absent()
          : Value(winnerFp),
      createdAt: Value(createdAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
    );
  }

  factory SyncConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflict(
      id: serializer.fromJson<String>(json['id']),
      pairId: serializer.fromJson<String>(json['pairId']),
      path: serializer.fromJson<String>(json['path']),
      loserCopyPath: serializer.fromJson<String>(json['loserCopyPath']),
      winnerFp: serializer.fromJson<String?>(json['winnerFp']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pairId': serializer.toJson<String>(pairId),
      'path': serializer.toJson<String>(path),
      'loserCopyPath': serializer.toJson<String>(loserCopyPath),
      'winnerFp': serializer.toJson<String?>(winnerFp),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
    };
  }

  SyncConflict copyWith({
    String? id,
    String? pairId,
    String? path,
    String? loserCopyPath,
    Value<String?> winnerFp = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> resolvedAt = const Value.absent(),
  }) => SyncConflict(
    id: id ?? this.id,
    pairId: pairId ?? this.pairId,
    path: path ?? this.path,
    loserCopyPath: loserCopyPath ?? this.loserCopyPath,
    winnerFp: winnerFp.present ? winnerFp.value : this.winnerFp,
    createdAt: createdAt ?? this.createdAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
  );
  SyncConflict copyWithCompanion(SyncConflictsCompanion data) {
    return SyncConflict(
      id: data.id.present ? data.id.value : this.id,
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      path: data.path.present ? data.path.value : this.path,
      loserCopyPath: data.loserCopyPath.present
          ? data.loserCopyPath.value
          : this.loserCopyPath,
      winnerFp: data.winnerFp.present ? data.winnerFp.value : this.winnerFp,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflict(')
          ..write('id: $id, ')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('loserCopyPath: $loserCopyPath, ')
          ..write('winnerFp: $winnerFp, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pairId,
    path,
    loserCopyPath,
    winnerFp,
    createdAt,
    resolvedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflict &&
          other.id == this.id &&
          other.pairId == this.pairId &&
          other.path == this.path &&
          other.loserCopyPath == this.loserCopyPath &&
          other.winnerFp == this.winnerFp &&
          other.createdAt == this.createdAt &&
          other.resolvedAt == this.resolvedAt);
}

class SyncConflictsCompanion extends UpdateCompanion<SyncConflict> {
  final Value<String> id;
  final Value<String> pairId;
  final Value<String> path;
  final Value<String> loserCopyPath;
  final Value<String?> winnerFp;
  final Value<DateTime> createdAt;
  final Value<DateTime?> resolvedAt;
  final Value<int> rowid;
  const SyncConflictsCompanion({
    this.id = const Value.absent(),
    this.pairId = const Value.absent(),
    this.path = const Value.absent(),
    this.loserCopyPath = const Value.absent(),
    this.winnerFp = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictsCompanion.insert({
    required String id,
    required String pairId,
    required String path,
    required String loserCopyPath,
    this.winnerFp = const Value.absent(),
    required DateTime createdAt,
    this.resolvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pairId = Value(pairId),
       path = Value(path),
       loserCopyPath = Value(loserCopyPath),
       createdAt = Value(createdAt);
  static Insertable<SyncConflict> custom({
    Expression<String>? id,
    Expression<String>? pairId,
    Expression<String>? path,
    Expression<String>? loserCopyPath,
    Expression<String>? winnerFp,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? resolvedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pairId != null) 'pair_id': pairId,
      if (path != null) 'path': path,
      if (loserCopyPath != null) 'loser_copy_path': loserCopyPath,
      if (winnerFp != null) 'winner_fp': winnerFp,
      if (createdAt != null) 'created_at': createdAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictsCompanion copyWith({
    Value<String>? id,
    Value<String>? pairId,
    Value<String>? path,
    Value<String>? loserCopyPath,
    Value<String?>? winnerFp,
    Value<DateTime>? createdAt,
    Value<DateTime?>? resolvedAt,
    Value<int>? rowid,
  }) {
    return SyncConflictsCompanion(
      id: id ?? this.id,
      pairId: pairId ?? this.pairId,
      path: path ?? this.path,
      loserCopyPath: loserCopyPath ?? this.loserCopyPath,
      winnerFp: winnerFp ?? this.winnerFp,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pairId.present) {
      map['pair_id'] = Variable<String>(pairId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (loserCopyPath.present) {
      map['loser_copy_path'] = Variable<String>(loserCopyPath.value);
    }
    if (winnerFp.present) {
      map['winner_fp'] = Variable<String>(winnerFp.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsCompanion(')
          ..write('id: $id, ')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('loserCopyPath: $loserCopyPath, ')
          ..write('winnerFp: $winnerFp, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncPeerStateTable extends SyncPeerState
    with TableInfo<$SyncPeerStateTable, SyncPeerStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPeerStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<String> pairId = GeneratedColumn<String>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownCursorMeta = const VerificationMeta(
    'ownCursor',
  );
  @override
  late final GeneratedColumn<int> ownCursor = GeneratedColumn<int>(
    'own_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _peerCursorMeta = const VerificationMeta(
    'peerCursor',
  );
  @override
  late final GeneratedColumn<int> peerCursor = GeneratedColumn<int>(
    'peer_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastLanSyncAtMeta = const VerificationMeta(
    'lastLanSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastLanSyncAt =
      GeneratedColumn<DateTime>(
        'last_lan_sync_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCloudPushAtMeta = const VerificationMeta(
    'lastCloudPushAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCloudPushAt =
      GeneratedColumn<DateTime>(
        'last_cloud_push_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cloudFingerprintMeta = const VerificationMeta(
    'cloudFingerprint',
  );
  @override
  late final GeneratedColumn<String> cloudFingerprint = GeneratedColumn<String>(
    'cloud_fingerprint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pairId,
    ownCursor,
    peerCursor,
    lastLanSyncAt,
    lastCloudPushAt,
    cloudFingerprint,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_peer_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPeerStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('own_cursor')) {
      context.handle(
        _ownCursorMeta,
        ownCursor.isAcceptableOrUnknown(data['own_cursor']!, _ownCursorMeta),
      );
    }
    if (data.containsKey('peer_cursor')) {
      context.handle(
        _peerCursorMeta,
        peerCursor.isAcceptableOrUnknown(data['peer_cursor']!, _peerCursorMeta),
      );
    }
    if (data.containsKey('last_lan_sync_at')) {
      context.handle(
        _lastLanSyncAtMeta,
        lastLanSyncAt.isAcceptableOrUnknown(
          data['last_lan_sync_at']!,
          _lastLanSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('last_cloud_push_at')) {
      context.handle(
        _lastCloudPushAtMeta,
        lastCloudPushAt.isAcceptableOrUnknown(
          data['last_cloud_push_at']!,
          _lastCloudPushAtMeta,
        ),
      );
    }
    if (data.containsKey('cloud_fingerprint')) {
      context.handle(
        _cloudFingerprintMeta,
        cloudFingerprint.isAcceptableOrUnknown(
          data['cloud_fingerprint']!,
          _cloudFingerprintMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pairId};
  @override
  SyncPeerStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPeerStateData(
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pair_id'],
      )!,
      ownCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}own_cursor'],
      )!,
      peerCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}peer_cursor'],
      )!,
      lastLanSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_lan_sync_at'],
      ),
      lastCloudPushAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_cloud_push_at'],
      ),
      cloudFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_fingerprint'],
      ),
    );
  }

  @override
  $SyncPeerStateTable createAlias(String alias) {
    return $SyncPeerStateTable(attachedDatabase, alias);
  }
}

class SyncPeerStateData extends DataClass
    implements Insertable<SyncPeerStateData> {
  final String pairId;

  /// This device's monotonic op cursor (bumped on every local change applied).
  final int ownCursor;

  /// Highest peer cursor we've fully reconciled (LAN delta handshake, §4.4).
  final int peerCursor;
  final DateTime? lastLanSyncAt;
  final DateTime? lastCloudPushAt;

  /// Last observed cloud beacon `(last_sync_at,total_files,total_size)` triple
  /// (§5.2) — a change means "pull the manifest". Serialized string.
  final String? cloudFingerprint;
  const SyncPeerStateData({
    required this.pairId,
    required this.ownCursor,
    required this.peerCursor,
    this.lastLanSyncAt,
    this.lastCloudPushAt,
    this.cloudFingerprint,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pair_id'] = Variable<String>(pairId);
    map['own_cursor'] = Variable<int>(ownCursor);
    map['peer_cursor'] = Variable<int>(peerCursor);
    if (!nullToAbsent || lastLanSyncAt != null) {
      map['last_lan_sync_at'] = Variable<DateTime>(lastLanSyncAt);
    }
    if (!nullToAbsent || lastCloudPushAt != null) {
      map['last_cloud_push_at'] = Variable<DateTime>(lastCloudPushAt);
    }
    if (!nullToAbsent || cloudFingerprint != null) {
      map['cloud_fingerprint'] = Variable<String>(cloudFingerprint);
    }
    return map;
  }

  SyncPeerStateCompanion toCompanion(bool nullToAbsent) {
    return SyncPeerStateCompanion(
      pairId: Value(pairId),
      ownCursor: Value(ownCursor),
      peerCursor: Value(peerCursor),
      lastLanSyncAt: lastLanSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLanSyncAt),
      lastCloudPushAt: lastCloudPushAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCloudPushAt),
      cloudFingerprint: cloudFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudFingerprint),
    );
  }

  factory SyncPeerStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPeerStateData(
      pairId: serializer.fromJson<String>(json['pairId']),
      ownCursor: serializer.fromJson<int>(json['ownCursor']),
      peerCursor: serializer.fromJson<int>(json['peerCursor']),
      lastLanSyncAt: serializer.fromJson<DateTime?>(json['lastLanSyncAt']),
      lastCloudPushAt: serializer.fromJson<DateTime?>(json['lastCloudPushAt']),
      cloudFingerprint: serializer.fromJson<String?>(json['cloudFingerprint']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pairId': serializer.toJson<String>(pairId),
      'ownCursor': serializer.toJson<int>(ownCursor),
      'peerCursor': serializer.toJson<int>(peerCursor),
      'lastLanSyncAt': serializer.toJson<DateTime?>(lastLanSyncAt),
      'lastCloudPushAt': serializer.toJson<DateTime?>(lastCloudPushAt),
      'cloudFingerprint': serializer.toJson<String?>(cloudFingerprint),
    };
  }

  SyncPeerStateData copyWith({
    String? pairId,
    int? ownCursor,
    int? peerCursor,
    Value<DateTime?> lastLanSyncAt = const Value.absent(),
    Value<DateTime?> lastCloudPushAt = const Value.absent(),
    Value<String?> cloudFingerprint = const Value.absent(),
  }) => SyncPeerStateData(
    pairId: pairId ?? this.pairId,
    ownCursor: ownCursor ?? this.ownCursor,
    peerCursor: peerCursor ?? this.peerCursor,
    lastLanSyncAt: lastLanSyncAt.present
        ? lastLanSyncAt.value
        : this.lastLanSyncAt,
    lastCloudPushAt: lastCloudPushAt.present
        ? lastCloudPushAt.value
        : this.lastCloudPushAt,
    cloudFingerprint: cloudFingerprint.present
        ? cloudFingerprint.value
        : this.cloudFingerprint,
  );
  SyncPeerStateData copyWithCompanion(SyncPeerStateCompanion data) {
    return SyncPeerStateData(
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      ownCursor: data.ownCursor.present ? data.ownCursor.value : this.ownCursor,
      peerCursor: data.peerCursor.present
          ? data.peerCursor.value
          : this.peerCursor,
      lastLanSyncAt: data.lastLanSyncAt.present
          ? data.lastLanSyncAt.value
          : this.lastLanSyncAt,
      lastCloudPushAt: data.lastCloudPushAt.present
          ? data.lastCloudPushAt.value
          : this.lastCloudPushAt,
      cloudFingerprint: data.cloudFingerprint.present
          ? data.cloudFingerprint.value
          : this.cloudFingerprint,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPeerStateData(')
          ..write('pairId: $pairId, ')
          ..write('ownCursor: $ownCursor, ')
          ..write('peerCursor: $peerCursor, ')
          ..write('lastLanSyncAt: $lastLanSyncAt, ')
          ..write('lastCloudPushAt: $lastCloudPushAt, ')
          ..write('cloudFingerprint: $cloudFingerprint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pairId,
    ownCursor,
    peerCursor,
    lastLanSyncAt,
    lastCloudPushAt,
    cloudFingerprint,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPeerStateData &&
          other.pairId == this.pairId &&
          other.ownCursor == this.ownCursor &&
          other.peerCursor == this.peerCursor &&
          other.lastLanSyncAt == this.lastLanSyncAt &&
          other.lastCloudPushAt == this.lastCloudPushAt &&
          other.cloudFingerprint == this.cloudFingerprint);
}

class SyncPeerStateCompanion extends UpdateCompanion<SyncPeerStateData> {
  final Value<String> pairId;
  final Value<int> ownCursor;
  final Value<int> peerCursor;
  final Value<DateTime?> lastLanSyncAt;
  final Value<DateTime?> lastCloudPushAt;
  final Value<String?> cloudFingerprint;
  final Value<int> rowid;
  const SyncPeerStateCompanion({
    this.pairId = const Value.absent(),
    this.ownCursor = const Value.absent(),
    this.peerCursor = const Value.absent(),
    this.lastLanSyncAt = const Value.absent(),
    this.lastCloudPushAt = const Value.absent(),
    this.cloudFingerprint = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPeerStateCompanion.insert({
    required String pairId,
    this.ownCursor = const Value.absent(),
    this.peerCursor = const Value.absent(),
    this.lastLanSyncAt = const Value.absent(),
    this.lastCloudPushAt = const Value.absent(),
    this.cloudFingerprint = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pairId = Value(pairId);
  static Insertable<SyncPeerStateData> custom({
    Expression<String>? pairId,
    Expression<int>? ownCursor,
    Expression<int>? peerCursor,
    Expression<DateTime>? lastLanSyncAt,
    Expression<DateTime>? lastCloudPushAt,
    Expression<String>? cloudFingerprint,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pairId != null) 'pair_id': pairId,
      if (ownCursor != null) 'own_cursor': ownCursor,
      if (peerCursor != null) 'peer_cursor': peerCursor,
      if (lastLanSyncAt != null) 'last_lan_sync_at': lastLanSyncAt,
      if (lastCloudPushAt != null) 'last_cloud_push_at': lastCloudPushAt,
      if (cloudFingerprint != null) 'cloud_fingerprint': cloudFingerprint,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPeerStateCompanion copyWith({
    Value<String>? pairId,
    Value<int>? ownCursor,
    Value<int>? peerCursor,
    Value<DateTime?>? lastLanSyncAt,
    Value<DateTime?>? lastCloudPushAt,
    Value<String?>? cloudFingerprint,
    Value<int>? rowid,
  }) {
    return SyncPeerStateCompanion(
      pairId: pairId ?? this.pairId,
      ownCursor: ownCursor ?? this.ownCursor,
      peerCursor: peerCursor ?? this.peerCursor,
      lastLanSyncAt: lastLanSyncAt ?? this.lastLanSyncAt,
      lastCloudPushAt: lastCloudPushAt ?? this.lastCloudPushAt,
      cloudFingerprint: cloudFingerprint ?? this.cloudFingerprint,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pairId.present) {
      map['pair_id'] = Variable<String>(pairId.value);
    }
    if (ownCursor.present) {
      map['own_cursor'] = Variable<int>(ownCursor.value);
    }
    if (peerCursor.present) {
      map['peer_cursor'] = Variable<int>(peerCursor.value);
    }
    if (lastLanSyncAt.present) {
      map['last_lan_sync_at'] = Variable<DateTime>(lastLanSyncAt.value);
    }
    if (lastCloudPushAt.present) {
      map['last_cloud_push_at'] = Variable<DateTime>(lastCloudPushAt.value);
    }
    if (cloudFingerprint.present) {
      map['cloud_fingerprint'] = Variable<String>(cloudFingerprint.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPeerStateCompanion(')
          ..write('pairId: $pairId, ')
          ..write('ownCursor: $ownCursor, ')
          ..write('peerCursor: $peerCursor, ')
          ..write('lastLanSyncAt: $lastLanSyncAt, ')
          ..write('lastCloudPushAt: $lastCloudPushAt, ')
          ..write('cloudFingerprint: $cloudFingerprint, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpectedChangesTable extends ExpectedChanges
    with TableInfo<$ExpectedChangesTable, ExpectedChange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpectedChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<String> pairId = GeneratedColumn<String>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedSha256Meta = const VerificationMeta(
    'expectedSha256',
  );
  @override
  late final GeneratedColumn<String> expectedSha256 = GeneratedColumn<String>(
    'expected_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pairId,
    path,
    expectedSha256,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expected_changes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpectedChange> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('expected_sha256')) {
      context.handle(
        _expectedSha256Meta,
        expectedSha256.isAcceptableOrUnknown(
          data['expected_sha256']!,
          _expectedSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedSha256Meta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pairId, path};
  @override
  ExpectedChange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpectedChange(
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pair_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      expectedSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_sha256'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $ExpectedChangesTable createAlias(String alias) {
    return $ExpectedChangesTable(attachedDatabase, alias);
  }
}

class ExpectedChange extends DataClass implements Insertable<ExpectedChange> {
  final String pairId;
  final String path;
  final String expectedSha256;
  final DateTime expiresAt;
  const ExpectedChange({
    required this.pairId,
    required this.path,
    required this.expectedSha256,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pair_id'] = Variable<String>(pairId);
    map['path'] = Variable<String>(path);
    map['expected_sha256'] = Variable<String>(expectedSha256);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    return map;
  }

  ExpectedChangesCompanion toCompanion(bool nullToAbsent) {
    return ExpectedChangesCompanion(
      pairId: Value(pairId),
      path: Value(path),
      expectedSha256: Value(expectedSha256),
      expiresAt: Value(expiresAt),
    );
  }

  factory ExpectedChange.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpectedChange(
      pairId: serializer.fromJson<String>(json['pairId']),
      path: serializer.fromJson<String>(json['path']),
      expectedSha256: serializer.fromJson<String>(json['expectedSha256']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pairId': serializer.toJson<String>(pairId),
      'path': serializer.toJson<String>(path),
      'expectedSha256': serializer.toJson<String>(expectedSha256),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  ExpectedChange copyWith({
    String? pairId,
    String? path,
    String? expectedSha256,
    DateTime? expiresAt,
  }) => ExpectedChange(
    pairId: pairId ?? this.pairId,
    path: path ?? this.path,
    expectedSha256: expectedSha256 ?? this.expectedSha256,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  ExpectedChange copyWithCompanion(ExpectedChangesCompanion data) {
    return ExpectedChange(
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      path: data.path.present ? data.path.value : this.path,
      expectedSha256: data.expectedSha256.present
          ? data.expectedSha256.value
          : this.expectedSha256,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpectedChange(')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('expectedSha256: $expectedSha256, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pairId, path, expectedSha256, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpectedChange &&
          other.pairId == this.pairId &&
          other.path == this.path &&
          other.expectedSha256 == this.expectedSha256 &&
          other.expiresAt == this.expiresAt);
}

class ExpectedChangesCompanion extends UpdateCompanion<ExpectedChange> {
  final Value<String> pairId;
  final Value<String> path;
  final Value<String> expectedSha256;
  final Value<DateTime> expiresAt;
  final Value<int> rowid;
  const ExpectedChangesCompanion({
    this.pairId = const Value.absent(),
    this.path = const Value.absent(),
    this.expectedSha256 = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpectedChangesCompanion.insert({
    required String pairId,
    required String path,
    required String expectedSha256,
    required DateTime expiresAt,
    this.rowid = const Value.absent(),
  }) : pairId = Value(pairId),
       path = Value(path),
       expectedSha256 = Value(expectedSha256),
       expiresAt = Value(expiresAt);
  static Insertable<ExpectedChange> custom({
    Expression<String>? pairId,
    Expression<String>? path,
    Expression<String>? expectedSha256,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pairId != null) 'pair_id': pairId,
      if (path != null) 'path': path,
      if (expectedSha256 != null) 'expected_sha256': expectedSha256,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpectedChangesCompanion copyWith({
    Value<String>? pairId,
    Value<String>? path,
    Value<String>? expectedSha256,
    Value<DateTime>? expiresAt,
    Value<int>? rowid,
  }) {
    return ExpectedChangesCompanion(
      pairId: pairId ?? this.pairId,
      path: path ?? this.path,
      expectedSha256: expectedSha256 ?? this.expectedSha256,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pairId.present) {
      map['pair_id'] = Variable<String>(pairId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (expectedSha256.present) {
      map['expected_sha256'] = Variable<String>(expectedSha256.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpectedChangesCompanion(')
          ..write('pairId: $pairId, ')
          ..write('path: $path, ')
          ..write('expectedSha256: $expectedSha256, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCloudBlobsTable extends SyncCloudBlobs
    with TableInfo<$SyncCloudBlobsTable, SyncCloudBlob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCloudBlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<String> pairId = GeneratedColumn<String>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plaintextSha256Meta = const VerificationMeta(
    'plaintextSha256',
  );
  @override
  late final GeneratedColumn<String> plaintextSha256 = GeneratedColumn<String>(
    'plaintext_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudBlobSha256Meta = const VerificationMeta(
    'cloudBlobSha256',
  );
  @override
  late final GeneratedColumn<String> cloudBlobSha256 = GeneratedColumn<String>(
    'cloud_blob_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeCipherMeta = const VerificationMeta(
    'sizeCipher',
  );
  @override
  late final GeneratedColumn<int> sizeCipher = GeneratedColumn<int>(
    'size_cipher',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    pairId,
    plaintextSha256,
    cloudBlobSha256,
    fileId,
    sizeCipher,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cloud_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCloudBlob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('plaintext_sha256')) {
      context.handle(
        _plaintextSha256Meta,
        plaintextSha256.isAcceptableOrUnknown(
          data['plaintext_sha256']!,
          _plaintextSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_plaintextSha256Meta);
    }
    if (data.containsKey('cloud_blob_sha256')) {
      context.handle(
        _cloudBlobSha256Meta,
        cloudBlobSha256.isAcceptableOrUnknown(
          data['cloud_blob_sha256']!,
          _cloudBlobSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cloudBlobSha256Meta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('size_cipher')) {
      context.handle(
        _sizeCipherMeta,
        sizeCipher.isAcceptableOrUnknown(data['size_cipher']!, _sizeCipherMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pairId, plaintextSha256};
  @override
  SyncCloudBlob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCloudBlob(
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pair_id'],
      )!,
      plaintextSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plaintext_sha256'],
      )!,
      cloudBlobSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_blob_sha256'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      sizeCipher: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_cipher'],
      )!,
    );
  }

  @override
  $SyncCloudBlobsTable createAlias(String alias) {
    return $SyncCloudBlobsTable(attachedDatabase, alias);
  }
}

class SyncCloudBlob extends DataClass implements Insertable<SyncCloudBlob> {
  final String pairId;
  final String plaintextSha256;
  final String cloudBlobSha256;
  final String fileId;
  final int sizeCipher;
  const SyncCloudBlob({
    required this.pairId,
    required this.plaintextSha256,
    required this.cloudBlobSha256,
    required this.fileId,
    required this.sizeCipher,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pair_id'] = Variable<String>(pairId);
    map['plaintext_sha256'] = Variable<String>(plaintextSha256);
    map['cloud_blob_sha256'] = Variable<String>(cloudBlobSha256);
    map['file_id'] = Variable<String>(fileId);
    map['size_cipher'] = Variable<int>(sizeCipher);
    return map;
  }

  SyncCloudBlobsCompanion toCompanion(bool nullToAbsent) {
    return SyncCloudBlobsCompanion(
      pairId: Value(pairId),
      plaintextSha256: Value(plaintextSha256),
      cloudBlobSha256: Value(cloudBlobSha256),
      fileId: Value(fileId),
      sizeCipher: Value(sizeCipher),
    );
  }

  factory SyncCloudBlob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCloudBlob(
      pairId: serializer.fromJson<String>(json['pairId']),
      plaintextSha256: serializer.fromJson<String>(json['plaintextSha256']),
      cloudBlobSha256: serializer.fromJson<String>(json['cloudBlobSha256']),
      fileId: serializer.fromJson<String>(json['fileId']),
      sizeCipher: serializer.fromJson<int>(json['sizeCipher']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pairId': serializer.toJson<String>(pairId),
      'plaintextSha256': serializer.toJson<String>(plaintextSha256),
      'cloudBlobSha256': serializer.toJson<String>(cloudBlobSha256),
      'fileId': serializer.toJson<String>(fileId),
      'sizeCipher': serializer.toJson<int>(sizeCipher),
    };
  }

  SyncCloudBlob copyWith({
    String? pairId,
    String? plaintextSha256,
    String? cloudBlobSha256,
    String? fileId,
    int? sizeCipher,
  }) => SyncCloudBlob(
    pairId: pairId ?? this.pairId,
    plaintextSha256: plaintextSha256 ?? this.plaintextSha256,
    cloudBlobSha256: cloudBlobSha256 ?? this.cloudBlobSha256,
    fileId: fileId ?? this.fileId,
    sizeCipher: sizeCipher ?? this.sizeCipher,
  );
  SyncCloudBlob copyWithCompanion(SyncCloudBlobsCompanion data) {
    return SyncCloudBlob(
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      plaintextSha256: data.plaintextSha256.present
          ? data.plaintextSha256.value
          : this.plaintextSha256,
      cloudBlobSha256: data.cloudBlobSha256.present
          ? data.cloudBlobSha256.value
          : this.cloudBlobSha256,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      sizeCipher: data.sizeCipher.present
          ? data.sizeCipher.value
          : this.sizeCipher,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCloudBlob(')
          ..write('pairId: $pairId, ')
          ..write('plaintextSha256: $plaintextSha256, ')
          ..write('cloudBlobSha256: $cloudBlobSha256, ')
          ..write('fileId: $fileId, ')
          ..write('sizeCipher: $sizeCipher')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(pairId, plaintextSha256, cloudBlobSha256, fileId, sizeCipher);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCloudBlob &&
          other.pairId == this.pairId &&
          other.plaintextSha256 == this.plaintextSha256 &&
          other.cloudBlobSha256 == this.cloudBlobSha256 &&
          other.fileId == this.fileId &&
          other.sizeCipher == this.sizeCipher);
}

class SyncCloudBlobsCompanion extends UpdateCompanion<SyncCloudBlob> {
  final Value<String> pairId;
  final Value<String> plaintextSha256;
  final Value<String> cloudBlobSha256;
  final Value<String> fileId;
  final Value<int> sizeCipher;
  final Value<int> rowid;
  const SyncCloudBlobsCompanion({
    this.pairId = const Value.absent(),
    this.plaintextSha256 = const Value.absent(),
    this.cloudBlobSha256 = const Value.absent(),
    this.fileId = const Value.absent(),
    this.sizeCipher = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCloudBlobsCompanion.insert({
    required String pairId,
    required String plaintextSha256,
    required String cloudBlobSha256,
    required String fileId,
    this.sizeCipher = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pairId = Value(pairId),
       plaintextSha256 = Value(plaintextSha256),
       cloudBlobSha256 = Value(cloudBlobSha256),
       fileId = Value(fileId);
  static Insertable<SyncCloudBlob> custom({
    Expression<String>? pairId,
    Expression<String>? plaintextSha256,
    Expression<String>? cloudBlobSha256,
    Expression<String>? fileId,
    Expression<int>? sizeCipher,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pairId != null) 'pair_id': pairId,
      if (plaintextSha256 != null) 'plaintext_sha256': plaintextSha256,
      if (cloudBlobSha256 != null) 'cloud_blob_sha256': cloudBlobSha256,
      if (fileId != null) 'file_id': fileId,
      if (sizeCipher != null) 'size_cipher': sizeCipher,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCloudBlobsCompanion copyWith({
    Value<String>? pairId,
    Value<String>? plaintextSha256,
    Value<String>? cloudBlobSha256,
    Value<String>? fileId,
    Value<int>? sizeCipher,
    Value<int>? rowid,
  }) {
    return SyncCloudBlobsCompanion(
      pairId: pairId ?? this.pairId,
      plaintextSha256: plaintextSha256 ?? this.plaintextSha256,
      cloudBlobSha256: cloudBlobSha256 ?? this.cloudBlobSha256,
      fileId: fileId ?? this.fileId,
      sizeCipher: sizeCipher ?? this.sizeCipher,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pairId.present) {
      map['pair_id'] = Variable<String>(pairId.value);
    }
    if (plaintextSha256.present) {
      map['plaintext_sha256'] = Variable<String>(plaintextSha256.value);
    }
    if (cloudBlobSha256.present) {
      map['cloud_blob_sha256'] = Variable<String>(cloudBlobSha256.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (sizeCipher.present) {
      map['size_cipher'] = Variable<int>(sizeCipher.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCloudBlobsCompanion(')
          ..write('pairId: $pairId, ')
          ..write('plaintextSha256: $plaintextSha256, ')
          ..write('cloudBlobSha256: $cloudBlobSha256, ')
          ..write('fileId: $fileId, ')
          ..write('sizeCipher: $sizeCipher, ')
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
  late final $KnownDevicesTable knownDevices = $KnownDevicesTable(this);
  late final $ClipboardHistoryTable clipboardHistory = $ClipboardHistoryTable(
    this,
  );
  late final $SyncPairsTable syncPairs = $SyncPairsTable(this);
  late final $SyncEntriesTable syncEntries = $SyncEntriesTable(this);
  late final $SyncTombstonesTable syncTombstones = $SyncTombstonesTable(this);
  late final $SyncConflictsTable syncConflicts = $SyncConflictsTable(this);
  late final $SyncPeerStateTable syncPeerState = $SyncPeerStateTable(this);
  late final $ExpectedChangesTable expectedChanges = $ExpectedChangesTable(
    this,
  );
  late final $SyncCloudBlobsTable syncCloudBlobs = $SyncCloudBlobsTable(this);
  late final SyncDao syncDao = SyncDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    transferRecords,
    favoriteDevices,
    knownDevices,
    clipboardHistory,
    syncPairs,
    syncEntries,
    syncTombstones,
    syncConflicts,
    syncPeerState,
    expectedChanges,
    syncCloudBlobs,
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
typedef $$SyncPairsTableCreateCompanionBuilder =
    SyncPairsCompanion Function({
      required String id,
      required String rootPath,
      required String peerFingerprint,
      Value<String> direction,
      Value<String> mode,
      Value<bool> paused,
      Value<String?> selectiveRoots,
      Value<String> encryption,
      Value<String?> cloudFolderId,
      required DateTime createdAt,
      Value<DateTime?> lastSyncAt,
      Value<int> rowid,
    });
typedef $$SyncPairsTableUpdateCompanionBuilder =
    SyncPairsCompanion Function({
      Value<String> id,
      Value<String> rootPath,
      Value<String> peerFingerprint,
      Value<String> direction,
      Value<String> mode,
      Value<bool> paused,
      Value<String?> selectiveRoots,
      Value<String> encryption,
      Value<String?> cloudFolderId,
      Value<DateTime> createdAt,
      Value<DateTime?> lastSyncAt,
      Value<int> rowid,
    });

class $$SyncPairsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncPairsTable> {
  $$SyncPairsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootPath => $composableBuilder(
    column: $table.rootPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get paused => $composableBuilder(
    column: $table.paused,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectiveRoots => $composableBuilder(
    column: $table.selectiveRoots,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryption => $composableBuilder(
    column: $table.encryption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudFolderId => $composableBuilder(
    column: $table.cloudFolderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncPairsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncPairsTable> {
  $$SyncPairsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootPath => $composableBuilder(
    column: $table.rootPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get paused => $composableBuilder(
    column: $table.paused,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectiveRoots => $composableBuilder(
    column: $table.selectiveRoots,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryption => $composableBuilder(
    column: $table.encryption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudFolderId => $composableBuilder(
    column: $table.cloudFolderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncPairsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncPairsTable> {
  $$SyncPairsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rootPath =>
      $composableBuilder(column: $table.rootPath, builder: (column) => column);

  GeneratedColumn<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<bool> get paused =>
      $composableBuilder(column: $table.paused, builder: (column) => column);

  GeneratedColumn<String> get selectiveRoots => $composableBuilder(
    column: $table.selectiveRoots,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryption => $composableBuilder(
    column: $table.encryption,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudFolderId => $composableBuilder(
    column: $table.cloudFolderId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );
}

class $$SyncPairsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncPairsTable,
          SyncPair,
          $$SyncPairsTableFilterComposer,
          $$SyncPairsTableOrderingComposer,
          $$SyncPairsTableAnnotationComposer,
          $$SyncPairsTableCreateCompanionBuilder,
          $$SyncPairsTableUpdateCompanionBuilder,
          (SyncPair, BaseReferences<_$AppDatabase, $SyncPairsTable, SyncPair>),
          SyncPair,
          PrefetchHooks Function()
        > {
  $$SyncPairsTableTableManager(_$AppDatabase db, $SyncPairsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncPairsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncPairsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncPairsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> rootPath = const Value.absent(),
                Value<String> peerFingerprint = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<bool> paused = const Value.absent(),
                Value<String?> selectiveRoots = const Value.absent(),
                Value<String> encryption = const Value.absent(),
                Value<String?> cloudFolderId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncPairsCompanion(
                id: id,
                rootPath: rootPath,
                peerFingerprint: peerFingerprint,
                direction: direction,
                mode: mode,
                paused: paused,
                selectiveRoots: selectiveRoots,
                encryption: encryption,
                cloudFolderId: cloudFolderId,
                createdAt: createdAt,
                lastSyncAt: lastSyncAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String rootPath,
                required String peerFingerprint,
                Value<String> direction = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<bool> paused = const Value.absent(),
                Value<String?> selectiveRoots = const Value.absent(),
                Value<String> encryption = const Value.absent(),
                Value<String?> cloudFolderId = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncPairsCompanion.insert(
                id: id,
                rootPath: rootPath,
                peerFingerprint: peerFingerprint,
                direction: direction,
                mode: mode,
                paused: paused,
                selectiveRoots: selectiveRoots,
                encryption: encryption,
                cloudFolderId: cloudFolderId,
                createdAt: createdAt,
                lastSyncAt: lastSyncAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncPairsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncPairsTable,
      SyncPair,
      $$SyncPairsTableFilterComposer,
      $$SyncPairsTableOrderingComposer,
      $$SyncPairsTableAnnotationComposer,
      $$SyncPairsTableCreateCompanionBuilder,
      $$SyncPairsTableUpdateCompanionBuilder,
      (SyncPair, BaseReferences<_$AppDatabase, $SyncPairsTable, SyncPair>),
      SyncPair,
      PrefetchHooks Function()
    >;
typedef $$SyncEntriesTableCreateCompanionBuilder =
    SyncEntriesCompanion Function({
      required String pairId,
      required String path,
      required int size,
      required int mtimeMs,
      Value<String?> sha256,
      Value<bool> isDir,
      Value<String?> originFp,
      Value<int> opCursor,
      Value<int> rowid,
    });
typedef $$SyncEntriesTableUpdateCompanionBuilder =
    SyncEntriesCompanion Function({
      Value<String> pairId,
      Value<String> path,
      Value<int> size,
      Value<int> mtimeMs,
      Value<String?> sha256,
      Value<bool> isDir,
      Value<String?> originFp,
      Value<int> opCursor,
      Value<int> rowid,
    });

class $$SyncEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncEntriesTable> {
  $$SyncEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mtimeMs => $composableBuilder(
    column: $table.mtimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDir => $composableBuilder(
    column: $table.isDir,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originFp => $composableBuilder(
    column: $table.originFp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get opCursor => $composableBuilder(
    column: $table.opCursor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncEntriesTable> {
  $$SyncEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mtimeMs => $composableBuilder(
    column: $table.mtimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDir => $composableBuilder(
    column: $table.isDir,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originFp => $composableBuilder(
    column: $table.originFp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get opCursor => $composableBuilder(
    column: $table.opCursor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncEntriesTable> {
  $$SyncEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pairId =>
      $composableBuilder(column: $table.pairId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get mtimeMs =>
      $composableBuilder(column: $table.mtimeMs, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<bool> get isDir =>
      $composableBuilder(column: $table.isDir, builder: (column) => column);

  GeneratedColumn<String> get originFp =>
      $composableBuilder(column: $table.originFp, builder: (column) => column);

  GeneratedColumn<int> get opCursor =>
      $composableBuilder(column: $table.opCursor, builder: (column) => column);
}

class $$SyncEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncEntriesTable,
          SyncEntry,
          $$SyncEntriesTableFilterComposer,
          $$SyncEntriesTableOrderingComposer,
          $$SyncEntriesTableAnnotationComposer,
          $$SyncEntriesTableCreateCompanionBuilder,
          $$SyncEntriesTableUpdateCompanionBuilder,
          (
            SyncEntry,
            BaseReferences<_$AppDatabase, $SyncEntriesTable, SyncEntry>,
          ),
          SyncEntry,
          PrefetchHooks Function()
        > {
  $$SyncEntriesTableTableManager(_$AppDatabase db, $SyncEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pairId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> mtimeMs = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<bool> isDir = const Value.absent(),
                Value<String?> originFp = const Value.absent(),
                Value<int> opCursor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncEntriesCompanion(
                pairId: pairId,
                path: path,
                size: size,
                mtimeMs: mtimeMs,
                sha256: sha256,
                isDir: isDir,
                originFp: originFp,
                opCursor: opCursor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pairId,
                required String path,
                required int size,
                required int mtimeMs,
                Value<String?> sha256 = const Value.absent(),
                Value<bool> isDir = const Value.absent(),
                Value<String?> originFp = const Value.absent(),
                Value<int> opCursor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncEntriesCompanion.insert(
                pairId: pairId,
                path: path,
                size: size,
                mtimeMs: mtimeMs,
                sha256: sha256,
                isDir: isDir,
                originFp: originFp,
                opCursor: opCursor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncEntriesTable,
      SyncEntry,
      $$SyncEntriesTableFilterComposer,
      $$SyncEntriesTableOrderingComposer,
      $$SyncEntriesTableAnnotationComposer,
      $$SyncEntriesTableCreateCompanionBuilder,
      $$SyncEntriesTableUpdateCompanionBuilder,
      (SyncEntry, BaseReferences<_$AppDatabase, $SyncEntriesTable, SyncEntry>),
      SyncEntry,
      PrefetchHooks Function()
    >;
typedef $$SyncTombstonesTableCreateCompanionBuilder =
    SyncTombstonesCompanion Function({
      required String pairId,
      required String path,
      required int deletedAtMs,
      Value<String?> originFp,
      Value<int> rowid,
    });
typedef $$SyncTombstonesTableUpdateCompanionBuilder =
    SyncTombstonesCompanion Function({
      Value<String> pairId,
      Value<String> path,
      Value<int> deletedAtMs,
      Value<String?> originFp,
      Value<int> rowid,
    });

class $$SyncTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAtMs => $composableBuilder(
    column: $table.deletedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originFp => $composableBuilder(
    column: $table.originFp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAtMs => $composableBuilder(
    column: $table.deletedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originFp => $composableBuilder(
    column: $table.originFp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pairId =>
      $composableBuilder(column: $table.pairId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get deletedAtMs => $composableBuilder(
    column: $table.deletedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originFp =>
      $composableBuilder(column: $table.originFp, builder: (column) => column);
}

class $$SyncTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncTombstonesTable,
          SyncTombstone,
          $$SyncTombstonesTableFilterComposer,
          $$SyncTombstonesTableOrderingComposer,
          $$SyncTombstonesTableAnnotationComposer,
          $$SyncTombstonesTableCreateCompanionBuilder,
          $$SyncTombstonesTableUpdateCompanionBuilder,
          (
            SyncTombstone,
            BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
          ),
          SyncTombstone,
          PrefetchHooks Function()
        > {
  $$SyncTombstonesTableTableManager(
    _$AppDatabase db,
    $SyncTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pairId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> deletedAtMs = const Value.absent(),
                Value<String?> originFp = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTombstonesCompanion(
                pairId: pairId,
                path: path,
                deletedAtMs: deletedAtMs,
                originFp: originFp,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pairId,
                required String path,
                required int deletedAtMs,
                Value<String?> originFp = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTombstonesCompanion.insert(
                pairId: pairId,
                path: path,
                deletedAtMs: deletedAtMs,
                originFp: originFp,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncTombstonesTable,
      SyncTombstone,
      $$SyncTombstonesTableFilterComposer,
      $$SyncTombstonesTableOrderingComposer,
      $$SyncTombstonesTableAnnotationComposer,
      $$SyncTombstonesTableCreateCompanionBuilder,
      $$SyncTombstonesTableUpdateCompanionBuilder,
      (
        SyncTombstone,
        BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
      ),
      SyncTombstone,
      PrefetchHooks Function()
    >;
typedef $$SyncConflictsTableCreateCompanionBuilder =
    SyncConflictsCompanion Function({
      required String id,
      required String pairId,
      required String path,
      required String loserCopyPath,
      Value<String?> winnerFp,
      required DateTime createdAt,
      Value<DateTime?> resolvedAt,
      Value<int> rowid,
    });
typedef $$SyncConflictsTableUpdateCompanionBuilder =
    SyncConflictsCompanion Function({
      Value<String> id,
      Value<String> pairId,
      Value<String> path,
      Value<String> loserCopyPath,
      Value<String?> winnerFp,
      Value<DateTime> createdAt,
      Value<DateTime?> resolvedAt,
      Value<int> rowid,
    });

class $$SyncConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loserCopyPath => $composableBuilder(
    column: $table.loserCopyPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get winnerFp => $composableBuilder(
    column: $table.winnerFp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loserCopyPath => $composableBuilder(
    column: $table.loserCopyPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get winnerFp => $composableBuilder(
    column: $table.winnerFp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pairId =>
      $composableBuilder(column: $table.pairId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get loserCopyPath => $composableBuilder(
    column: $table.loserCopyPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get winnerFp =>
      $composableBuilder(column: $table.winnerFp, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );
}

class $$SyncConflictsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncConflictsTable,
          SyncConflict,
          $$SyncConflictsTableFilterComposer,
          $$SyncConflictsTableOrderingComposer,
          $$SyncConflictsTableAnnotationComposer,
          $$SyncConflictsTableCreateCompanionBuilder,
          $$SyncConflictsTableUpdateCompanionBuilder,
          (
            SyncConflict,
            BaseReferences<_$AppDatabase, $SyncConflictsTable, SyncConflict>,
          ),
          SyncConflict,
          PrefetchHooks Function()
        > {
  $$SyncConflictsTableTableManager(_$AppDatabase db, $SyncConflictsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pairId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> loserCopyPath = const Value.absent(),
                Value<String?> winnerFp = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion(
                id: id,
                pairId: pairId,
                path: path,
                loserCopyPath: loserCopyPath,
                winnerFp: winnerFp,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pairId,
                required String path,
                required String loserCopyPath,
                Value<String?> winnerFp = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion.insert(
                id: id,
                pairId: pairId,
                path: path,
                loserCopyPath: loserCopyPath,
                winnerFp: winnerFp,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncConflictsTable,
      SyncConflict,
      $$SyncConflictsTableFilterComposer,
      $$SyncConflictsTableOrderingComposer,
      $$SyncConflictsTableAnnotationComposer,
      $$SyncConflictsTableCreateCompanionBuilder,
      $$SyncConflictsTableUpdateCompanionBuilder,
      (
        SyncConflict,
        BaseReferences<_$AppDatabase, $SyncConflictsTable, SyncConflict>,
      ),
      SyncConflict,
      PrefetchHooks Function()
    >;
typedef $$SyncPeerStateTableCreateCompanionBuilder =
    SyncPeerStateCompanion Function({
      required String pairId,
      Value<int> ownCursor,
      Value<int> peerCursor,
      Value<DateTime?> lastLanSyncAt,
      Value<DateTime?> lastCloudPushAt,
      Value<String?> cloudFingerprint,
      Value<int> rowid,
    });
typedef $$SyncPeerStateTableUpdateCompanionBuilder =
    SyncPeerStateCompanion Function({
      Value<String> pairId,
      Value<int> ownCursor,
      Value<int> peerCursor,
      Value<DateTime?> lastLanSyncAt,
      Value<DateTime?> lastCloudPushAt,
      Value<String?> cloudFingerprint,
      Value<int> rowid,
    });

class $$SyncPeerStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncPeerStateTable> {
  $$SyncPeerStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ownCursor => $composableBuilder(
    column: $table.ownCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get peerCursor => $composableBuilder(
    column: $table.peerCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastLanSyncAt => $composableBuilder(
    column: $table.lastLanSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCloudPushAt => $composableBuilder(
    column: $table.lastCloudPushAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudFingerprint => $composableBuilder(
    column: $table.cloudFingerprint,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncPeerStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncPeerStateTable> {
  $$SyncPeerStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ownCursor => $composableBuilder(
    column: $table.ownCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get peerCursor => $composableBuilder(
    column: $table.peerCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastLanSyncAt => $composableBuilder(
    column: $table.lastLanSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCloudPushAt => $composableBuilder(
    column: $table.lastCloudPushAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudFingerprint => $composableBuilder(
    column: $table.cloudFingerprint,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncPeerStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncPeerStateTable> {
  $$SyncPeerStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pairId =>
      $composableBuilder(column: $table.pairId, builder: (column) => column);

  GeneratedColumn<int> get ownCursor =>
      $composableBuilder(column: $table.ownCursor, builder: (column) => column);

  GeneratedColumn<int> get peerCursor => $composableBuilder(
    column: $table.peerCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastLanSyncAt => $composableBuilder(
    column: $table.lastLanSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCloudPushAt => $composableBuilder(
    column: $table.lastCloudPushAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudFingerprint => $composableBuilder(
    column: $table.cloudFingerprint,
    builder: (column) => column,
  );
}

class $$SyncPeerStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncPeerStateTable,
          SyncPeerStateData,
          $$SyncPeerStateTableFilterComposer,
          $$SyncPeerStateTableOrderingComposer,
          $$SyncPeerStateTableAnnotationComposer,
          $$SyncPeerStateTableCreateCompanionBuilder,
          $$SyncPeerStateTableUpdateCompanionBuilder,
          (
            SyncPeerStateData,
            BaseReferences<
              _$AppDatabase,
              $SyncPeerStateTable,
              SyncPeerStateData
            >,
          ),
          SyncPeerStateData,
          PrefetchHooks Function()
        > {
  $$SyncPeerStateTableTableManager(_$AppDatabase db, $SyncPeerStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncPeerStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncPeerStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncPeerStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pairId = const Value.absent(),
                Value<int> ownCursor = const Value.absent(),
                Value<int> peerCursor = const Value.absent(),
                Value<DateTime?> lastLanSyncAt = const Value.absent(),
                Value<DateTime?> lastCloudPushAt = const Value.absent(),
                Value<String?> cloudFingerprint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncPeerStateCompanion(
                pairId: pairId,
                ownCursor: ownCursor,
                peerCursor: peerCursor,
                lastLanSyncAt: lastLanSyncAt,
                lastCloudPushAt: lastCloudPushAt,
                cloudFingerprint: cloudFingerprint,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pairId,
                Value<int> ownCursor = const Value.absent(),
                Value<int> peerCursor = const Value.absent(),
                Value<DateTime?> lastLanSyncAt = const Value.absent(),
                Value<DateTime?> lastCloudPushAt = const Value.absent(),
                Value<String?> cloudFingerprint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncPeerStateCompanion.insert(
                pairId: pairId,
                ownCursor: ownCursor,
                peerCursor: peerCursor,
                lastLanSyncAt: lastLanSyncAt,
                lastCloudPushAt: lastCloudPushAt,
                cloudFingerprint: cloudFingerprint,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncPeerStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncPeerStateTable,
      SyncPeerStateData,
      $$SyncPeerStateTableFilterComposer,
      $$SyncPeerStateTableOrderingComposer,
      $$SyncPeerStateTableAnnotationComposer,
      $$SyncPeerStateTableCreateCompanionBuilder,
      $$SyncPeerStateTableUpdateCompanionBuilder,
      (
        SyncPeerStateData,
        BaseReferences<_$AppDatabase, $SyncPeerStateTable, SyncPeerStateData>,
      ),
      SyncPeerStateData,
      PrefetchHooks Function()
    >;
typedef $$ExpectedChangesTableCreateCompanionBuilder =
    ExpectedChangesCompanion Function({
      required String pairId,
      required String path,
      required String expectedSha256,
      required DateTime expiresAt,
      Value<int> rowid,
    });
typedef $$ExpectedChangesTableUpdateCompanionBuilder =
    ExpectedChangesCompanion Function({
      Value<String> pairId,
      Value<String> path,
      Value<String> expectedSha256,
      Value<DateTime> expiresAt,
      Value<int> rowid,
    });

class $$ExpectedChangesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpectedChangesTable> {
  $$ExpectedChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedSha256 => $composableBuilder(
    column: $table.expectedSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpectedChangesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpectedChangesTable> {
  $$ExpectedChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedSha256 => $composableBuilder(
    column: $table.expectedSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpectedChangesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpectedChangesTable> {
  $$ExpectedChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pairId =>
      $composableBuilder(column: $table.pairId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get expectedSha256 => $composableBuilder(
    column: $table.expectedSha256,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$ExpectedChangesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpectedChangesTable,
          ExpectedChange,
          $$ExpectedChangesTableFilterComposer,
          $$ExpectedChangesTableOrderingComposer,
          $$ExpectedChangesTableAnnotationComposer,
          $$ExpectedChangesTableCreateCompanionBuilder,
          $$ExpectedChangesTableUpdateCompanionBuilder,
          (
            ExpectedChange,
            BaseReferences<
              _$AppDatabase,
              $ExpectedChangesTable,
              ExpectedChange
            >,
          ),
          ExpectedChange,
          PrefetchHooks Function()
        > {
  $$ExpectedChangesTableTableManager(
    _$AppDatabase db,
    $ExpectedChangesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpectedChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpectedChangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpectedChangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pairId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> expectedSha256 = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpectedChangesCompanion(
                pairId: pairId,
                path: path,
                expectedSha256: expectedSha256,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pairId,
                required String path,
                required String expectedSha256,
                required DateTime expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => ExpectedChangesCompanion.insert(
                pairId: pairId,
                path: path,
                expectedSha256: expectedSha256,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpectedChangesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpectedChangesTable,
      ExpectedChange,
      $$ExpectedChangesTableFilterComposer,
      $$ExpectedChangesTableOrderingComposer,
      $$ExpectedChangesTableAnnotationComposer,
      $$ExpectedChangesTableCreateCompanionBuilder,
      $$ExpectedChangesTableUpdateCompanionBuilder,
      (
        ExpectedChange,
        BaseReferences<_$AppDatabase, $ExpectedChangesTable, ExpectedChange>,
      ),
      ExpectedChange,
      PrefetchHooks Function()
    >;
typedef $$SyncCloudBlobsTableCreateCompanionBuilder =
    SyncCloudBlobsCompanion Function({
      required String pairId,
      required String plaintextSha256,
      required String cloudBlobSha256,
      required String fileId,
      Value<int> sizeCipher,
      Value<int> rowid,
    });
typedef $$SyncCloudBlobsTableUpdateCompanionBuilder =
    SyncCloudBlobsCompanion Function({
      Value<String> pairId,
      Value<String> plaintextSha256,
      Value<String> cloudBlobSha256,
      Value<String> fileId,
      Value<int> sizeCipher,
      Value<int> rowid,
    });

class $$SyncCloudBlobsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCloudBlobsTable> {
  $$SyncCloudBlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plaintextSha256 => $composableBuilder(
    column: $table.plaintextSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudBlobSha256 => $composableBuilder(
    column: $table.cloudBlobSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeCipher => $composableBuilder(
    column: $table.sizeCipher,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCloudBlobsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCloudBlobsTable> {
  $$SyncCloudBlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pairId => $composableBuilder(
    column: $table.pairId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plaintextSha256 => $composableBuilder(
    column: $table.plaintextSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudBlobSha256 => $composableBuilder(
    column: $table.cloudBlobSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeCipher => $composableBuilder(
    column: $table.sizeCipher,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCloudBlobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCloudBlobsTable> {
  $$SyncCloudBlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pairId =>
      $composableBuilder(column: $table.pairId, builder: (column) => column);

  GeneratedColumn<String> get plaintextSha256 => $composableBuilder(
    column: $table.plaintextSha256,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudBlobSha256 => $composableBuilder(
    column: $table.cloudBlobSha256,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<int> get sizeCipher => $composableBuilder(
    column: $table.sizeCipher,
    builder: (column) => column,
  );
}

class $$SyncCloudBlobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCloudBlobsTable,
          SyncCloudBlob,
          $$SyncCloudBlobsTableFilterComposer,
          $$SyncCloudBlobsTableOrderingComposer,
          $$SyncCloudBlobsTableAnnotationComposer,
          $$SyncCloudBlobsTableCreateCompanionBuilder,
          $$SyncCloudBlobsTableUpdateCompanionBuilder,
          (
            SyncCloudBlob,
            BaseReferences<_$AppDatabase, $SyncCloudBlobsTable, SyncCloudBlob>,
          ),
          SyncCloudBlob,
          PrefetchHooks Function()
        > {
  $$SyncCloudBlobsTableTableManager(
    _$AppDatabase db,
    $SyncCloudBlobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCloudBlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCloudBlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCloudBlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pairId = const Value.absent(),
                Value<String> plaintextSha256 = const Value.absent(),
                Value<String> cloudBlobSha256 = const Value.absent(),
                Value<String> fileId = const Value.absent(),
                Value<int> sizeCipher = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCloudBlobsCompanion(
                pairId: pairId,
                plaintextSha256: plaintextSha256,
                cloudBlobSha256: cloudBlobSha256,
                fileId: fileId,
                sizeCipher: sizeCipher,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pairId,
                required String plaintextSha256,
                required String cloudBlobSha256,
                required String fileId,
                Value<int> sizeCipher = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCloudBlobsCompanion.insert(
                pairId: pairId,
                plaintextSha256: plaintextSha256,
                cloudBlobSha256: cloudBlobSha256,
                fileId: fileId,
                sizeCipher: sizeCipher,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCloudBlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCloudBlobsTable,
      SyncCloudBlob,
      $$SyncCloudBlobsTableFilterComposer,
      $$SyncCloudBlobsTableOrderingComposer,
      $$SyncCloudBlobsTableAnnotationComposer,
      $$SyncCloudBlobsTableCreateCompanionBuilder,
      $$SyncCloudBlobsTableUpdateCompanionBuilder,
      (
        SyncCloudBlob,
        BaseReferences<_$AppDatabase, $SyncCloudBlobsTable, SyncCloudBlob>,
      ),
      SyncCloudBlob,
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
  $$SyncPairsTableTableManager get syncPairs =>
      $$SyncPairsTableTableManager(_db, _db.syncPairs);
  $$SyncEntriesTableTableManager get syncEntries =>
      $$SyncEntriesTableTableManager(_db, _db.syncEntries);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(_db, _db.syncTombstones);
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db, _db.syncConflicts);
  $$SyncPeerStateTableTableManager get syncPeerState =>
      $$SyncPeerStateTableTableManager(_db, _db.syncPeerState);
  $$ExpectedChangesTableTableManager get expectedChanges =>
      $$ExpectedChangesTableTableManager(_db, _db.expectedChanges);
  $$SyncCloudBlobsTableTableManager get syncCloudBlobs =>
      $$SyncCloudBlobsTableTableManager(_db, _db.syncCloudBlobs);
}
