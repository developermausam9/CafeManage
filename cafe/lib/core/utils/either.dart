abstract class Either<L, R> {
  const Either();

  T fold<T>(T Function(L l) left, T Function(R r) right);
}

class Left<L, R> extends Either<L, R> {
  final L value;
  const Left(this.value);

  @override
  T fold<T>(T Function(L l) left, T Function(R r) right) => left(value);
}

class Right<L, R> extends Either<L, R> {
  final R value;
  const Right(this.value);

  @override
  T fold<T>(T Function(L l) left, T Function(R r) right) => right(value);
}
