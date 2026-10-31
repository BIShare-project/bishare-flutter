/// Text that goes into an HTTP header: device names and file names.
///
/// Dart refuses a header value with characters outside printable ASCII before
/// the request leaves (FormatException "Invalid HTTP header field value"), and
/// a Mac's default name has one: "cakra’s Mac mini" (U+2019). Such a value is
/// percent-encoded, as the web client does with encodeURIComponent; the server
/// decodes X-File-Name and X-Sender-Alias, and the app decodes X-Owner-Alias
/// and room file names when it reads them back. Plain ASCII without '%' goes
/// as it is, so what already worked arrives unchanged.
library;

String headerText(String value) {
  for (final c in value.codeUnits) {
    if (c < 0x20 || c > 0x7e || c == 0x25 /* % */ ) {
      return Uri.encodeComponent(value);
    }
  }
  return value;
}

/// The other way: a name that came back from a header as it was sent. The web
/// client percent-encodes every alias and file name and the server stores them
/// as sent, so "Web Tester" arrives as "Web%20Tester". A value that merely
/// contains a stray '%' is kept as it is.
String? decodeHeaderText(String? raw) {
  if (raw == null || raw.isEmpty || !raw.contains('%')) return raw;
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    return raw;
  } on FormatException {
    return raw;
  }
}
