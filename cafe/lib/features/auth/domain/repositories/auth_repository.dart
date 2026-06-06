import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/either.dart';
import '../../data/models/profile_model.dart';

abstract class AuthRepository {
  Future<Either<Failure, Session?>> signInWithEmail(String email, String password);
  Future<Either<Failure, void>> signOut();
  Future<Either<Failure, ProfileModel>> getCurrentProfile();
  bool get isAuthenticated;
}
