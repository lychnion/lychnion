import 'dart:convert';

// Shared by the files in src/; not exported.

/// base64url without padding.
String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// base64url, with or without padding. Throws [FormatException].
List<int> unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// A publisher's name in records (`publisher`): lower case, digits, `.`,
/// `_` and `-`, for example `jp.city.kobe`.
final publisherNamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
