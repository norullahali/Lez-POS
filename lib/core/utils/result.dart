// lib/core/utils/result.dart

/// A utility class representing either a successful result `T` or an error `Exception`.
class Result<T> {
  final T? _value;
  final Exception? _error;
  final String? _errorMessage;

  const Result.success(this._value) : _error = null, _errorMessage = null;
  const Result.failure(this._error, [this._errorMessage]) : _value = null;

  bool get isSuccess => _error == null;
  bool get isFailure => !isSuccess;

  T get value {
    if (isFailure) {
      throw StateError('Cannot get value of a failure result');
    }
    return _value as T;
  }

  Exception get error {
    if (isSuccess) {
      throw StateError('Cannot get error of a success result');
    }
    return _error!;
  }

  String get errorMessage => _errorMessage ?? _error.toString();
}
