class AppException implements Exception {
  final String userMessage;
  final String? debugInfo;

  AppException(this.userMessage, {this.debugInfo});

  @override
  String toString() {
    return 'AppException: $userMessage' +
        (debugInfo != null ? ' ($debugInfo)' : '');
  }
}

class ModelDownloadException extends AppException {
  ModelDownloadException(super.userMessage, {super.debugInfo});
}

class ModelInferenceException extends AppException {
  ModelInferenceException(super.userMessage, {super.debugInfo});
}

class ParseException extends AppException {
  ParseException(super.userMessage, {super.debugInfo});
}
